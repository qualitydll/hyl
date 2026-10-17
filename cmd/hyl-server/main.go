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
		Long:  "HyL (Hysteria Lite) is a lightweight QUIC-based VPN protocol optimized for mobile clients.",
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

			logger.Info("Starting HyL server",
				zap.String("version", version),
				zap.String("listen", cfg.Listen),
				zap.String("congestion_mode", cfg.Congestion.Mode),
			)

			// TODO: initialize QUIC listener with AdaptiveSender, Salamander obfs
			// and serve connections. This is the next implementation milestone.
			logger.Info("Server ready", zap.String("listen", cfg.Listen))

			// Block forever (real impl will use signal handling)
			select {}
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
