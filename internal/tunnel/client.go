package tunnel

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"crypto/tls"
	"crypto/x509"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"os"
	"strings"
	"time"

	"github.com/quic-go/quic-go"

	"github.com/qualitydll/hyl/config"
)

// RunClient establishes an authenticated QUIC connection and exposes a loopback-only SOCKS5 TCP proxy.
// UDP ASSOCIATE and full-device TUN routing are intentionally not advertised yet.
func RunClient(ctx context.Context, cfg *config.ClientConfig) error {
	if cfg == nil {
		return fmt.Errorf("client config is nil")
	}
	if len(cfg.Auth.Password) < 16 || cfg.Auth.Password == "changeme" {
		return fmt.Errorf("auth.password must be at least 16 characters and must not be the default password")
	}
	host, _, err := net.SplitHostPort(cfg.Server)
	if err != nil {
		return fmt.Errorf("server must be host:port: %w", err)
	}
	serverName := strings.TrimSpace(cfg.TLS.SNI)
	if serverName == "" {
		serverName = host
	}
	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS13,
		ServerName: serverName,
		NextProtos: []string{alpnProtocol},
	}
	if cfg.TLS.PinSHA256 != "" {
		expected, err := hex.DecodeString(strings.ReplaceAll(cfg.TLS.PinSHA256, ":", ""))
		if err != nil || len(expected) != sha256.Size {
			return fmt.Errorf("tls.pin_sha256 must be a 64-character SHA-256 hex fingerprint")
		}
		// Pinning the exact certificate is an explicit trust decision. Standard
		// CA/name validation is replaced only when this exact pin is configured.
		tlsConfig.InsecureSkipVerify = true //nolint:gosec
		tlsConfig.VerifyConnection = func(state tls.ConnectionState) error {
			if len(state.PeerCertificates) == 0 { return fmt.Errorf("server sent no certificate") }
			got := sha256.Sum256(state.PeerCertificates[0].Raw)
			if subtle.ConstantTimeCompare(got[:], expected) != 1 {
				return fmt.Errorf("server certificate SHA-256 pin mismatch")
			}
			return nil
		}
	}
	if cfg.TLS.Insecure {
		// Explicit opt-in only. Certificate verification remains enabled by default.
		tlsConfig.InsecureSkipVerify = true //nolint:gosec
	} else if cfg.TLS.CA != "" {
		pem, err := os.ReadFile(cfg.TLS.CA)
		if err != nil {
			return fmt.Errorf("read TLS CA file: %w", err)
		}
		roots, err := x509.SystemCertPool()
		if err != nil || roots == nil {
			roots = x509.NewCertPool()
		}
		if ok := roots.AppendCertsFromPEM(pem); !ok {
			return fmt.Errorf("TLS CA file contains no valid certificates")
		}
		tlsConfig.RootCAs = roots
	}

	dialCtx, cancel := context.WithTimeout(ctx, 15*time.Second)
	defer cancel()
	conn, err := quic.DialAddr(dialCtx, cfg.Server, tlsConfig, &quic.Config{
		KeepAlivePeriod:  cfg.Mobile.KeepaliveIntervalDuration(),
		MaxIdleTimeout:   2 * time.Minute,
		MaxIncomingStreams: 128,
	})
	if err != nil {
		return fmt.Errorf("connect to HyL server: %w", err)
	}
	defer conn.CloseWithError(0, "client stopped")

	authStream, err := conn.OpenStreamSync(dialCtx)
	if err != nil {
		return fmt.Errorf("open authentication stream: %w", err)
	}
	password := []byte(cfg.Auth.Password)
	if len(password) > 1024 {
		return fmt.Errorf("auth.password is too long (maximum 1024 bytes)")
	}
	if _, err := authStream.Write([]byte{authRequest}); err != nil {
		return fmt.Errorf("send authentication request: %w", err)
	}
	if err := binary.Write(authStream, binary.BigEndian, uint16(len(password))); err != nil {
		return fmt.Errorf("send authentication length: %w", err)
	}
	if _, err := authStream.Write(password); err != nil {
		return fmt.Errorf("send authentication secret: %w", err)
	}
	authStatus, err := readByte(authStream)
	if err != nil {
		return fmt.Errorf("read authentication response: %w", err)
	}
	_ = authStream.Close()
	if authStatus != 0 {
		return fmt.Errorf("HyL server rejected authentication")
	}

	socksAddr := cfg.LocalSocks
	if socksAddr == "" {
		socksAddr = "127.0.0.1:10808"
	}
	hostPart, _, err := net.SplitHostPort(socksAddr)
	if err != nil {
		return fmt.Errorf("local_socks must be host:port: %w", err)
	}
	if hostPart != "127.0.0.1" && hostPart != "::1" && strings.ToLower(hostPart) != "localhost" {
		return fmt.Errorf("local_socks must bind to loopback only to avoid exposing an unauthenticated proxy")
	}
	listener, err := net.Listen("tcp", socksAddr)
	if err != nil {
		return fmt.Errorf("start local SOCKS5 listener on %s: %w", socksAddr, err)
	}
	defer listener.Close()
	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	for {
		local, err := listener.Accept()
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("accept SOCKS5 client: %w", err)
		}
		go handleSOCKS5(ctx, conn, local)
	}
}

