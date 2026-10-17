package tunnel

import (
	"bytes"
	"context"
	"crypto/ecdsa"
	"crypto/elliptic"
	"crypto/rand"
	"crypto/tls"
	"crypto/x509"
	"encoding/pem"
	"io"
	"math/big"
	"net"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/quic-go/quic-go"

	"github.com/qualitydll/hyl/config"
)

func TestIsPublicIP(t *testing.T) {
	tests := []struct { ip string; ok bool }{
		{"1.1.1.1", true}, {"8.8.8.8", true},
		{"100.64.0.1", false}, {"192.0.2.1", false},
		{"198.18.0.1", false}, {"2001:db8::1", false},
		{"127.0.0.1", false}, {"10.0.0.1", false},
		{"192.168.1.1", false}, {"169.254.1.1", false},
		{"::1", false}, {"fc00::1", false}, {"ff02::1", false},
	}
	for _, tt := range tests {
		t.Run(tt.ip, func(t *testing.T) {
			if got := isPublicIP(net.ParseIP(tt.ip)); got != tt.ok {
				t.Fatalf("isPublicIP(%s) = %v, want %v", tt.ip, got, tt.ok)
			}
		})
	}
}

func TestSOCKS5TrafficOverAuthenticatedQUIC(t *testing.T) {
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	certPath, keyPath := writeTestCertificate(t)
	cert, err := tls.LoadX509KeyPair(certPath, keyPath)
	if err != nil { t.Fatal(err) }
	quicListener, err := quic.ListenAddr("127.0.0.1:0", &tls.Config{
		MinVersion: tls.VersionTLS13, NextProtos: []string{alpnProtocol},
		Certificates: []tls.Certificate{cert},
	}, &quic.Config{MaxIdleTimeout: time.Minute})
	if err != nil { t.Fatal(err) }
	defer quicListener.Close()

	echoListener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil { t.Fatal(err) }
	defer echoListener.Close()
	go func() {
		c, err := echoListener.Accept()
		if err != nil { return }
		defer c.Close()
		_, _ = io.Copy(c, c)
	}()

	const password = "a-long-test-password-for-hyl"
	go func() {
		peer, err := quicListener.Accept(ctx)
		if err != nil { return }
		serveConnectionWithDialer(ctx, peer, password, func(ctx context.Context, _ string, _ uint16) (net.Conn, error) {
			var d net.Dialer
			return d.DialContext(ctx, "tcp", echoListener.Addr().String())
		})
	}()

	reserved, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil { t.Fatal(err) }
	socksAddr := reserved.Addr().String()
	_ = reserved.Close()
	clientCfg := &config.ClientConfig{
		Server: quicListener.Addr().String(),
		Auth: config.ClientAuth{Password: password},
		TLS: config.ClientTLS{SNI: "localhost", CA: certPath},
		Mobile: config.MobileConfig{KeepaliveInterval: "25s"},
		LocalSocks: socksAddr,
	}
	clientErr := make(chan error, 1)
	go func() { clientErr <- RunClient(ctx, clientCfg) }()

	var local net.Conn
	deadline := time.Now().Add(5 * time.Second)
	for time.Now().Before(deadline) {
		local, err = net.DialTimeout("tcp", socksAddr, 150*time.Millisecond)
		if err == nil { break }
		select {
		case e := <-clientErr:
			t.Fatalf("HyL client exited before SOCKS listener became ready: %v", e)
		default:
		}
		time.Sleep(50 * time.Millisecond)
	}
	if local == nil { t.Fatal("SOCKS listener did not start") }
	defer local.Close()
	_ = local.SetDeadline(time.Now().Add(5 * time.Second))
	if _, err := local.Write([]byte{5, 1, 0}); err != nil { t.Fatal(err) }
	var greeting [2]byte
	if _, err := io.ReadFull(local, greeting[:]); err != nil { t.Fatal(err) }
	if !bytes.Equal(greeting[:], []byte{5, 0}) { t.Fatalf("unexpected SOCKS greeting %v", greeting) }

	targetPort := echoListener.Addr().(*net.TCPAddr).Port
	req := []byte{5, 1, 0, 3, 12}
	req = append(req, []byte("test.example")...)
	req = append(req, byte(targetPort>>8), byte(targetPort))
	if _, err := local.Write(req); err != nil { t.Fatal(err) }
	var reply [10]byte
	if _, err := io.ReadFull(local, reply[:]); err != nil { t.Fatal(err) }
	if reply[1] != 0 { t.Fatalf("SOCKS CONNECT failed, status %d", reply[1]) }
	payload := []byte("hyl-quic-traffic-check")
	if _, err := local.Write(payload); err != nil { t.Fatal(err) }
	got := make([]byte, len(payload))
	if _, err := io.ReadFull(local, got); err != nil { t.Fatal(err) }
	if !bytes.Equal(got, payload) { t.Fatalf("echo mismatch: got %q, want %q", got, payload) }
}

func writeTestCertificate(t *testing.T) (string, string) {
	t.Helper()
	key, err := ecdsa.GenerateKey(elliptic.P256(), rand.Reader)
	if err != nil { t.Fatal(err) }
	now := time.Now()
	template := &x509.Certificate{
		SerialNumber: big.NewInt(1),
		NotBefore: now.Add(-time.Minute), NotAfter: now.Add(time.Hour),
		KeyUsage: x509.KeyUsageDigitalSignature | x509.KeyUsageCertSign,
		ExtKeyUsage: []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth},
		DNSNames: []string{"localhost"},
		IPAddresses: []net.IP{net.ParseIP("127.0.0.1")},
		IsCA: true, BasicConstraintsValid: true,
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil { t.Fatal(err) }
	keyDER, err := x509.MarshalPKCS8PrivateKey(key)
	if err != nil { t.Fatal(err) }
	dir := t.TempDir()
	certPath, keyPath := filepath.Join(dir, "cert.pem"), filepath.Join(dir, "key.pem")
	if err := os.WriteFile(certPath, pem.EncodeToMemory(&pem.Block{Type:"CERTIFICATE", Bytes:der}), 0600); err != nil { t.Fatal(err) }
	if err := os.WriteFile(keyPath, pem.EncodeToMemory(&pem.Block{Type:"PRIVATE KEY", Bytes:keyDER}), 0600); err != nil { t.Fatal(err) }
	return certPath, keyPath
}
