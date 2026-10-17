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
		Use:   "hyl-server",
		Short: "HyL Server — Hysteria Lite VPN server",
		Long:  "HyL (Hysteria Lite) is a lightweight QUIC-based VPN prototype; the data plane is not implemented yet.",
		PersistentPreRunE: func(cmd *cobra.Command, args []string) error {
			var err error
			logger, err = zap.NewProduction()
			return err
		},
	}

	root.PersistentFlags().StringVarP(&cfgFile, "config", "c", "/etc/hyl/server.yaml", "path to server config file")
	root.AddCommand(startCmd(), versionCmd())

	if err := root.Execute(); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
}

func startCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "start",
		Short: "Start the HyL server",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.LoadServerConfig(cfgFile)
			if err != nil {
				return fmt.Errorf("failed to load config %q: %w", cfgFile, err)
			}

			logger.Info("HyL server startup requested",
				zap.String("version", version),
				zap.String("listen", cfg.Listen),
				zap.String("congestion_mode", cfg.Congestion.Mode),
			)

			// Fail closed: do not claim the service is listening when there is
			// no QUIC listener, authentication handler, or VPN data plane.
			return fmt.Errorf("HyL server data plane is not implemented; refusing to start a misleading idle service")
		},
	}
}

func versionCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "version",
		Short: "Print version information",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("hyl-server version %s\n", version)
		},
	}
}
