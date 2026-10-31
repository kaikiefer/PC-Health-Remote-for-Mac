# Privacy

PC Health Remote processes system metrics locally on your Mac. It has no
accounts, analytics, advertisements, cloud backend, crash-upload service, or
network listener. The application does not contact a developer-operated server.

When you connect, it sends metrics directly to the selected Flipper over USB or
Bluetooth LE. These include CPU/GPU load and temperature when available, RAM
and GPU shared-memory use and totals, disk usage percentage, battery state,
uptime, CPU clock, fan speed, and abbreviated names/usage of the highest-CPU
and highest-memory processes. The desktop dashboard shows those process names
in full. The app does not read the contents of documents or process memory.

Recent CPU/GPU history is held in memory for the dashboard and discarded on
quit. The app stores connection preference, the selected Bluetooth device ID,
temperature units, and reconnect preference in its own UserDefaults. macOS
handles Bluetooth pairing/bond storage and login-item registration. You can
disconnect at any time, forget the remembered Flipper, and turn off Open at login.

The app does not save telemetry logs. Screenshots, terminal test output, or
diagnostics that you choose to share can expose metrics, device identifiers, or
process names; review them before posting an issue. The GitHub build/test
workflow uses a hosted runner, not the metrics from your Mac.
