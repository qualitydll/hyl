// Package congestion implements an adaptive congestion control algorithm
// that combines Brutal (aggressive) and Economy (conservative) modes
// based on observed network conditions.
package congestion

import (
	"fmt"
	"sync"
	"time"

	"github.com/apernet/quic-go/congestion"
	"github.com/apernet/quic-go/monotime"
)

const (
	pktInfoSlotCount = 5 // seconds of history

	minSampleCount = 50
	minAckRate     = 0.8

	// Brutal mode: aggressive, high window multiplier
	brutalWindowMultiplier = 2.0
	// Economy mode: conservative, lower window multiplier (saves battery)
	economyWindowMultiplier = 1.0

	// Thresholds for mode switching
	lossRateForBrutal   = 0.03 // >3% loss → switch to Brutal
	lossRateForEconomy  = 0.01 // <1% loss → can switch to Economy
	rttVarianceThreshold = 50 * time.Millisecond

	// Hysteresis: how many consecutive evaluations before switching
	hysteresisCount = 3
)

// Mode represents the current congestion control mode.
type Mode int

const (
	ModeAuto    Mode = iota // starts in Brutal, adapts
	ModeBrutal              // aggressive send rate
	ModeEconomy             // conservative, mobile-friendly
)

func (m Mode) String() string {
	switch m {
	case ModeBrutal:
		return "Brutal"
	case ModeEconomy:
		return "Economy"
	default:
		return "Auto"
	}
}

type pktInfo struct {
	Timestamp int64
	AckCount  uint64
	LossCount uint64
}

// AdaptiveSender is a congestion controller that switches between
// Brutal and Economy modes based on real-time network conditions.
// It is safe for concurrent use.
var _ congestion.CongestionControl = (*AdaptiveSender)(nil)

type AdaptiveSender struct {
	mu              sync.Mutex
	rttStats        congestion.RTTStatsProvider
	bps             congestion.ByteCount
	maxDatagramSize congestion.ByteCount
	pacer           *pacer

	pktInfoSlots [pktInfoSlotCount]pktInfo
	ackRate      float64

	mode            Mode
	forcedMode      Mode // ModeAuto means not forced
	hysteresisTick  int  // consecutive ticks voting for a mode change
	pendingMode     Mode

	lastRTT    time.Duration
	rttSamples []time.Duration
}

// NewAdaptiveSender creates a new AdaptiveSender with the given target bandwidth.
// forcedMode can be ModeAuto (adaptive), ModeBrutal, or ModeEconomy.
func NewAdaptiveSender(bps uint64, forcedMode Mode) *AdaptiveSender {
	s := &AdaptiveSender{
		bps:             congestion.ByteCount(bps),
		maxDatagramSize: congestion.InitialPacketSize,
		ackRate:         1,
		mode:            ModeBrutal, // start aggressive
		forcedMode:      forcedMode,
		pendingMode:     ModeBrutal,
	}
	s.pacer = newPacer(func() congestion.ByteCount {
		return congestion.ByteCount(float64(s.bps) / s.ackRate)
	})
	return s
}

// ModeString returns the current active mode as a string for logging.
func (s *AdaptiveSender) ModeString() string {
	s.mu.Lock()
	defer s.mu.Unlock()
	return s.mode.String()
}

func (s *AdaptiveSender) SetRTTStatsProvider(rttStats congestion.RTTStatsProvider) {
	s.mu.Lock()
	s.rttStats = rttStats
	s.mu.Unlock()
}

func (s *AdaptiveSender) TimeUntilSend(_ congestion.ByteCount) monotime.Time {
	return s.pacer.TimeUntilSend()
}

func (s *AdaptiveSender) HasPacingBudget(now monotime.Time) bool {
	return s.pacer.Budget(now) >= s.maxDatagramSize
}

func (s *AdaptiveSender) CanSend(bytesInFlight congestion.ByteCount) bool {
	return bytesInFlight <= s.GetCongestionWindow()
}

func (s *AdaptiveSender) GetCongestionWindow() congestion.ByteCount {
	s.mu.Lock()
	rttStats := s.rttStats
	mode := s.mode
	ackRate := s.ackRate
	bps := s.bps
	maxDgram := s.maxDatagramSize
	s.mu.Unlock()

	if rttStats == nil {
		return 10240
	}
	rtt := rttStats.SmoothedRTT()
	if rtt <= 0 {
		return 10240
	}

	multiplier := brutalWindowMultiplier
	if mode == ModeEconomy {
		multiplier = economyWindowMultiplier
	}

	cwnd := congestion.ByteCount(float64(bps) * rtt.Seconds() * multiplier / ackRate)
	if cwnd < maxDgram {
		cwnd = maxDgram
	}
	return cwnd
}

