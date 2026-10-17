package dev.crew.crew

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.VpnService
import android.os.Build
import android.os.Bundle
import android.os.ParcelFileDescriptor
import android.os.ResultReceiver
import io.github.oviron.libmihomo.Clash
import io.github.oviron.libmihomo.TunInterface
import org.json.JSONObject
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * Android TUN lifecycle adapted for Crew's libmihomo-android bridge.
 *
 * FlClash's service is built against its own Go Mobile bridge, so its Core and
 * ServiceController classes cannot be dropped into this app unchanged. This
 * service keeps Crew's existing bridge and channel contract while adopting
 * the upstream lifecycle safeguards: non-blocking TUN, explicit cleanup,
 * serialized TUN start/stop, and memory-pressure handling.
 */
class MihomoVpnService : VpnService() {
    private val worker = Executors.newSingleThreadExecutor()
    private val tunLock = Any()

    @Volatile private var latestStartId = 0
    @Volatile private var activeSessionId: String? = null
    private var tunRunning = false

    private val tunInterface = object : TunInterface {
        override fun protect(fd: Int) {
            check(this@MihomoVpnService.protect(fd)) {
                "Could not protect Mihomo's outbound socket."
            }
        }

        override fun resolverProcess(
            protocol: Int,
            source: String,
            target: String,
            uid: Int,
        ): String = ""
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        latestStartId = startId
        val receiver = intent?.getResultReceiver()
        when (intent?.action) {
            ACTION_START -> {
                startForegroundCompat()
                val configPath = intent.getStringExtra(EXTRA_CONFIG_PATH)
                val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
                if (sessionId.isNullOrBlank()) {
                    receiver?.send(
                        Activity.RESULT_CANCELED,
                        Bundle().apply { putString(EXTRA_ERROR, "VPN session ID is missing.") },
                    )
                    if (activeSessionId == null) finishServiceIfCurrent(startId)
                    return START_NOT_STICKY
                }
                worker.execute {
                    try {
                        if (activeSessionId != null && activeSessionId != sessionId) {
                            stopMihomo()
                            activeSessionId = null
                        }
                        activeSessionId = sessionId
                        startMihomo(configPath ?: error("Mihomo config path is missing."))
                        receiver?.send(Activity.RESULT_OK, Bundle())
                    } catch (error: Throwable) {
                        val message = try {
                            if (activeSessionId == sessionId) {
                                stopMihomo()
                                activeSessionId = null
                            }
                            error.message ?: error.toString()
                        } catch (cleanupError: Throwable) {
                            "${error.message ?: error}; cleanup failed: " +
                                "${cleanupError.message ?: cleanupError}"
                        }
                        receiver?.send(
                            Activity.RESULT_CANCELED,
                            Bundle().apply { putString(EXTRA_ERROR, message) },
                        )
                        if (activeSessionId == null) finishServiceIfCurrent(startId)
                    }
                }
            }

            ACTION_STOP -> {
                val sessionId = intent.getStringExtra(EXTRA_SESSION_ID)
                if (sessionId.isNullOrBlank()) {
                    receiver?.send(
                        Activity.RESULT_CANCELED,
                        Bundle().apply { putString(EXTRA_ERROR, "VPN session ID is missing.") },
                    )
                    if (activeSessionId == null) finishServiceIfCurrent(startId)
                    return START_NOT_STICKY
                }
                worker.execute {
                    try {
                        if (activeSessionId == sessionId) {
                            stopMihomo()
                            activeSessionId = null
                        }
                        receiver?.send(Activity.RESULT_OK, Bundle())
                        if (activeSessionId == null) finishServiceIfCurrent(startId)
                    } catch (error: Throwable) {
                        receiver?.send(
                            Activity.RESULT_CANCELED,
                            Bundle().apply {
                                putString(EXTRA_ERROR, error.message ?: error.toString())
                            },
                        )
                    }
                }
            }

            else -> stopSelf(startId)
        }
        return START_NOT_STICKY
    }

    private fun finishServiceIfCurrent(startId: Int) {
        if (latestStartId == startId && activeSessionId == null) {
            stopForeground(true)
            stopSelf(startId)
        }
    }

