# Crew

Crew — cross-platform VPN client for Android and Windows, built with Flutter and the Mihomo core.

## Goals
- A polished, accessible Material 3 interface with carefully tuned motion.
- Android and Windows clients with profile/subscription management.
- Mihomo-powered proxy groups, live traffic, logs, and connection monitoring.
- User-customizable appearance, motion intensity, compact/comfortable density, and startup behavior.

## Development status
The repository was initialized as a clean project. Core integration and UI are being added incrementally; features should be considered complete only after automated builds and device testing.

## Core and protocol compatibility
Crew uses Mihomo as its primary core. Supported node types depend on the pinned Mihomo version and the provider's subscription format. Unsupported protocols or fields should be reported clearly rather than silently pretending to connect.

## License
Mihomo is distributed under GPL-3.0. Review third-party notices and corresponding source requirements before distributing Crew builds.
