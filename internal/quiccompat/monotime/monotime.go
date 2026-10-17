// Package monotime provides the small monotonic-time abstraction needed by
// HyL's congestion-control prototype. It is not wired to a QUIC transport yet.
package monotime

import "time"

// Time stores monotonic nanoseconds relative to an arbitrary origin.
type Time int64

func Now() Time { return Time(time.Now().UnixNano()) }

func (t Time) IsZero() bool { return t == 0 }

func (t Time) Add(d time.Duration) Time { return t + Time(d) }

func (t Time) Sub(other Time) time.Duration { return time.Duration(t - other) }

func (t Time) After(other Time) bool { return t > other }
