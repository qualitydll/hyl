# HyL — Hysteria Lite

> A lightweight, mobile-optimized QUIC VPN protocol — a fork of [Hysteria2](https://github.com/apernet/hysteria) with an adaptive congestion control, automatic transport fallback, and a one-command server setup.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Go](https://img.shields.io/badge/Go-1.22+-00ADD8?logo=go)](https://go.dev)

---

## Why HyL?

Hysteria2 is great for raw throughput on bad networks. HyL extends it with:

| Feature | Hysteria2 | HyL |
|---|---|---|
| Congestion control | Brutal (fixed aggressive) | **Adaptive** (Brutal ↔ Economy, auto-switching) |
| Transport fallback | Manual config | **Auto** UDP → WebSocket when UDP blocked |
| Battery drain | Not optimized | **Idle keepalive** (slow ping in background) |
| Server setup | Manual | **One-command OOBE installer** |
| Homebrew tap | — | `brew install qualitydll/hyl/hyl` |
| Obfuscation | Salamander | Salamander (same, preserved) |

---

## Quick Start: Server

```bash
# On your VPS/VDS (Ubuntu, Debian, CentOS, Fedora):
curl -fsSL https://raw.githubusercontent.com/qualitydll/hyl/main/scripts/install.sh | sudo bash
```

The installer will:
1. Detect your OS and install dependencies
2. Download the latest `hyl-server` binary
3. Generate a self-signed TLS certificate
4. Prompt for port (default 443) and password (random if blank)
5. Create `/etc/hyl/server.yaml`
6. Register and start a `systemd` service
7. Print your connection URI: `hyl://password@IP:port`

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

HyL uses **Salamander** obfuscation (same as Hysteria2): each UDP packet is XOR'd with `BLAKE2b-256(PSK || random_8_byte_salt)`. The salt is prepended on the wire. This hides traffic from shallow DPI but does not replace TLS.

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

## License

MIT — see [LICENSE](LICENSE).  
Based on [Hysteria2](https://github.com/apernet/hysteria) (MIT).
