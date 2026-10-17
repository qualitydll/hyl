// Package config defines HyL configuration structures.
package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

// ServerConfig is the full server configuration loaded from server.yaml.
type ServerConfig struct {
	Listen    string          `yaml:"listen"`    // e.g. "0.0.0.0:443"
	Auth      ServerAuth      `yaml:"auth"`
	TLS       ServerTLS       `yaml:"tls"`
	Congestion ServerCongestion `yaml:"congestion"`
	Bandwidth ServerBandwidth  `yaml:"bandwidth"`
	Log       LogConfig        `yaml:"log"`
}

type ServerAuth struct {
	// Password is a shared secret clients must present.
	Password string `yaml:"password"`
}

type ServerTLS struct {
	Cert string `yaml:"cert"` // path to certificate PEM
	Key  string `yaml:"key"`  // path to private key PEM
}

// ServerCongestion controls which CC algorithm the server advertises.
type ServerCongestion struct {
	// Mode: "auto" (adaptive), "brutal", or "economy"
	Mode string `yaml:"mode"`
}

type ServerBandwidth struct {
	// Up and Down are the server's uplink/downlink bandwidth hints in Mbps.
	Up   int `yaml:"up"`
	Down int `yaml:"down"`
}

type LogConfig struct {
	Level string `yaml:"level"` // debug, info, warn, error
}

// DefaultServerConfig returns a usable default configuration.
func DefaultServerConfig() *ServerConfig {
	return &ServerConfig{
		Listen: "0.0.0.0:443",
		Auth:   ServerAuth{Password: "changeme"},
		TLS: ServerTLS{
			Cert: "/etc/hyl/server.crt",
			Key:  "/etc/hyl/server.key",
		},
		Congestion: ServerCongestion{Mode: "auto"},
		Bandwidth:  ServerBandwidth{Up: 100, Down: 100},
		Log:        LogConfig{Level: "info"},
	}
}

// LoadServerConfig reads and parses a YAML server config file.
func LoadServerConfig(path string) (*ServerConfig, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	cfg := DefaultServerConfig()
	if err := yaml.Unmarshal(data, cfg); err != nil {
		return nil, err
	}
	return cfg, nil
}
