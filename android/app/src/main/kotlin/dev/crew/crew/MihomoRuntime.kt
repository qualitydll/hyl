package dev.crew.crew

import android.content.Context
import android.os.Build
import io.github.oviron.libmihomo.Clash
import java.io.File

internal object MihomoRuntime {
    private val requiredLibraries = listOf("libclash.so", "libmihomo-jni.so")

    fun load(context: Context) {
        val nativeLibraryDir = File(context.applicationInfo.nativeLibraryDir)
        val missing = requiredLibraries.filterNot { File(nativeLibraryDir, it).isFile }
        check(missing.isEmpty()) {
            "Mihomo native libraries are missing from ${nativeLibraryDir.absolutePath} " +
                "for supported ABIs ${Build.SUPPORTED_ABIS.joinToString()}: " +
                missing.joinToString()
        }

        Clash.load(nativeLibraryDir.absolutePath)
        Clash.assertReady()
        val abi = Clash.bridgeABI()
        check(abi == Clash.EXPECTED_BRIDGE_ABI) {
            "Mihomo JNI bridge ABI mismatch: expected ${Clash.EXPECTED_BRIDGE_ABI}, got $abi."
        }
    }
}