func (s *AdaptiveSender) OnPacketSent(sentTime monotime.Time, _ congestion.ByteCount,
	_ congestion.PacketNumber, bytes congestion.ByteCount, _ bool,
) {
	s.pacer.SentPacket(sentTime, bytes)
}

func (s *AdaptiveSender) OnPacketAcked(_ congestion.PacketNumber, _ congestion.ByteCount,
	_ congestion.ByteCount, _ monotime.Time,
) {
	// stats tracked in OnCongestionEventEx
}

func (s *AdaptiveSender) OnCongestionEvent(_ congestion.PacketNumber, _ congestion.ByteCount,
	_ congestion.ByteCount,
) {
	// stub — handled in OnCongestionEventEx
}

func (s *AdaptiveSender) OnCongestionEventEx(_ congestion.ByteCount, eventTime monotime.Time,
	ackedPackets []congestion.AckedPacketInfo, lostPackets []congestion.LostPacketInfo,
) {
	currentTimestamp := int64(time.Duration(eventTime) / time.Second)
	slot := currentTimestamp % pktInfoSlotCount

	s.mu.Lock()
	defer s.mu.Unlock()

	if s.pktInfoSlots[slot].Timestamp == currentTimestamp {
		s.pktInfoSlots[slot].LossCount += uint64(len(lostPackets))
		s.pktInfoSlots[slot].AckCount += uint64(len(ackedPackets))
	} else {
		s.pktInfoSlots[slot].Timestamp = currentTimestamp
		s.pktInfoSlots[slot].AckCount = uint64(len(ackedPackets))
		s.pktInfoSlots[slot].LossCount = uint64(len(lostPackets))
	}

	s.updateAckRate(currentTimestamp)

	if s.forcedMode != ModeAuto {
		s.mode = s.forcedMode
		return
	}
	s.adaptMode(currentTimestamp)
}

func (s *AdaptiveSender) updateAckRate(currentTimestamp int64) {
	minTimestamp := currentTimestamp - pktInfoSlotCount
	var ackCount, lossCount uint64
	for _, info := range s.pktInfoSlots {
		if info.Timestamp < minTimestamp {
			continue
		}
		ackCount += info.AckCount
		lossCount += info.LossCount
	}
	if ackCount+lossCount < minSampleCount {
		s.ackRate = 1
		return
	}
	rate := float64(ackCount) / float64(ackCount+lossCount)
	if rate < minAckRate {
		rate = minAckRate
	}
	s.ackRate = rate
}

// adaptMode evaluates current conditions and switches modes with hysteresis.
func (s *AdaptiveSender) adaptMode(currentTimestamp int64) {
	if s.rttStats == nil {
		return
	}

	minTimestamp := currentTimestamp - pktInfoSlotCount
	var ackCount, lossCount uint64
	for _, info := range s.pktInfoSlots {
		if info.Timestamp < minTimestamp {
			continue
		}
		ackCount += info.AckCount
		lossCount += info.LossCount
	}
	total := ackCount + lossCount
	if total < minSampleCount {
		return
	}

	lossRate := float64(lossCount) / float64(total)

	rtt := s.rttStats.SmoothedRTT()
	rttVariance := rtt - s.lastRTT
	if rttVariance < 0 {
		rttVariance = -rttVariance
	}
	s.lastRTT = rtt

	var desiredMode Mode
	if lossRate > lossRateForBrutal || rttVariance > rttVarianceThreshold {
		desiredMode = ModeBrutal
	} else if lossRate < lossRateForEconomy && rttVariance < rttVarianceThreshold/2 {
		desiredMode = ModeEconomy
	} else {
		desiredMode = s.mode // no change
	}

	if desiredMode == s.mode {
		s.hysteresisTick = 0
		s.pendingMode = s.mode
		return
	}

	if s.pendingMode != desiredMode {
		s.pendingMode = desiredMode
		s.hysteresisTick = 1
	} else {
		s.hysteresisTick++
	}

	if s.hysteresisTick >= hysteresisCount {
		fmt.Printf("[AdaptiveSender] mode switch: %s → %s (loss=%.2f%%, rttVar=%dms)\n",
			s.mode, desiredMode, lossRate*100, rttVariance.Milliseconds())
		s.mode = desiredMode
		s.hysteresisTick = 0
	}
}

func (s *AdaptiveSender) SetMaxDatagramSize(size congestion.ByteCount) {
	s.mu.Lock()
	s.maxDatagramSize = size
	s.mu.Unlock()
	s.pacer.SetMaxDatagramSize(size)
}

func (s *AdaptiveSender) InSlowStart() bool          { return false }
func (s *AdaptiveSender) InRecovery() bool            { return false }
func (s *AdaptiveSender) MaybeExitSlowStart()         {}
func (s *AdaptiveSender) OnRetransmissionTimeout(_ bool) {}
