package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// ClientConfig is the full client configuration loaded from client.yaml.
type ClientConfig struct {
	Server    string          `yaml:"server"`    // e.g. "example.com:443"
	Auth      ClientAuth      `yaml:"auth"`
	TLS       ClientTLS       `yaml:"tls"`
	Congestion ClientCongestion `yaml:"congestion"`
	Transport ClientTransport  `yaml:"transport"`
	Mobile    MobileConfig     `yaml:"mobile"`
	Log       LogConfig        `yaml:"log"`
}

type ClientAuth struct {
	Password string `yaml:"password"`
}

type ClientTLS struct {
	// SNI overrides the server name used for TLS verification.
	SNI string `yaml:"sni"`
	// Insecure disables certificate verification (useful for self-signed certs).
	Insecure bool `yaml:"insecure"`
	// CA is a path to a custom CA certificate PEM for self-signed server certs.
	CA string `yaml:"ca"`
}

type ClientCongestion struct {
	// Mode: "auto", "brutal", or "economy"
	Mode string `yaml:"mode"`
	// UpMbps is the target upload bandwidth hint for Brutal/adaptive modes.
	UpMbps int `yaml:"up_mbps"`
}

type ClientTransport struct {
	// Mode: "auto" (UDP with WS fallback), "udp", or "ws"
	Mode string `yaml:"mode"`
}

type MobileConfig struct {
	// KeepaliveInterval controls how often a keepalive ping is sent.
	// Parsed as a Go duration string, e.g. "25s". Default: 25s.
	KeepaliveInterval string `yaml:"keepalive_interval"`
}

// KeepaliveIntervalDuration parses MobileConfig.KeepaliveInterval as time.Duration.
func (m *MobileConfig) KeepaliveIntervalDuration() time.Duration {
	d, err := time.ParseDuration(m.KeepaliveInterval)
	if err != nil || d <= 0 {
		return 25 * time.Second
	}
	return d
}

// DefaultClientConfig returns a usable default configuration.
func DefaultClientConfig() *ClientConfig {
	return &ClientConfig{
		Server: "example.com:443",
		Auth:   ClientAuth{Password: "changeme"},
		TLS:    ClientTLS{SNI: ""},
		Congestion: ClientCongestion{Mode: "auto", UpMbps: 50},
		Transport:  ClientTransport{Mode: "auto"},
		Mobile:     MobileConfig{KeepaliveInterval: "25s"},
		Log:        LogConfig{Level: "info"},
	}
}

// LoadClientConfig reads and parses a YAML client config file.
func LoadClientConfig(path string) (*ClientConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := DefaultClientConfig()
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}
