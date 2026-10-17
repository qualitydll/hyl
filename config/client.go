package config

import (
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

// ClientConfig is the full HyL client configuration loaded from client.yaml.
type ClientConfig struct {
	Server     string          `yaml:"server"`
	Auth       ClientAuth      `yaml:"auth"`
	TLS        ClientTLS       `yaml:"tls"`
	Congestion ClientCongestion `yaml:"congestion"`
	Transport  ClientTransport  `yaml:"transport"`
	Mobile     MobileConfig     `yaml:"mobile"`
	LocalSocks string          `yaml:"local_socks"`
	Log        LogConfig        `yaml:"log"`
}

type ClientAuth struct {
	Password string `yaml:"password"`
}

type ClientTLS struct {
	SNI      string `yaml:"sni"`
	Insecure bool   `yaml:"insecure"`
	CA       string `yaml:"ca"`
}

type ClientCongestion struct {
	Mode   string `yaml:"mode"`
	UpMbps int    `yaml:"up_mbps"`
}

type ClientTransport struct {
	Mode string `yaml:"mode"`
}

type MobileConfig struct {
	KeepaliveInterval string `yaml:"keepalive_interval"`
}

func (m *MobileConfig) KeepaliveIntervalDuration() time.Duration {
	d, err := time.ParseDuration(m.KeepaliveInterval)
	if err != nil || d <= 0 {
		return 25 * time.Second
	}
	return d
}

func DefaultClientConfig() *ClientConfig {
	return &ClientConfig{
		Server:     "example.com:443",
		Auth:       ClientAuth{Password: ""},
		TLS:        ClientTLS{SNI: ""},
		Congestion: ClientCongestion{Mode: "auto", UpMbps: 50},
		Transport:  ClientTransport{Mode: "udp"},
		Mobile:     MobileConfig{KeepaliveInterval: "25s"},
		LocalSocks: "127.0.0.1:10808",
		Log:        LogConfig{Level: "info"},
	}
}

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
