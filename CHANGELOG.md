# Changelog

## 1.3.1 — 2026-10-31

- Explicitly apply the bundled icon to the running application's Dock tile at
  launch, so an older locally cached icon does not persist after rebuilding.
- Include the icon filename extension in bundle metadata.

## 1.3.0 — 2026-10-31

Initial GitHub release candidate.

- Native macOS menu bar companion with a cyan/orange telemetry HUD.
- Original Pulse Link logo, desktop icon, and editable brand assets.
- CPU/GPU temperatures and load, memory, storage, battery, uptime, and top processes.
- Read-only Apple silicon sensor integration and live CPU clock reporting.
- GPU shared memory mapped to the Flipper's VRAM fields.
- USB handshake with CRC validation before any telemetry writes.
- Bluetooth device selection, OS-managed pairing, and reconnect support.
- Saved Celsius/Fahrenheit dashboard preference; wire data stays Celsius.
- Optional Open at login, real 60-second traces, and universal Mac packaging.

Validated on an Apple M3 MacBook Air with physical USB telemetry and reconnecting
to an already-paired BLE Flipper. First-time Bluetooth pairing, Intel hardware
readings, other chips/firmwares, and installation on a
fresh Mac still need manual validation. Unsupported sensor readings remain
unavailable. Fanless Macs have no fan RPM. Public artifacts are ad-hoc signed
unless built with an explicitly configured signing identity; they are not
Apple-notarized by the default workflow.
