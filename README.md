# HyL — Hysteria Lite

> An early-stage QUIC VPN prototype inspired by [Hysteria2](https://github.com/apernet/hysteria). The server/client data plane is not implemented yet; this repository is not currently a usable VPN.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go)](https://go.dev)

---

## Why HyL?

HyL is currently an experimental scaffold. The following components are planned or partially implemented, not yet a production-ready VPN:

| Feature | Hysteria2 | HyL |
|---|---|---|
| Congestion control | Brutal | Adaptive controller prototype |
| Transport fallback | Manual config | Transport switcher prototype (not wired into a working tunnel) |
| Battery drain | Not optimized | Keepalive component prototype |
| Server setup | Manual | Installer sets up a service scaffold; does not enable VPN traffic yet |
| Homebrew tap | — | `brew install qualitydll/hyl/hyl` |
| Obfuscation | Salamander | Obfuscation component prototype |

---

## Quick Start: Server

```bash
# On your VPS/VDS (Ubuntu, Debian, CentOS, Fedora):
curl -fsSL https://raw.githubusercontent.com/qualitydll/hyl/main/scripts/install.sh | sudo bash
```

The installer detects the OS, tries a published binary and otherwise builds from source, generates TLS material, prompts for settings, and configures a systemd service. **The current server executable does not implement the QUIC/VPN data plane** and now exits with an explicit error instead of pretending it is listening. Do not use this as a production VPN.

---

## Current status

The client and server commands load configuration but do not establish a QUIC tunnel or route user traffic. They intentionally exit with an error instead of printing a misleading ready message. CLI flags and the connection URI shown in older examples are not fully implemented. The installer cannot turn this prototype into a functioning VPN until the data plane is implemented and tested.

---

## Quick Start: Client

### macOS / Linux (Homebrew)

```bash
brew tap qualitydll/hyl
brew install hyl
```

### From source

```bash
go install github.com/qualitydll/hyl/cmd/hyl-client@latest
```

### Usage

```bash
# Start with a config file
hyl start --config client.yaml

# Or inline for quick test
hyl start --server your-vps:443 --password yourpassword
```

---

## Configuration

### Server (`/etc/hyl/server.yaml`)

```yaml
listen: "0.0.0.0:443"

auth:
  password: "your-strong-password"

tls:
  cert: /etc/hyl/server.crt
  key:  /etc/hyl/server.key

congestion:
  # auto: switches between brutal and economy based on network conditions
  # brutal: always aggressive (like original Hy2)
  # economy: always conservative (best for battery on server side)
  mode: auto

bandwidth:
  up: 100    # Mbps hint for clients
  down: 100

log:
  level: info
```

### Client (`client.yaml`)

```yaml
server: "your-vps.example.com:443"

auth:
  password: "your-strong-password"

tls:
  insecure: false   # set true for self-signed cert
  sni: ""           # override SNI if needed

congestion:
  mode: auto        # auto, brutal, economy
  up_mbps: 50       # your upload bandwidth hint

transport:
  # auto: tries UDP, falls back to WebSocket if UDP blocked
  # udp:  UDP/QUIC only
  # ws:   WebSocket only
  mode: auto

mobile:
  # Ping interval to keep connection alive through NAT
  # Slows to 55s automatically when app is idle
  keepalive_interval: 25s

log:
  level: info
```

---

## Congestion Modes

| Mode | Window multiplier | When to use |
|---|---|---|
| `brutal` | 2× | Bad networks, high packet loss, max throughput |
| `economy` | 1× | Good networks, mobile, battery conservation |
| `auto` | adaptive | **Default** — switches automatically with hysteresis |

**Auto mode** switches to Economy when loss < 1% and RTT is stable. Switches back to Brutal when loss > 3% or RTT spikes. A hysteresis counter prevents rapid toggling.

---

## Obfuscation

HyL contains a Salamander-style packet-obfuscation prototype. Packet salts now use Go's `crypto/rand`, rather than predictable `math/rand`. **Obfuscation is not encryption or authentication and does not guarantee resistance to DPI.** A future working implementation must rely on correctly configured QUIC/TLS for confidentiality and integrity. QUIC Initial packets expose some handshake information to passive observers; see [RFC 9001](https://www.rfc-editor.org/rfc/rfc9001.html).

To enable:
```yaml
# server.yaml
obfs:
  type: salamander
  password: "obfs-psk-separate-from-auth"
```

---

## Architecture

```
Client                              Server
  │                                   │
  │  QUIC over UDP (or WS fallback)   │
  │◄─────────────────────────────────►│
  │                                   │
  │  [Salamander obfs layer]          │
  │  [AdaptiveSender CC]              │
  │  [KeepaliveManager]               │
  │  [TransportSwitcher]              │
```

---

## Building from source

```bash
git clone https://github.com/qualitydll/hyl
cd hyl
go build ./cmd/hyl-server
go build ./cmd/hyl-client
```

---

## Roadmap

- [ ] Full QUIC connection implementation (client ↔ server)
- [ ] SOCKS5 local proxy
- [ ] TUN mode (full VPN)
- [ ] UDP hop (port rotation for whitelist bypass)
- [ ] Android/iOS SDK via `gomobile`
- [ ] Automated GitHub Releases + Homebrew bottle CI

---

## Security status

See [SECURITY.md](SECURITY.md) for current limitations and deployment guidance. HyL is not ready for public or production use; its server does not implement authentication, a QUIC listener, or a traffic-forwarding data plane.

---

## License

MIT — see [LICENSE](LICENSE).  
Based on [Hysteria2](https://github.com/apernet/hysteria) (MIT).
