# Battery and power API research

Investigated on 4 November 2026. The implementation reads values; it does not change power policy, battery limits, fan controls, or SMC registers.

## Public interfaces

[IOPowerSources](https://developer.apple.com/documentation/iokit/iopowersources_h) provides power-source descriptions, state of charge, charging state, and time estimates. Filter `kIOPSTypeKey == kIOPSInternalBatteryType`: a USB UPS or accessory must not be mistaken for the Mac’s internal battery. `IOPSGetPowerSourceDescription` returns an unretained object; copy calls return retained objects.

`IORegistryEntryCreateCFProperties` is a public IOKit function, but many of the battery properties it retrieves are undocumented implementation details. [IOPMPowerSource](https://developer.apple.com/documentation/kernel/iopmpowersource) describes the underlying power-source registry interface. We fetch a dictionary once per sample and release the service object on every path.

Public power-source APIs alone do not supply a portable, guaranteed breakdown of charger input versus device and battery consumption.

## Undocumented AppleSmartBattery fields

The reader probes `AppleSmartBattery`, plus `AppleSmartBatteryPack` for the newer nested layout observed on this Mac. Some data moved from top-level properties into `BatteryData` dictionaries. No reliance on parsing human-readable shell output is needed.

| Field | Interpretation used |
| --- | --- |
| `CurrentCapacity / MaxCapacity` | State-of-charge ratio. On Apple Silicon `MaxCapacity` commonly equals 100 and is **not mAh**. |
| `AppleRawMaxCapacity` | Full-charge capacity in mAh when present. |
| `BatteryData.FullChargeCapacity` | Full-charge capacity fallback, preferred to nominal capacity. |
| `NominalChargeCapacity` | Separate nominal capacity; a final full-capacity fallback. |
| `DesignCapacity` | Original design capacity in mAh. |
| `CycleCount`, `DesignCycleCount9C` | Current cycles and reported design-cycle count. |
| `Temperature` | Hundredths of °C on the targeted battery driver; values outside the supported plausible range are omitted. |
| `Voltage`, `InstantAmperage` / `Amperage` | mV and signed mA; multiply and divide by 1,000,000 for watts. |
| `PowerTelemetryData.SystemPowerIn` | DC input power in mW. Only accepted when an external source is connected. |
| `PowerTelemetryData.SystemLoad` | Device-load power in mW. |
| `PowerTelemetryData.BatteryPower` | Signed battery power in mW. Charging values inconsistent with disconnect state / current direction are rejected. |
| `AdapterDetails.Watts` | Connection capability in watts, **not measured consumption**. |

IORegistry can encode negative signed integers as unsigned two’s-complement values. Both 64-bit and older 32-bit representations are decoded. `65535`, non-positive or implausibly long time estimates are omitted. Invalid, missing, and non-finite values remain absent. A real zero-current reading is retained.

The developer of [Stats’ battery reader](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift) demonstrates the registry/public-source combination and fallback capacity fields. A [published power probe](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) demonstrates that measured input (`SystemPowerIn / 1000`) and advertised adapter wattage differ. These are implementation evidence, not Apple stability guarantees. The field interpretation was also checked against live readings on this Mac.

## Read-only AppleSMC fallback

The host app opens the `AppleSMC` service with `IOServiceOpen` and uses external method 2. The 80-byte ABI is represented by a byte buffer rather than assuming Swift struct layout. It issues only key-metadata (9) and read-bytes (5) commands. No write command exists in the implementation.

`PSTR` is tried for total system power when battery telemetry does not expose `SystemLoad`, including desktop Macs. Supported encodings are little-endian `flt `, signed big-endian `sp78`, and unsigned `fpe2`. Unknown encodings, failed calls, non-finite values, or implausible wattages return unavailable.

Reference: the [Stats SMC implementation](https://github.com/exelban/stats/blob/master/SMC/smc.swift) and its [sensor definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) describe the private protocol and system-power sensor. The implementation here is a new, restricted reader with explicit byte offsets; it does not include the referenced project’s fan-writing functionality.

Access worked without root in this session’s unsandboxed app/probe. The development tool sandbox blocked the SMC user client, so the same probe was checked outside that sandbox. The host app is unsandboxed. Sensor availability and permissions vary by model and OS. No administrator helper or sudo fallback is installed.

## Live sampling architecture

The menu bar dropdown, overview, and floating panel share the same in-process snapshot. The app samples on a utility task approximately every second while a live view is visible, and every five seconds in the background. Sampling pauses during sleep and refreshes on wake, when opening a live view, and on IOPowerSources notifications. Sensor reads are serialized; an event received during a read queues another refresh.

Window occlusion notifications determine whether live views are visible, including minimization, hiding, and Space changes. Desktop and Notification Center widgets are not included; the floating panel provides the live desktop view. No App Group or extension is required.

## Other routes considered

- `powermetrics`: useful for investigation, but typically needs elevated access and often reports subsystem / SoC power rather than a complete charger/battery split. Not invoked by the app.
- IOReport: private energy counters can estimate subsystem power across sampling intervals. They do not by themselves establish wall input or the battery charging split. Not needed for the available registry and SMC measurements, and not implemented.
- Adapter negotiated voltage × maximum current: a ceiling, not a power meter. Never used as actual input power.
- Wall-energy estimates: not presented as measured wall consumption. A physical meter is required to verify outlet-side use.

## Validation scope

- Built the native app as arm64 for macOS 14+ with Xcode 27.2.
- Executed unit tests against modern and legacy fixtures, invalid inputs, and signed-current edge cases.
- Read real battery telemetry from a `MacBookPro18,1`, including nested battery temperature and capacity.
- Verified real input/load/battery values, e.g. 56.519 W / 25.993 W / 30.526 W in one sample.
- Successfully read `PSTR` without root, in the normal host. Desktop presentation is rendered and parser-tested; no physical Mac mini, iMac, Mac Studio, or Mac Pro was available for hardware testing.
- Rendered the menu, overview, floating panel, and desktop power-only layout in light and dark appearances; inspected the app’s live views.
- No App Store submission, Developer ID signing, notarization, or older-macOS hardware test was performed.
