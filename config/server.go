// Package config defines HyL configuration structures.
package config

import (
	"os"

	"gopkg.in/yaml.v3"
)

type ServerConfig struct {
	Listen     string           `yaml:"listen"`
	Auth       ServerAuth       `yaml:"auth"`
	TLS        ServerTLS        `yaml:"tls"`
	Congestion ServerCongestion `yaml:"congestion"`
	Bandwidth  ServerBandwidth  `yaml:"bandwidth"`
	Log        LogConfig        `yaml:"log"`
}

type ServerAuth struct {
	Password string `yaml:"password"`
}

type ServerTLS struct {
	Cert string `yaml:"cert"`
	Key  string `yaml:"key"`
}

type ServerCongestion struct {
	Mode string `yaml:"mode"`
}

type ServerBandwidth struct {
	Up   int `yaml:"up"`
	Down int `yaml:"down"`
}

type LogConfig struct {
	Level string `yaml:"level"`
}

func DefaultServerConfig() *ServerConfig {
	return &ServerConfig{
		Listen: "0.0.0.0:443",
		Auth:   ServerAuth{Password: ""},
		TLS: ServerTLS{
			Cert: "/etc/hyl/server.crt",
			Key:  "/etc/hyl/server.key",
		},
		Congestion: ServerCongestion{Mode: "auto"},
		Bandwidth:  ServerBandwidth{Up: 100, Down: 100},
		Log:        LogConfig{Level: "info"},
	}
}

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
