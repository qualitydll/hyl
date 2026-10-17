// Package obfs provides packet obfuscation for HyL.
// Salamander obfuscation is taken from Hysteria2's extras/obfs package.
package obfs

import (
	"fmt"
	"math/rand"
	"net"
	"sync"
	"syscall"
	"time"

	"golang.org/x/crypto/blake2b"
)

const (
	smPSKMinLen  = 4
	smSaltLen    = 8
	smKeyLen     = 32 // blake2b.Size256
	udpBufferSize = 2048
)

var ErrPSKTooShort = fmt.Errorf("PSK must be at least %d bytes", smPSKMinLen)

// obfuscator is the internal per-packet cipher interface.
type obfuscator interface {
	Obfuscate(in, out []byte) int
	Deobfuscate(in, out []byte) int
}

// salamanderObfuscator obfuscates each packet with BLAKE2b-256(PSK || random_salt).
// Wire format: [8-byte salt][XOR'd payload]
type salamanderObfuscator struct {
	PSK     []byte
	RandSrc *rand.Rand

	lk       sync.Mutex
	keyInput []byte
}

func newSalamanderObfuscator(psk []byte) (*salamanderObfuscator, error) {
	if len(psk) < smPSKMinLen {
		return nil, ErrPSKTooShort
	}
	pskCopy := append([]byte(nil), psk...)
	keyInput := make([]byte, len(pskCopy)+smSaltLen)
	copy(keyInput, pskCopy)
	return &salamanderObfuscator{
		PSK:      pskCopy,
		RandSrc:  rand.New(rand.NewSource(time.Now().UnixNano())), //nolint:gosec
		keyInput: keyInput,
	}, nil
}

// WrapPacketConnSalamander wraps conn with Salamander obfuscation.
func WrapPacketConnSalamander(conn net.PacketConn, psk []byte) (net.PacketConn, error) {
	ob, err := newSalamanderObfuscator(psk)
	if err != nil {
		return nil, err
	}
	return wrapPacketConn(conn, ob), nil
}

func (o *salamanderObfuscator) Obfuscate(in, out []byte) int {
	outLen := len(in) + smSaltLen
	if len(out) < outLen {
		return 0
	}
	o.lk.Lock()
	_, _ = o.RandSrc.Read(out[:smSaltLen])
	key := o.keyLocked(out[:smSaltLen])
	o.lk.Unlock()
	for i, c := range in {
		out[i+smSaltLen] = c ^ key[i%smKeyLen]
	}
	return outLen
}

func (o *salamanderObfuscator) Deobfuscate(in, out []byte) int {
	outLen := len(in) - smSaltLen
	if outLen <= 0 || len(out) < outLen {
		return 0
	}
	o.lk.Lock()
	key := o.keyLocked(in[:smSaltLen])
	o.lk.Unlock()
	for i, c := range in[smSaltLen:] {
		out[i] = c ^ key[i%smKeyLen]
	}
	return outLen
}

func (o *salamanderObfuscator) keyLocked(salt []byte) [smKeyLen]byte {
	copy(o.keyInput[len(o.PSK):], salt[:smSaltLen])
	return blake2b.Sum256(o.keyInput)
}

// --- PacketConn wrapper ---

type udpLikePacketConn interface {
	net.PacketConn
	SyscallConn() (syscall.RawConn, error)
	SetReadBuffer(int) error
	SetWriteBuffer(int) error
}

type obfsPacketConn struct {
	Conn net.PacketConn
	Obfs obfuscator

	readBuf    []byte
	readMutex  sync.Mutex
	writeBuf   []byte
	writeMutex sync.Mutex
}

type obfsPacketConnUDP struct {
	*obfsPacketConn
	UDPConn udpLikePacketConn
}

func wrapPacketConn(conn net.PacketConn, ob obfuscator) net.PacketConn {
	opc := &obfsPacketConn{
		Conn:     conn,
		Obfs:     ob,
		readBuf:  make([]byte, udpBufferSize),
		writeBuf: make([]byte, udpBufferSize),
	}
	if udpConn, ok := conn.(udpLikePacketConn); ok {
		return &obfsPacketConnUDP{obfsPacketConn: opc, UDPConn: udpConn}
	}
	return opc
}

func (c *obfsPacketConn) ReadFrom(p []byte) (n int, addr net.Addr, err error) {
	for {
		c.readMutex.Lock()
		n, addr, err = c.Conn.ReadFrom(c.readBuf)
		if n <= 0 {
			c.readMutex.Unlock()
			return n, addr, err
		}
		n = c.Obfs.Deobfuscate(c.readBuf[:n], p)
		c.readMutex.Unlock()
		if n > 0 || err != nil {
			return n, addr, err
		}
	}
}

func (c *obfsPacketConn) WriteTo(p []byte, addr net.Addr) (n int, err error) {
	c.writeMutex.Lock()
	nn := c.Obfs.Obfuscate(p, c.writeBuf)
	_, err = c.Conn.WriteTo(c.writeBuf[:nn], addr)
	c.writeMutex.Unlock()
	if err == nil {
		n = len(p)
	}
	return n, err
}

func (c *obfsPacketConn) Close() error                       { return c.Conn.Close() }
func (c *obfsPacketConn) LocalAddr() net.Addr                { return c.Conn.LocalAddr() }
func (c *obfsPacketConn) SetDeadline(t time.Time) error      { return c.Conn.SetDeadline(t) }
func (c *obfsPacketConn) SetReadDeadline(t time.Time) error  { return c.Conn.SetReadDeadline(t) }
func (c *obfsPacketConn) SetWriteDeadline(t time.Time) error { return c.Conn.SetWriteDeadline(t) }

func (c *obfsPacketConnUDP) SetReadBuffer(bytes int) error        { return c.UDPConn.SetReadBuffer(bytes) }
func (c *obfsPacketConnUDP) SetWriteBuffer(bytes int) error       { return c.UDPConn.SetWriteBuffer(bytes) }
func (c *obfsPacketConnUDP) SyscallConn() (syscall.RawConn, error) { return c.UDPConn.SyscallConn() }