func handleSOCKS5(ctx context.Context, conn quic.Connection, local net.Conn) {
	defer local.Close()
	_ = local.SetDeadline(time.Now().Add(15 * time.Second))
	var greeting [2]byte
	if _, err := io.ReadFull(local, greeting[:]); err != nil || greeting[0] != 5 || greeting[1] == 0 {
		return
	}
	methods := make([]byte, int(greeting[1]))
	if _, err := io.ReadFull(local, methods); err != nil {
		return
	}
	noAuth := false
	for _, m := range methods {
		if m == 0 {
			noAuth = true
			break
		}
	}
	if !noAuth {
		_, _ = local.Write([]byte{5, 0xff})
		return
	}
	if _, err := local.Write([]byte{5, 0}); err != nil {
		return
	}

	var request [4]byte
	if _, err := io.ReadFull(local, request[:]); err != nil || request[0] != 5 {
		return
	}
	if request[1] != 1 {
		_ = writeSOCKSReply(local, 7)
		return
	}
	var host string
	switch request[3] {
	case 1:
		var ip [4]byte
		if _, err := io.ReadFull(local, ip[:]); err != nil {
			return
		}
		host = net.IP(ip[:]).String()
	case 3:
		var length [1]byte
		if _, err := io.ReadFull(local, length[:]); err != nil || length[0] == 0 {
			return
		}
		buf := make([]byte, int(length[0]))
		if _, err := io.ReadFull(local, buf); err != nil {
			return
		}
		host = string(buf)
	case 4:
		var ip [16]byte
		if _, err := io.ReadFull(local, ip[:]); err != nil {
			return
		}
		host = net.IP(ip[:]).String()
	default:
		_ = writeSOCKSReply(local, 8)
		return
	}
	var portBytes [2]byte
	if _, err := io.ReadFull(local, portBytes[:]); err != nil {
		return
	}
	port := binary.BigEndian.Uint16(portBytes[:])
	if port == 0 || len(host) == 0 || len(host) > maxHostBytes {
		_ = writeSOCKSReply(local, 1)
		return
	}
	_ = local.SetDeadline(time.Time{})

	stream, err := conn.OpenStreamSync(ctx)
	if err != nil {
		_ = writeSOCKSReply(local, 1)
		return
	}
	defer stream.Close()
	if _, err := stream.Write([]byte{connectTCP}); err != nil {
		_ = writeSOCKSReply(local, 1)
		return
	}
	if err := binary.Write(stream, binary.BigEndian, uint16(len(host))); err != nil {
		_ = writeSOCKSReply(local, 1)
		return
	}
	if _, err := stream.Write([]byte(host)); err != nil {
		_ = writeSOCKSReply(local, 1)
		return
	}
	if err := binary.Write(stream, binary.BigEndian, port); err != nil {
		_ = writeSOCKSReply(local, 1)
		return
	}
	_ = stream.SetReadDeadline(time.Now().Add(15 * time.Second))
	status, err := readByte(stream)
	if err != nil || status != 0 {
		_ = writeSOCKSReply(local, 5)
		return
	}
	_ = stream.SetReadDeadline(time.Time{})
	if err := writeSOCKSReply(local, 0); err != nil {
		return
	}
	relay(stream, local)
}

func writeSOCKSReply(w io.Writer, status byte) error {
	_, err := w.Write([]byte{5, status, 0, 1, 0, 0, 0, 0, 0, 0})
	return err
}
