package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/qualitydll/hyl/config"
	"github.com/qualitydll/hyl/internal/transport"
)

const version = "0.1.0"

var (
	cfgFile string
	logger  *zap.Logger
)

func main() {
	root := &cobra.Command{
		Use:   "hyl",
		Short: "HyL Client — Hysteria Lite VPN client",
		Long:  "HyL (Hysteria Lite) is a lightweight QUIC-based VPN protocol optimized for mobile clients.",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			var err error
			logger, err = zap.NewProduction()
			return err
		},
	}

	root.PersistentFlags().StringVarP(&cfgFile, "config", "c", "client.yaml", "path to client config file")

	root.AddCommand(startCmd(), versionCmd())

	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func startCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "start",
		Short: "Connect to a HyL server",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.LoadClientConfig(cfgFile)
			if err != nil {
				return fmt.Errorf("failed to load config %q: %w", cfgFile, err)
			}

			// Build transport switcher
			udpDialer := &transport.UDPDialer{}
			wsDialer := &transport.WSDialer{TLSAddr: cfg.Server}
			mode := transport.Mode(cfg.Transport.Mode)
			switcher := transport.NewSwitcher(udpDialer, wsDialer, mode)

			logger.Info("Starting HyL client",
				zap.String("version", version),
				zap.String("server", cfg.Server),
				zap.String("congestion_mode", cfg.Congestion.Mode),
				zap.String("transport", switcher.ActiveTransport()),
			)

			// TODO: establish QUIC connection, start local SOCKS5/TUN proxy,
			// wire up AdaptiveSender and KeepaliveManager.
			// This is the next implementation milestone.
			logger.Info("Client ready — waiting for connections")

			select {}
		},
	}
}

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("hyl version %s\n", version)
		},
	}
}
