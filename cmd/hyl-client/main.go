package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/qualitydll/hyl/config"
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
		Long:  "HyL (Hysteria Lite) is a lightweight QUIC-based VPN prototype; the data plane is not implemented yet.",
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

			logger.Info("HyL client connection requested",
				zap.String("version", version),
				zap.String("server", cfg.Server),
				zap.String("congestion_mode", cfg.Congestion.Mode),
				zap.String("transport", cfg.Transport.Mode),
			)

			// Fail closed: do not report a successful connection while QUIC,
			// authentication, and SOCKS/TUN traffic forwarding are unimplemented.
			return fmt.Errorf("HyL client data plane is not implemented; no connection was established")
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
