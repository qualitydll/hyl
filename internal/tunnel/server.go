package tunnel

import (
	"context"
	"crypto/subtle"
	"crypto/tls"
	"encoding/binary"
	"fmt"
	"io"
	"net"
	"strconv"
	"time"

	"github.com/quic-go/quic-go"

	"github.com/qualitydll/hyl/config"
)

const (
	alpnProtocol = "hyl/1"
	authRequest  = byte(0)
	connectTCP   = byte(1)
	maxHostBytes = 255
)

func RunServer(ctx context.Context, cfg *config.ServerConfig) error {
	if cfg == nil {
		return fmt.Errorf("server config is nil")
	}
	if len(cfg.Auth.Password) < 16 || cfg.Auth.Password == "changeme" {
		return fmt.Errorf("auth.password must be at least 16 characters and must not be the default password")
	}
	cert, err := tls.LoadX509KeyPair(cfg.TLS.Cert, cfg.TLS.Key)
	if err != nil {
		return fmt.Errorf("load TLS certificate/key: %w", err)
	}
	tlsConfig := &tls.Config{
		MinVersion: tls.VersionTLS13,
		NextProtos: []string{alpnProtocol},
		Certificates: []tls.Certificate{cert},
	}
	listener, err := quic.ListenAddr(cfg.Listen, tlsConfig, &quic.Config{
		KeepAlivePeriod: 25 * time.Second,
		MaxIdleTimeout:  2 * time.Minute,
		MaxIncomingStreams: 128,
	})
	if err != nil {
		return fmt.Errorf("listen for QUIC on %s: %w", cfg.Listen, err)
	}
	defer listener.Close()

	go func() {
		<-ctx.Done()
		_ = listener.Close()
	}()

	for {
		conn, err := listener.Accept(ctx)
		if err != nil {
			if ctx.Err() != nil {
				return nil
			}
			return fmt.Errorf("accept QUIC connection: %w", err)
		}
		go serveConnection(ctx, conn, cfg.Auth.Password)
	}
}

func serveConnection(ctx context.Context, conn quic.Connection, password string) {
	serveConnectionWithDialer(ctx, conn, password, dialPublicTCP)
}

func serveConnectionWithDialer(ctx context.Context, conn quic.Connection, password string, dial func(context.Context, string, uint16) (net.Conn, error)) {
	defer conn.CloseWithError(0, "connection closed")
	authCtx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	stream, err := conn.AcceptStream(authCtx)
	if err != nil {
		return
	}
	defer stream.Close()
	_ = stream.SetDeadline(time.Now().Add(10 * time.Second))

	kind, err := readByte(stream)
	if err != nil || kind != authRequest {
		_, _ = stream.Write([]byte{1})
		return
	}
	var length uint16
	if err := binary.Read(stream, binary.BigEndian, &length); err != nil || length == 0 || length > 1024 {
		_, _ = stream.Write([]byte{1})
		return
	}
	got := make([]byte, int(length))
	if _, err := io.ReadFull(stream, got); err != nil {
		_, _ = stream.Write([]byte{1})
		return
	}
	if subtle.ConstantTimeCompare(got, []byte(password)) != 1 {
		_, _ = stream.Write([]byte{1})
		return
	}
	_ = stream.SetDeadline(time.Time{})
	if _, err := stream.Write([]byte{0}); err != nil {
		return
	}
	_ = stream.SetDeadline(time.Time{})
	_ = stream.Close()

	for {
		stream, err := conn.AcceptStream(conn.Context())
		if err != nil {
			return
		}
		go handleTCPStreamWithDialer(stream, dial)
	}
}

func handleTCPStream(stream quic.Stream) {
	handleTCPStreamWithDialer(stream, dialPublicTCP)
}

