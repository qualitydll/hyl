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
		Use:   "hyl",
		Short: "HyL Client — authenticated QUIC TCP proxy",
		Long:  "HyL client exposes a local SOCKS5 TCP proxy over an authenticated QUIC connection. UDP ASSOCIATE and full-device TUN are not implemented yet.",
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
		Short: "Connect to a HyL server and expose local SOCKS5",
		RunE: func(cmd *cobra.Command, args []string) error {
			cfg, err := config.LoadClientConfig(cfgFile)
			if err != nil {
				return fmt.Errorf("failed to load config %q: %w", cfgFile, err)
			}
			ctx, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
			defer stop()
			logger.Info("Connecting HyL client",
				zap.String("version", version),
				zap.String("server", cfg.Server),
				zap.String("local_socks", cfg.LocalSocks),
			)
			return tunnel.RunClient(ctx, cfg)
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
