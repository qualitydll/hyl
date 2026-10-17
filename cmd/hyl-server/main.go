package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"

	"github.com/spf13/cobra"
	"go.uber.org/zap"

	"github.com/qualitydll/hyl/config"
	"github.com/qualitydll/hyl/internal/tunnel"
)

const version = "0.1.1"

var (
	cfgFile string
	logger  *zap.Logger
)

func main() {
	root := &cobra.Command{
		Use:   "hyl-server",
		Short: "HyL Server — QUIC TCP proxy server",
		Long:  "HyL uses authenticated QUIC streams to provide a TCP CONNECT proxy. It is not a full IP-level TUN VPN yet.",
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
			ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
			defer stop()
			logger.Info("Starting HyL QUIC server",
				zap.String("version", version),
				zap.String("listen", cfg.Listen),
			)
			return tunnel.RunServer(ctx, cfg)
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
