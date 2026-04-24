# OpenDiag

Flutter-based OBD-II / UDS vehicle diagnostic tool. DTC lookup, live data
dashboard, and session recording.

## Status: 🚧 Work In Progress

This repository is a scaffold. Implementation has not started. The directory
structure reflects the planned architecture:

- `lib/src/bluetooth/` — Bluetooth / BLE transport layer
- `lib/src/obd/` — OBD-II PID handling
- `lib/src/uds/` — ISO 14229 UDS protocol
- `lib/src/data/` — session recording and playback
- `lib/src/models/` — domain types
- `lib/src/providers/` — state management
- `lib/src/services/` — application services
- `lib/src/ui/` — Flutter widgets and screens
- `lib/src/platform/` — platform channels (Android / iOS / Windows)

There is no buildable code yet. Do not clone this expecting a working app.

## Planned

- OBD-II live data over BLE and USB
- UDS DID and routine-control for supported ECUs
- Freeze-frame, DTC lookup, and readiness monitors
- Cross-platform: Android, iOS, Windows

## License

MIT — see [LICENSE](LICENSE). No warranty.