func handleTCPStreamWithDialer(stream quic.Stream, dial func(context.Context, string, uint16) (net.Conn, error)) {
	defer stream.Close()
	_ = stream.SetDeadline(time.Now().Add(10 * time.Second))
	kind, err := readByte(stream)
	if err != nil || kind != connectTCP {
		_, _ = stream.Write([]byte{1})
		return
	}
	var hostLen uint16
	if err := binary.Read(stream, binary.BigEndian, &hostLen); err != nil || hostLen == 0 || hostLen > maxHostBytes {
		_, _ = stream.Write([]byte{1})
		return
	}
	hostBytes := make([]byte, int(hostLen))
	if _, err := io.ReadFull(stream, hostBytes); err != nil {
		_, _ = stream.Write([]byte{1})
		return
	}
	var port uint16
	if err := binary.Read(stream, binary.BigEndian, &port); err != nil || port == 0 {
		_, _ = stream.Write([]byte{1})
		return
	}
	host := string(hostBytes)
	if host == "" {
		_, _ = stream.Write([]byte{1})
		return
	}

	ctx, cancel := context.WithTimeout(stream.Context(), 10*time.Second)
	defer cancel()
	target, err := dial(ctx, host, port)
	if err != nil {
		_, _ = stream.Write([]byte{1})
		return
	}
	defer target.Close()
	_ = stream.SetDeadline(time.Time{})
	if _, err := stream.Write([]byte{0}); err != nil {
		return
	}
	relay(stream, target)
}

func dialPublicTCP(ctx context.Context, host string, port uint16) (net.Conn, error) {
	portText := strconv.Itoa(int(port))
	if ip := net.ParseIP(host); ip != nil {
		if !isPublicIP(ip) {
			return nil, fmt.Errorf("private or non-public destination is not allowed")
		}
		var d net.Dialer
		return d.DialContext(ctx, "tcp", net.JoinHostPort(ip.String(), portText))
	}

	ips, err := net.DefaultResolver.LookupIPAddr(ctx, host)
	if err != nil {
		return nil, fmt.Errorf("resolve destination: %w", err)
	}
	var lastErr error
	for _, item := range ips {
		if !isPublicIP(item.IP) {
			continue
		}
		var d net.Dialer
		conn, err := d.DialContext(ctx, "tcp", net.JoinHostPort(item.IP.String(), portText))
		if err == nil {
			return conn, nil
		}
		lastErr = err
	}
	if lastErr != nil {
		return nil, fmt.Errorf("connect to public destination: %w", lastErr)
	}
	return nil, fmt.Errorf("destination resolves only to non-public addresses")
}

func isPublicIP(ip net.IP) bool {
	if ip == nil || ip.IsPrivate() || ip.IsLoopback() ||
		ip.IsLinkLocalUnicast() || ip.IsLinkLocalMulticast() ||
		ip.IsMulticast() || ip.IsUnspecified() {
		return false
	}
	// Block shared, documentation, benchmark, and reserved ranges too. These
	// are not suitable as public Internet destinations for a remote proxy.
	v4Blocked := []string{
		"0.0.0.0/8", "100.64.0.0/10", "192.0.0.0/24", "192.0.2.0/24",
		"192.88.99.0/24", "198.18.0.0/15", "198.51.100.0/24",
		"203.0.113.0/24", "240.0.0.0/4",
	}
	if v4 := ip.To4(); v4 != nil {
		for _, block := range v4Blocked {
			_, network, _ := net.ParseCIDR(block)
			if network.Contains(v4) {
				return false
			}
		}
		return true
	}
	_, documentationIPv6, _ := net.ParseCIDR("2001:db8::/32")
	return !documentationIPv6.Contains(ip)
}

func relay(stream quic.Stream, target net.Conn) {
	done := make(chan struct{}, 2)
	go func() {
		_, _ = io.Copy(target, stream)
		if tcp, ok := target.(*net.TCPConn); ok {
			_ = tcp.CloseWrite()
		}
		done <- struct{}{}
	}()
	go func() {
		_, _ = io.Copy(stream, target)
		_ = stream.Close()
		done <- struct{}{}
	}()
	<-done
	<-done
	_ = target.Close()
	stream.CancelRead(0)
	stream.CancelWrite(0)
}

func readByte(r io.Reader) (byte, error) {
	var b [1]byte
	_, err := io.ReadFull(r, b[:])
	return b[0], err
}