    private fun startMihomo(configPath: String) {
        MihomoRuntime.load(this)

        val configFile = File(configPath).canonicalFile
        check(configFile.isFile && configFile.canRead()) {
            "Mihomo config is missing or unreadable: ${configFile.absolutePath}"
        }
        check(configFile.name == CONFIG_FILE_NAME) {
            "Mihomo expects $CONFIG_FILE_NAME, got ${configFile.name}."
        }
        val homeDir = configFile.parentFile
            ?: error("Mihomo config has no parent directory.")
        val initParams = JSONObject()
            // libmihomo-android InitParams expects the JSON key `home-dir`. This must match the native InitParams JSON tag exactly.
            .put("home-dir", homeDir.absolutePath)
            .put("version", Build.VERSION.SDK_INT)
            .toString()
        val setupParams = JSONObject()
            .put("profile", configFile.absolutePath)
            .toString()

        // libmihomo reports an empty callback result on success.
        val ready = CountDownLatch(1)
        var setupError: String? = null
        Clash.quickSetup(initParams, setupParams) { message ->
            setupError = message?.takeIf { it.isNotBlank() }
            ready.countDown()
        }
        check(ready.await(30, TimeUnit.SECONDS)) {
            "Mihomo did not finish loading the profile within 30 seconds."
        }
        check(setupError == null) {
            "Mihomo rejected the profile at ${configFile.absolutePath}: $setupError"
        }

        // Match FlClash's Android TUN setup: the system owns the TUN interface,
        // while Mihomo receives the detached descriptor through its mobile bridge.
        val tun = Builder()
            .setSession(packageManager.getApplicationLabel(applicationInfo).toString())
            .setMtu(TUN_MTU)
            .setBlocking(false)
            .apply {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                    setMetered(false)
                }
            }
            .addAddress(IPV4_ADDRESS, 30)
            .addRoute("0.0.0.0", 0)
            .addDnsServer(IPV4_DNS)
            .addAddress(IPV6_ADDRESS, 126)
            .addRoute("::", 0)
            .addDnsServer(IPV6_DNS)
            .establish() ?: error("Android refused to establish the VPN interface.")

        val fd = tun.detachFd()
        synchronized(tunLock) {
            try {
                Clash.startTUN(
                    fd = fd,
                    cb = tunInterface,
                    device = "crew",
                    stack = "mixed",
                    address = "$IPV4_ADDRESS/30,$IPV6_ADDRESS/126",
                    dns = "$IPV4_DNS,$IPV6_DNS",
                    mtu = TUN_MTU,
                )
                tunRunning = true
            } catch (error: Throwable) {
                // startTUN can fail before native code takes ownership of fd.
                runCatching { ParcelFileDescriptor.adoptFd(fd).close() }
                throw error
            }
        }
    }

    private fun startForegroundCompat() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(
                NotificationChannel(
                    NOTIFICATION_CHANNEL,
                    packageManager.getApplicationLabel(applicationInfo).toString(),
                    NotificationManager.IMPORTANCE_LOW,
                ),
            )
        }
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, NOTIFICATION_CHANNEL)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        val notification = builder
            .setContentTitle(packageManager.getApplicationLabel(applicationInfo).toString())
            .setContentText("VPN подключён")
            .setSmallIcon(R.mipmap.ic_launcher)
            .setOngoing(true)
            .build()

        if (Build.VERSION.SDK_INT >= 34) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SYSTEM_EXEMPTED,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun stopMihomo() {
        synchronized(tunLock) {
            if (Clash.isLoaded()) {
                Clash.stopTun()
            }
            tunRunning = false
        }
    }

    override fun onLowMemory() {
        if (Clash.isLoaded()) runCatching { Clash.forceGC() }
        super.onLowMemory()
    }

    override fun onTrimMemory(level: Int) {
        if (level >= TRIM_MEMORY_BACKGROUND && Clash.isLoaded()) {
            runCatching { Clash.forceGC() }
        }
        super.onTrimMemory(level)
    }

    override fun onRevoke() {
        // Serialize revocation cleanup with an in-progress start/stop operation.
        runCatching {
            worker.execute {
                runCatching { stopMihomo() }
                activeSessionId = null
                stopSelf()
            }
        }
        super.onRevoke()
    }

    override fun onDestroy() {
        runCatching { stopMihomo() }
        worker.shutdownNow()
        super.onDestroy()
    }

    @Suppress("DEPRECATION")
    private fun Intent.getResultReceiver(): ResultReceiver? =
        if (Build.VERSION.SDK_INT >= 33) {
            getParcelableExtra(EXTRA_RESULT, ResultReceiver::class.java)
        } else {
            getParcelableExtra(EXTRA_RESULT)
        }

    companion object {
        const val ACTION_START = "dev.crew.crew.action.START_VPN"
        const val ACTION_STOP = "dev.crew.crew.action.STOP_VPN"
        const val EXTRA_CONFIG_PATH = "configPath"
        const val EXTRA_SESSION_ID = "sessionId"
        const val EXTRA_RESULT = "resultReceiver"
        const val EXTRA_ERROR = "error"

        private const val NOTIFICATION_CHANNEL = "crew_vpn"
        private const val NOTIFICATION_ID = 1
        private const val CONFIG_FILE_NAME = "config.yaml"
        // Reserved benchmarking space; the configured fake-IP pool starts after this /30.
        private const val TUN_MTU = 1400
        private const val IPV4_ADDRESS = "198.18.0.1"
        private const val IPV4_DNS = "198.18.0.2"
        private const val IPV6_ADDRESS = "fdfe:dcba:9876::1"
        private const val IPV6_DNS = "fdfe:dcba:9876::2"
    }
}
