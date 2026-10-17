// Package transport provides a transport switcher that automatically falls
// back from UDP/QUIC to WebSocket when UDP is blocked.
package transport

import (
	"context"
	"fmt"
	"net"
	"sync/atomic"
	"time"
)

const (
	// maxUDPFailures is how many consecutive UDP dial errors trigger a fallback.
	maxUDPFailures = 3
	// fallbackCooldown is how long we stay on WebSocket before retrying UDP.
	fallbackCooldown = 5 * time.Minute
)

// Mode controls which transport the switcher prefers.
type Mode string

const (
	ModeAuto Mode = "auto" // try UDP, fall back to WS on failure
	ModeUDP  Mode = "udp"  // force UDP only
	ModeWS   Mode = "ws"   // force WebSocket only
)

// Dialer is the interface both transports implement.
type Dialer interface {
	Dial(ctx context.Context, addr string) (net.Conn, error)
}

// UDPDialer dials raw UDP connections (used as QUIC transport).
type UDPDialer struct{}

func (d *UDPDialer) Dial(ctx context.Context, addr string) (net.Conn, error) {
	var nd net.Dialer
	return nd.DialContext(ctx, "udp", addr)
}

// WSDialer dials WebSocket connections as a fallback transport.
// The actual WebSocket upgrade is handled by the calling layer;
// here we establish the TCP connection that will be upgraded.
type WSDialer struct {
	// TLSAddr is the HTTPS address for the WebSocket endpoint, e.g. "example.com:443"
	TLSAddr string
}

func (d *WSDialer) Dial(ctx context.Context, addr string) (net.Conn, error) {
	target := d.TLSAddr
	if target == "" {
		target = addr
	}
	var nd net.Dialer
	return nd.DialContext(ctx, "tcp", target)
}

// Switcher wraps two dialers and switches between them based on error rate.
type Switcher struct {
	udpDialer Dialer
	wsDialer  Dialer
	mode      Mode

	udpFailures  atomic.Int32
	usingWS      atomic.Bool
	fallbackUntil atomic.Int64 // unix nano
}

// NewSwitcher creates a transport switcher.
func NewSwitcher(udp, ws Dialer, mode Mode) *Switcher {
	return &Switcher{
		udpDialer: udp,
		wsDialer:  ws,
		mode:      mode,
	}
}

// Dial connects to addr using the currently active transport.
func (s *Switcher) Dial(ctx context.Context, addr string) (net.Conn, error) {
	switch s.mode {
	case ModeUDP:
		return s.udpDialer.Dial(ctx, addr)
	case ModeWS:
		return s.wsDialer.Dial(ctx, addr)
	default:
		return s.dialAuto(ctx, addr)
	}
}

func (s *Switcher) dialAuto(ctx context.Context, addr string) (net.Conn, error) {
	// Check if we're in WS fallback period
	if s.usingWS.Load() {
		if time.Now().UnixNano() < s.fallbackUntil.Load() {
			conn, err := s.wsDialer.Dial(ctx, addr)
			if err == nil {
				return conn, nil
			}
			// WS also failed — nothing we can do
			return nil, fmt.Errorf("both transports failed, ws error: %w", err)
		}
		// Cooldown expired — try UDP again
		s.usingWS.Store(false)
		s.udpFailures.Store(0)
	}

	conn, err := s.udpDialer.Dial(ctx, addr)
	if err == nil {
		s.udpFailures.Store(0)
		return conn, nil
	}

	// UDP failed — count failures
	failures := s.udpFailures.Add(1)
	if failures >= maxUDPFailures {
		// Switch to WebSocket
		s.usingWS.Store(true)
		s.fallbackUntil.Store(time.Now().Add(fallbackCooldown).UnixNano())
		s.udpFailures.Store(0)
		fmt.Printf("[Switcher] UDP failed %d times, switching to WebSocket fallback for %s\n",
			maxUDPFailures, fallbackCooldown)

		wsConn, wsErr := s.wsDialer.Dial(ctx, addr)
		if wsErr != nil {
			return nil, fmt.Errorf("UDP failed (%w), WebSocket fallback also failed: %v", err, wsErr)
		}
		return wsConn, nil
	}

	return nil, err
}

// ActiveTransport returns which transport is currently in use.
func (s *Switcher) ActiveTransport() string {
	if s.mode == ModeWS {
		return "websocket"
	}
	if s.mode == ModeUDP {
		return "udp"
	}
	if s.usingWS.Load() {
		return "websocket (fallback)"
	}
	return "udp"
}
