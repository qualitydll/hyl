package tunnel

import (
	"net"
	"testing"
)

func TestIsPublicIP(t *testing.T) {
	tests := []struct {
		ip string
		ok bool
	}{
		{"1.1.1.1", true},
		{"8.8.8.8", true},
		{"127.0.0.1", false},
		{"10.0.0.1", false},
		{"192.168.1.1", false},
		{"169.254.1.1", false},
		{"::1", false},
		{"fc00::1", false},
		{"ff02::1", false},
	}
	for _, tt := range tests {
		t.Run(tt.ip, func(t *testing.T) {
			if got := isPublicIP(net.ParseIP(tt.ip)); got != tt.ok {
				t.Fatalf("isPublicIP(%s) = %v, want %v", tt.ip, got, tt.ok)
			}
		})
	}
}
