# Security status

HyL is an experimental TCP proxy, not a production full-device VPN. It has not undergone an independent security audit.

## Implemented protections

- QUIC/TLS 1.3 with certificate verification by default.
- Optional SHA-256 pinning of the exact server leaf certificate.
- Constant-time comparison for the shared password.
- The server rejects default or short passwords.
- The client SOCKS listener binds to loopback only.
- The server rejects destinations resolving only to private, loopback, link-local, multicast, or unspecified IP addresses.
- The installer configures a dedicated service account, restrictive file permissions, a read-only filesystem sandbox, and only the low-port capability.

## Known limitations

- Only TCP CONNECT is supported. There is no UDP relay, IP TUN, or full-device VPN.
- The server has not been independently load-tested or audited for denial-of-service resistance.
- No per-IP connection-rate limiter or detailed abuse controls are implemented yet.
- Salamander obfuscation is not used by the active QUIC transport. It is not encryption or authentication and does not guarantee DPI resistance.
- QUIC Initial packets may expose parts of the TLS handshake to passive observers. A certificate pin authenticates the server but does not hide its IP or make traffic indistinguishable from ordinary QUIC. See https://www.rfc-editor.org/rfc/rfc9001.html.
- The installer-generated certificate is self-signed; the generated URI includes its SHA-256 fingerprint. Certificate rotation requires distributing an updated pin.
- The connection URI contains a password. Treat it as a credential and rotate it if it leaks.

## Before wider deployment

1. Run the automated test suite and verify a real client-to-VPS TCP connection.
2. Add rate limiting and resource limits, and perform fuzz, race, and dependency checks.
3. Review logs, firewall rules, provider security groups, and systemd sandboxing.
4. Add UDP/TUN support only with a separate protocol design and integration tests.
5. Arrange independent security review before relying on HyL for sensitive traffic.

Report vulnerabilities privately to the maintainer.
