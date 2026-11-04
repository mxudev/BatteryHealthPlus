# BatteryHealth++

A quiet, native battery and power monitor for **Apple Silicon Macs running macOS 14+**. SwiftUI, IOKit, and a small read-only AppleSMC client. No third-party packages, accounts, network requests, root helper, or charging-control writes.

| Light | Dark |
| --- | --- |
| <img src="Docs/Previews/menu-light.png" width="260" alt="Compact menu in light appearance, with example readings"> | <img src="Docs/Previews/menu-dark.png" width="260" alt="Compact menu in dark appearance, with example readings"> |

## What’s included

- A compact, 260-point menu bar dropdown with adaptive live sampling. The dropdown opens on launch; there is no automatic overview window or Dock icon.
- Explicit **Open Window** and **Float** actions for the detailed overview and draggable floating readout.
- Light and dark appearances that follow macOS, including the dropdown, windows, and floating panel.
- Battery health, current charge, full-charge and original capacity in mAh, cycle count, temperature, and estimated charging / battery time when available.
- Actual charger input, device load, and signed battery power. Advertised charger wattage is labeled separately as the connection’s capability.
- A ten-minute in-memory power chart. History begins when the app opens; no invented points or persisted usage log.
- Automatic power-only presentation on desktop Macs, using the AppleSMC `PSTR` sensor when available.
- Optional launch at login, enabled explicitly in Settings.

The images in `Docs/Previews` use **design fixtures**, not this Mac’s measurements. Live views always use hardware data. `--render-previews` is the only runtime entry point for design fixtures.

## Build and run

Clone the source:

```sh
git clone https://github.com/mxudev/BatteryHealthPlus.git
cd BatteryHealthPlus
```

Open `BatteryHealthPlus.xcodeproj`, select **BatteryHealthPlus**, and run on **My Mac**. The app builds only `arm64`. Xcode 15+ is required; the project was built and checked with Xcode 27.2 on an Apple Silicon MacBook Pro.

For a local ad-hoc signed build:

```sh
./Scripts/build.sh --run
```

The app is generated at:

```text
build/DerivedData/Build/Products/Release/BatteryHealth++.app
```

Keep the app running for live sampling. Click the menu bar battery to open or dismiss the dropdown; Escape or clicking outside dismisses it. Choose **Open Window** (⌘O) for the overview or **Float** (⇧⌘F) for the floating panel. Its upper-right close button hides it. **Settings…** (⌘,) includes launch at login. Closing a window (⌘W) leaves the menu bar app running; **Quit** (⌘Q) stops it. Relaunching opens only the dropdown, even if a window was open when the app quit.

For a stable installation, copy the built app into Applications and launch it there.

For distribution, select your signing team and choose a unique bundle identifier. No App Group is required. Developer ID signing and notarization are not configured; the supplied script produces a **local development build**. Private sensor access is intended for direct distribution and should not be assumed to satisfy Mac App Store review requirements.

## Honest measurements

| Reading | Meaning |
| --- | --- |
| Health | Full-charge capacity ÷ design capacity; can differ from System Settings’ estimate. The numerical percentage retains values over 100%. |
| From charger | Measured DC power entering the Mac, not the adapter’s maximum rating or wall-socket consumption. |
| Mac | System-load telemetry; on desktop Macs, the supported SMC system-power sensor. |
| Battery in / out | Positive telemetry charges the battery; negative telemetry supplies the Mac. The interface labels the direction explicitly. |
| ≈ | Calculated from voltage × current or input − battery. A subtraction estimate includes conversion losses. |
| — | Unavailable. Missing sensor data is never fabricated. |

Independent sensors can sample at different times, so input, load, and battery power need not sum exactly. Apple’s hardware may update its registers less frequently than the app reads them. This app does not measure a wall socket.

## Verify and inspect

```sh
swift test
swift run power-probe
swift run power-probe --smc
```

The probe prints selected readings and their provenance, without battery serial numbers. `--smc` additionally probes `PSTR`, `PDTR`, and `PPBR`; only `PSTR` is used as a system-load fallback. The latter two probes are exploratory and their meanings are not assumed to be portable across models.

To check the signed app’s sensors:

```sh
'build/DerivedData/Build/Products/Release/BatteryHealth++.app/Contents/MacOS/BatteryHealth++' --diagnose
```

To regenerate the design previews:

```sh
'build/DerivedData/Build/Products/Release/BatteryHealth++.app/Contents/MacOS/BatteryHealth++' --render-previews "$PWD/Docs/Previews"
```

The unit suite covers modern nested battery properties, legacy signed currents, battery discharge and assistance, missing fields, valid idle zeros, invalid measurements, SMC decoding, desktop adaptation, and snapshot serialization.

`Scripts/generate-project.py` generates the checked-in Xcode project without XcodeGen. Run it after adding source files. It also regenerates the plist and entitlement templates, so preserve any custom signing changes in that script. `Scripts/make-icon.swift` regenerates the original native app icon.

See [API research and limitations](Docs/API-Research.md) for field mappings, source links, and the tested hardware scope.

## Contributing and license

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and hardware-reporting guidance. Released under the [MIT license](LICENSE).
