// Package congestion defines the local interfaces used by HyL's
// experimental adaptive congestion controller. The types are intentionally
// isolated from a specific QUIC implementation until the transport is wired up.
package congestion

import (
	"time"

	"github.com/qualitydll/hyl/internal/quiccompat/monotime"
)

type ByteCount int64
type PacketNumber int64

const (
	InitialPacketSize ByteCount = 1200
	MinPacingDelay              = time.Millisecond
	MaxCongestionWindowPackets  = 1000
	MaxPacketBufferSize ByteCount = 1452
	PacketsPerConnectionID      = 4
)

type RTTStatsProvider interface {
	SmoothedRTT() time.Duration
}

type AckedPacketInfo struct {
	PacketNumber PacketNumber
}

type LostPacketInfo struct {
	PacketNumber PacketNumber
}

type CongestionControl interface {
	SetRTTStatsProvider(RTTStatsProvider)
	TimeUntilSend(bytesInFlight ByteCount) monotime.Time
	HasPacingBudget(now monotime.Time) bool
	CanSend(bytesInFlight ByteCount) bool
	GetCongestionWindow() ByteCount
	OnPacketSent(sentTime monotime.Time, bytesInFlight ByteCount, packetNumber PacketNumber, bytes ByteCount, isRetransmittable bool)
	OnPacketAcked(number PacketNumber, ackedBytes, priorInFlight ByteCount, eventTime monotime.Time)
	OnCongestionEvent(number PacketNumber, lostBytes, priorInFlight ByteCount)
	OnCongestionEventEx(priorInFlight ByteCount, eventTime monotime.Time, ackedPackets []AckedPacketInfo, lostPackets []LostPacketInfo)
	SetMaxDatagramSize(size ByteCount)
	InSlowStart() bool
	InRecovery() bool
	MaybeExitSlowStart()
	OnRetransmissionTimeout(packetsRetransmitted bool)
}
