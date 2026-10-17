// Package mobile provides mobile-optimized connection management for HyL.
// It implements minimal keepalive to preserve battery life while keeping
// the QUIC connection alive through NAT/firewall timeout periods.
package mobile

import (
	"context"
	"time"
)

const (
	// DefaultKeepaliveInterval is how often to send a minimal ping.
	// 25s is well under most NAT timeout (30s) without excessive battery drain.
	DefaultKeepaliveInterval = 25 * time.Second

	// IdleThreshold: if no real traffic for this duration, drop to slow keepalive.
	IdleThreshold = 30 * time.Second

	// SlowKeepaliveInterval is used when the app is backgrounded / idle.
	SlowKeepaliveInterval = 55 * time.Second
)

// PingFunc is called by the keepalive manager to send a minimal probe.
// The implementation should send the smallest possible packet (e.g. QUIC PING frame).
type PingFunc func(ctx context.Context) error

// KeepaliveManager sends periodic pings to keep a QUIC connection alive
// with minimal battery impact. It slows down when traffic is idle.
type KeepaliveManager struct {
	ping     PingFunc
	interval time.Duration
	idle     bool

	lastActivity time.Time
	stop         chan struct{}
}

// NewKeepaliveManager creates a manager with the given ping function.
// interval should be DefaultKeepaliveInterval unless overridden by config.
func NewKeepaliveManager(ping PingFunc, interval time.Duration) *KeepaliveManager {
	if interval <= 0 {
		interval = DefaultKeepaliveInterval
	}
	return &KeepaliveManager{
		ping:         ping,
		interval:     interval,
		lastActivity: time.Now(),
		stop:         make(chan struct{}),
	}
}

// NotifyActivity should be called whenever real traffic is sent or received.
// This resets the idle timer and switches back to normal keepalive rate.
func (m *KeepaliveManager) NotifyActivity() {
	m.lastActivity = time.Now()
	m.idle = false
}

// Start begins the keepalive loop. It runs until ctx is cancelled or Stop is called.
func (m *KeepaliveManager) Start(ctx context.Context) {
	ticker := time.NewTicker(m.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-m.stop:
			return
		case <-ticker.C:
			// Check if we should switch to idle (slow) mode
			if time.Since(m.lastActivity) > IdleThreshold {
				if !m.idle {
					m.idle = true
					ticker.Reset(SlowKeepaliveInterval)
				}
			} else if m.idle {
				m.idle = false
				ticker.Reset(m.interval)
			}

			if err := m.ping(ctx); err != nil {
				// Ping failed — connection may be dead. Caller should handle reconnect.
				return
			}
		}
	}
}

// Stop signals the keepalive loop to exit.
func (m *KeepaliveManager) Stop() {
	select {
	case m.stop <- struct{}{}:
	default:
	}
}

// IsIdle returns whether the manager has entered idle (slow) keepalive mode.
func (m *KeepaliveManager) IsIdle() bool {
	return m.idle
}
