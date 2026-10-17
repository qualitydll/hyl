package congestion

import (
	"time"

	"github.com/qualitydll/hyl/internal/quiccompat/congestion"
	"github.com/qualitydll/hyl/internal/quiccompat/monotime"
)

const (
	maxBurstPackets               = 10
	maxBurstPacingDelayMultiplier = 4
)

// pacer implements a token bucket pacing algorithm (copied from Hy2 common pacer).
type pacer struct {
	budgetAtLastSent congestion.ByteCount
	maxDatagramSize  congestion.ByteCount
	lastSentTime     monotime.Time
	getBandwidth     func() congestion.ByteCount
}

func newPacer(getBandwidth func() congestion.ByteCount) *pacer {
	return &pacer{
		budgetAtLastSent: maxBurstPackets * congestion.InitialPacketSize,
		maxDatagramSize:  congestion.InitialPacketSize,
		getBandwidth:     getBandwidth,
	}
}

func (p *pacer) SentPacket(sendTime monotime.Time, size congestion.ByteCount) {
	budget := p.Budget(sendTime)
	if size > budget {
		p.budgetAtLastSent = 0
	} else {
		p.budgetAtLastSent = budget - size
	}
	p.lastSentTime = sendTime
}

func (p *pacer) Budget(now monotime.Time) congestion.ByteCount {
	if p.lastSentTime.IsZero() {
		return p.maxBurstSize()
	}
	budget := p.budgetAtLastSent + (p.getBandwidth()*congestion.ByteCount(now.Sub(p.lastSentTime).Nanoseconds()))/1e9
	if budget < 0 {
		budget = congestion.ByteCount(1<<62 - 1)
	}
	bms := p.maxBurstSize()
	if budget > bms {
		return bms
	}
	return budget
}

func (p *pacer) maxBurstSize() congestion.ByteCount {
	a := congestion.ByteCount((maxBurstPacingDelayMultiplier * congestion.MinPacingDelay).Nanoseconds()) * p.getBandwidth() / 1e9
	b := congestion.ByteCount(maxBurstPackets) * p.maxDatagramSize
	if a > b {
		return a
	}
	return b
}

func (p *pacer) TimeUntilSend() monotime.Time {
	if p.budgetAtLastSent >= p.maxDatagramSize {
		return 0
	}
	diff := 1e9 * uint64(p.maxDatagramSize-p.budgetAtLastSent)
	bw := uint64(p.getBandwidth())
	if bw == 0 {
		return p.lastSentTime.Add(time.Second)
	}
	d := diff / bw
	if diff%bw > 0 {
		d++
	}
	delay := time.Duration(d) * time.Nanosecond
	if delay < congestion.MinPacingDelay {
		delay = congestion.MinPacingDelay
	}
	return p.lastSentTime.Add(delay)
}

func (p *pacer) SetMaxDatagramSize(s congestion.ByteCount) {
	p.maxDatagramSize = s
}
