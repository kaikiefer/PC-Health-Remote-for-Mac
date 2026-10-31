# PC Health Remote for Mac

![PC Health Remote logo](Assets/Brand/logo-lockup.png)

A native macOS companion for the [PC Health Remote Flipper Zero app](https://github.com/vladatman/pc-health-remote/releases), targeting the v1.0.0 wire protocol. Uses Bluetooth LE or USB to send your Mac's metrics to the existing Flipper app. No changes to the Flipper application are required by the protocol implementation.

Requires macOS 13 Ventura or later. The build script targets your current Mac's architecture; the release script produces a universal Apple silicon + Intel binary. Physical validation so far covers an Apple M3 MacBook Air, USB telemetry and reconnection to an already-paired BLE Flipper. Other chips, Intel sensors and first-time BLE pairing need further manual validation. No third-party packages or privileged helper is required. This is an independent companion, not an official upstream release.

## GitHub download and release

Release ZIPs contain `PC Health Remote.app`; extract one and move the app to Applications. Install the separately released [Flipper app](https://github.com/vladatman/pc-health-remote/releases) on your device. The default build is **ad-hoc signed, not Apple-notarized**. A downloaded app may be blocked by Gatekeeper; building from source is available without a developer account. A local signature is not a malware-audit or notarization result.

Maintainers can run `./scripts/release.sh` to create a universal ZIP, checksum and draft release notes in `build/releases/`. Run `python3 scripts/source-archive.py` for a clean source handoff. See [release instructions](docs/RELEASING.md), [privacy](PRIVACY.md), [license](LICENSE), and [acknowledgments](NOTICE.md). The repository includes CI and an optional tag-triggered **draft** release workflow; nothing is published merely by building locally.

## Run

Build with Xcode or matching Apple Command Line Tools installed:

```sh
./scripts/build.sh
open "build/PC Health Remote.app"
```

You can copy `build/PC Health Remote.app` to Applications using Finder. Move it to its permanent location before enabling **Open at login**. This local build is ad-hoc signed, not notarized for distribution to other Macs.

The dashboard shows live metrics. Closing its window leaves the menu bar app running; use its menu to reopen the dashboard, disconnect, or quit. After the first connection attempt, it resumes the selected transport on the next launch unless you disconnected or explicitly quit using the app menu.

The desktop dashboard uses a dark HUD with cyan CPU telemetry, Flipper-orange GPU accents, a central live connection indicator, and real 60-second CPU/GPU usage traces. The icon matches the dashboard. Traces begin collecting when the app starts; they do not contain simulated history. Decorative rings are static, avoiding a continuous rendering loop while monitoring your Mac.

Use the **°C / °F** selector beside **TEMP DISPLAY** to change both dashboard temperatures. The preference is saved across launches. This only converts the Mac display; telemetry sent to Flipper and its alert thresholds remain in Celsius.

### Bluetooth

1. On Flipper, launch **PC Health Remote**, open its settings, and select **Bluetooth LE**.
2. On Mac, choose **Bluetooth**, click **Connect**, and allow Bluetooth access when prompted.
3. Click **Use this Flipper** beside your `PCHealth…` device.
4. Compare and confirm any pairing code on both Mac and Flipper. macOS handles the pairing dialog.

The Mac remembers the selected device after receiving a valid HELLO. It scans and reconnects when that device advertises again. If several Flippers are nearby, select the desired one from the list. **Forget selected Flipper** clears this app's remembered selection; removing a stale OS bond requires System Settings → Bluetooth and, if necessary, resetting the Flipper app's bond. Unlike the Windows backend, macOS controls its own pairing UI.

### USB

1. Connect Flipper to the Mac with a data-capable USB cable and close qFlipper or any serial terminal using it.
2. Open **PC Health Remote** on Flipper and select **USB** in its settings.
3. In the Mac app, choose **USB** and click **Connect**.

Only Flipper VID/PID `0483:5740` serial ports are considered. The Mac opens the port at 115200 baud with DTR and listens for a valid, CRC-checked USB HELLO before sending anything. If none arrives in three seconds, it releases the port and retries later. This avoids sending binary telemetry to the regular Flipper CLI. Disconnect the Mac companion before using qFlipper. USB mode on Flipper temporarily takes over its USB connection; exit the Flipper app or switch it back to Bluetooth to restore the normal interface.

## Metrics and limitations

| Metric | Source / behavior |
| --- | --- |
| CPU load | Mach CPU tick deltas, normalized across all cores, sampled every second |
| Memory | Mach VM statistics: internal resident + wired + compressed pages, minus purgeable; excludes reclaimable file-backed cache. Approximate used memory, not memory pressure |
| RAM total | Physical memory, decimal GB as required by the protocol |
| Disk | Used fraction of the home volume (normally the startup APFS Data volume) |
| Battery / charging | IOKit internal battery, when present |
| Uptime | System uptime, whole hours, clamped to the protocol's 16-bit range |
| Top processes | `/bin/ps`, refreshed every five seconds; CPU is macOS ps's decaying recent average divided by logical core count, RAM is ps's resident-memory percentage |
| CPU/GPU temperature | Average of valid SMC CPU/GPU thermal sensors; read-only, no admin helper |
| GPU load | IOAccelerator driver `Device Utilization %` |
| VRAM / shared GPU memory | Driver `In use system memory` divided by physical unified memory; total equals shared system RAM, not dedicated VRAM |
| CPU clock | IOReport core performance-state residency deltas mapped to IORegistry DVFS tables; active-residency-weighted average across efficiency/performance cores |
| Fan | Highest available SMC fan actual speed; absent on fanless machines, including this M3 MacBook Air |

The large CPU/GPU boxes on Flipper page 1 show temperatures. GPU and VRAM bars are enabled when a valid GPU utilization counter is available. On Apple silicon, the Flipper's fixed **VRAM** label represents GPU-resident shared memory usage; the capacity is physical unified memory, also used by the CPU. It is not a separate VRAM allocation or Metal working-set budget. A 95% VRAM alert therefore means GPU residency alone approaches total physical memory.

Fanless Macs have no fan RPM; this correctly stays `--` on Flipper. A real fan at 0 RPM is reported as a valid zero. CPU clock needs two consecutive samples and may be unavailable if the CPU is fully idle or its performance-state table cannot be matched. This implementation supports the M1–M4-style efficiency/performance table layout and was validated on this M3. SMC and IOReport are undocumented system interfaces and may change in future macOS/chip versions. Unsupported readings retain their unavailable flag instead of substituting values. Thermal-zone averages may differ from other apps that select a hottest-core or package sensor. Flipper handles alert rules and snoozing using its existing settings.

BLE and USB use the same 48-byte, little-endian telemetry frame with CRC16-CCITT-FALSE. The companion honors HELLO's requested 1–10 second interval, fragments BLE writes according to the negotiated maximum length, respects CoreBluetooth write readiness, and reconnects after a 30-second HELLO silence. Only one selected transport runs at a time. A frame counter records writes completed by the local transport; it is not a device acknowledgment.

All metrics stay on your Mac and the selected Flipper. There is no cloud backend, analytics, or network server. The app stores transport, selected Bluetooth device ID, temperature units and reconnect preferences in UserDefaults. macOS stores Bluetooth bonds. See [PRIVACY.md](PRIVACY.md) for the transmitted fields and data retention details.

## Development and validation

```sh
./scripts/test.sh
./scripts/build.sh
```

Tests cover the CRC reference vector, packet fields and bounds, unavailable sensor flags, ASCII names, fragmented/coalesced/corrupt HELLO streams, live metrics, and a USB session over a pseudo-terminal. The USB test confirms silence before HELLO and after ordinary CLI text, telemetry after HELLO, and port release on handshake timeout. The emitted packet is also decoded by the unmodified upstream Flipper C decoder in `Tests/Reference` (MIT license included).

The sensor-enabled packet is separately checked by the Flipper decoder, including temperatures above 100°C, GPU/VRAM values, clock, fan speed, and validity flags. `Tests/HardwareProbe.c` can be compiled alongside `Sources/Hardware/Hardware.c` with IOKit and CoreFoundation to inspect live SMC/IOReport readings. The hardware interfaces adapt the MIT-licensed [macmon](https://github.com/vladkens/macmon) approach; its notice is in `ThirdParty/` and included in the app bundle.

Tests do not establish physical BLE pairing or physical Flipper display behavior. Those require a Flipper with the matching app running and a user confirming the pairing prompts. If Xcode was updated recently, finish its first-launch setup and license acceptance, and check `xcode-select -p`. Scripts use the active toolchain; override `DEVELOPER_DIR` to select a different matching installation. Build products and module caches stay inside `build/`.
