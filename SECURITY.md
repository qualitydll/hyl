# Security status

**HyL is an experimental prototype, not a production VPN. Do not rely on it to protect traffic or expose it as a public VPN service.**

## Current verified limitations

- The client and server do not establish a QUIC session.
- The server does not bind a network listener, authenticate clients, or forward traffic.
- The configured TLS certificate and authentication password are not yet used by a data plane.
- Salamander-style packet obfuscation is not encryption or authentication. It only transforms packet bytes and cannot guarantee resistance to DPI.
- QUIC uses TLS 1.3, but QUIC Initial packets have publicly derivable protection keys, so a passive observer may recover parts of the initial handshake, including SNI unless protections such as ECH apply in the actual deployment. See [RFC 9001](https://www.rfc-editor.org/rfc/rfc9001.html).
- The installer generates a self-signed certificate. A future client must validate certificates by default and support explicit trust/pinning instead of silently disabling validation.
- The installer prints a connection URI containing the password. Treat terminal scrollback and shell/session recordings as sensitive; do not paste the URI into issues, screenshots, or public chats.

## Changes made in this hardening pass

- Salamander packet salts now use Go's `crypto/rand`, not `math/rand`.
- Regression tests cover obfuscation round-trip, per-packet salts, short PSKs, and undersized buffers.
- Client/server startup now fails explicitly instead of claiming a connection or server listener is ready when the data plane is absent.
- The installer service uses `Restart=no` while the server is a scaffold, avoiding a pointless systemd restart loop.

## Before public deployment

1. Implement the complete QUIC transport, authenticated protocol handshake, and traffic forwarding.
2. Validate configuration strictly and reject empty/default passwords.
3. Keep certificate verification enabled by default; test SNI and certificate-name matching.
4. Add rate limits, bounded buffers/reassembly, connection and handshake timeouts, and resource limits before accepting unauthenticated traffic.
5. Run fuzzing, race tests, dependency checks, and integration tests from a separate client against a disposable test VPS.
6. Review firewall exposure and run as a dedicated unprivileged service account when the eventual listener no longer needs privileged ports.

Report security issues privately to the repository maintainer rather than publishing working exploit details.
