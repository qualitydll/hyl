# HyL — Hysteria Lite

HyL is an experimental authenticated QUIC-based TCP proxy inspired by Hysteria2. The current client can expose a local SOCKS5 endpoint and forward TCP CONNECT traffic through a QUIC connection.

## Current status

- Implemented: QUIC/TLS 1.3 transport, password authentication, certificate verification, optional SHA-256 certificate pinning, local SOCKS5 TCP CONNECT, public-destination filtering, systemd installer hardening.
- Not implemented: full IP-level TUN VPN, UDP forwarding, SOCKS5 UDP ASSOCIATE, Android embedding, WebSocket fallback, and production-grade DPI resistance.
- The adaptive congestion and Salamander packages are prototypes and are not wired into the active transport.

## Server install

On a supported Linux VPS:

    curl -fsSL https://raw.githubusercontent.com/qualitydll/hyl/main/scripts/install.sh | sudo bash

The installer generates a certificate if needed, creates a long random password when you leave the password prompt blank, computes the certificate's SHA-256 fingerprint, configures a restricted systemd service account, and opens the selected UDP port in common host firewalls when available. You must also check the firewall/security group in your VPS provider panel.

The installer prints a connection URI in this form:

    hyl://PASSWORD@SERVER_IP:443?pin=SHA256_CERTIFICATE_FINGERPRINT

The URI contains a password and must be treated as a secret. Do not publish it in issues, screenshots, or chats.

## Brew support

Brew's Windows build can bundle the HyL client and represent each hyl:// URI as a local SOCKS5 outbound in Mihomo. The Windows client launches the HyL sidecar and waits for its SOCKS5 port before starting Mihomo. Current support is TCP-only. Android is not integrated yet; Brew will report that limitation instead of pretending to connect.

Use a recent Windows artifact from the Brew GitHub Actions workflow. For a self-signed server certificate, use the pin in the URI; it authenticates the exact certificate. When the certificate is renewed, distribute the new pin.

## Client config

    server: "vpn.example:443"
    auth:
      password: "use-a-long-random-secret"
    tls:
      sni: "vpn.example"
      insecure: false
      ca: ""
      pin_sha256: "64-hex-character-sha256-certificate-fingerprint"
    local_socks: "127.0.0.1:10808"
    mobile:
      keepalive_interval: 25s

Run the client with:

    hyl start --config client.yaml

SOCKS5 is available at 127.0.0.1:10808. It supports TCP CONNECT only. If pin_sha256 is configured, the exact server certificate is verified. Otherwise normal system CA/name verification is enabled by default. Setting tls.insecure to true disables certificate verification and should be avoided.

## DPI and security

TLS 1.3 protects application data after the handshake, but QUIC Initial packets can reveal parts of the TLS handshake to passive observers. Certificate pinning authenticates the server; it does not hide the server IP or make the traffic indistinguishable from ordinary QUIC. The Salamander code is not used by the active transport, is not encryption, and has not been evaluated against DPI. No DPI resistance is guaranteed.

See SECURITY.md for the limitations and pre-deployment checklist.

## Tests and builds

The GitHub Actions workflow on main runs go test -race ./..., go vet ./..., and builds both client and server. A successful CI run is necessary but not a substitute for a real client-to-VPS test.

    go mod tidy
    go test -race ./...
    go vet ./...
    go build ./cmd/hyl-server
    go build ./cmd/hyl-client

## License

MIT. See LICENSE.
