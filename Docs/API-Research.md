# Battery and power API research

Investigated on 4 November 2026; direct SMC sampling validated on 6 November 2026. The implementation reads values; it does not change power policy, battery limits, fan controls, or SMC registers.

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
| `PowerTelemetryData.BatteryPower` | Signed battery power in mW. A coherent charging input/load/battery split takes precedence over separately cached current. Otherwise inconsistent direction falls back to electrical measurements. |
| `AdapterDetails.Watts` | Connection capability in watts, **not measured consumption**. |

IORegistry can encode negative signed integers as unsigned two’s-complement values. Both 64-bit and older 32-bit representations are decoded. `65535`, non-positive or implausibly long time estimates are omitted. Invalid, missing, and non-finite values remain absent. A real zero-current reading is retained.

### Connection transitions

Reading the registry again does not force a hardware update. Apple's [battery driver source](https://github.com/apple-oss-distributions/PowerManagement/blob/main/AppleSmartBatteryManager/AppleSmartBattery.cpp) reads current, voltage, and connection state through separate commands. Its timing is an implementation detail, not a guaranteed one-second sensor cadence.

When a complete direct SMC power pair is available, it bypasses the cache transition filter immediately, including idle and battery-assisting states. For the registry fallback, the app tracks power-source changes separately from its polling timestamp. Until the driver advances `UserVisiblePathUpdated`, electrical readings change on drivers without that timestamp, or a charging split becomes available, it suppresses the previous source's battery direction/current and a zero charger reading. The status says “Power updating” (or “Charging” if confirmed). Measured device load remains visible; calculations based on the stale battery reading do not enter history. The wait is capped at 90 seconds so an adapter that really provides no power is not hidden indefinitely. It also handles launching during an apparent connection transition and rapid unplugging.

A positive charging split is considered coherent when input minus load agrees with battery power within 1 W or 5% of input, whichever is greater. That heuristic avoids discarding charging telemetry solely because cached current is still negative; contradictory current is omitted. Incomplete telemetry still uses the conservative electrical fallback, and fresh discharge readings can still report a battery assisting a weak charger. Synthetic transition sequences are regression-tested; a physical cable reconnection is needed to confirm behavior on each hardware/OS combination.

The developer of [Stats’ battery reader](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift) demonstrates the registry/public-source combination and fallback capacity fields. A [published power probe](https://gist.github.com/robzr/2abf9c7e7f576d8af00d90b671489b48) demonstrates that measured input (`SystemPowerIn / 1000`) and advertised adapter wattage differ. These are implementation evidence, not Apple stability guarantees. The field interpretation was also checked against live readings on this Mac.

## Primary read-only AppleSMC power readings

The host app opens the `AppleSMC` service with `IOServiceOpen` and uses external method 2. The 80-byte ABI is represented by a byte buffer rather than assuming Swift struct layout. It issues only key-metadata (9) and read-bytes (5) commands. No write command exists in the implementation.

`PDTR` (input) and `PSTR` (system load) are read consecutively through one connection on every sample, taking priority over registry power telemetry. With both available on a portable, battery power is estimated as input minus load; values within ±0.5 W are treated as idle. The pair also determines charging direction so cached current and charging flags cannot reverse the live flow. Positive measured input can establish external power before the registry connection flag catches up. Contradictory cached current/time estimates are omitted. Health and capacity metadata continue using the registry. Desktop Macs use `PSTR` without a battery split. Missing or invalid individual keys retain the corresponding registry fallback; a new split is never calculated from mixed direct and cached readings. Supported encodings are little-endian `flt `, signed big-endian `sp78`, and unsigned `fpe2`. Unknown encodings, failed calls, non-finite values, or implausible wattages return unavailable.

The [Asahi SMC documentation](https://asahilinux.org/docs/hw/soc/smc/) identifies `PDTR` and `PSTR`. In an eight-second local comparison, direct device power varied from 11.1–15.2 W while registry load remained 11.638 W. `PPBR` returned about 0.35 W during substantial battery charging, so it is not used as signed battery power. This validates faster updates on the tested Mac, not a universal firmware sampling rate.

Reference: the [Stats SMC implementation](https://github.com/exelban/stats/blob/master/SMC/smc.swift) and its [sensor definitions](https://github.com/exelban/stats/blob/master/Modules/Sensors/values.swift) describe the private protocol and system-power sensor. The implementation here is a new, restricted reader with explicit byte offsets; it does not include the referenced project’s fan-writing functionality.

Access worked without root in this session’s unsandboxed app/probe. The development tool sandbox blocked the SMC user client, so the same probe was checked outside that sandbox. The host app is unsandboxed. Sensor availability and permissions vary by model and OS. No administrator helper or sudo fallback is installed.

## Live sampling architecture

The menu bar dropdown, overview, and floating panel share the same in-process snapshot. The app samples on a utility task approximately every second while a live view is visible, and every five seconds in the background. Sampling pauses during sleep and refreshes on wake, when opening a live view, and on IOPowerSources notifications. Sensor reads are serialized; an event received during a read queues another refresh.

NSMenu delegate callbacks track whether the status menu is open; no app activation or key window is needed. Window occlusion notifications track the overview and floating panel, including minimization, hiding, and Space changes. Sampling timers run in common run-loop modes so they continue during native menu tracking. Desktop and Notification Center widgets are not included; the floating panel provides the live desktop view. No App Group or extension is required.

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

## Connected iPhone telemetry

The optional phone reader dynamically loads Apple's private `MobileDevice.framework` and uses an existing trusted USB session to query `com.apple.mobile.diagnostics_relay`. It requests only the `IOPMPowerSource` registry entry. There are no pairing, install, reboot, charging-control, or filesystem commands. Wi-Fi devices are excluded. Missing framework symbols disable the reader gracefully. The first detected USB iPhone is displayed; no personal device name or serial number is collected in the snapshot.

The response's `PowerTelemetryData.SystemPowerIn`, `SystemLoad`, and signed `BatteryPower` are converted from mW to W. Missing or invalid values remain unavailable. `AdapterDetails.Watts` is a connection limit, never substituted for measured input. Phone input is measured on the phone side: it excludes cable losses and may originate from a powered hub rather than the Mac. It is not added to or subtracted from the Mac's existing readings.

The parent app starts its own executable in a read-only command mode, independently of Mac sampling, approximately every five seconds while visible. A six-second deadline terminates a blocked reader, with a one-second grace before killing that child only. Failed reads clear previous values; cached phone results expire after 15 seconds, and sleep clears them. No background service or root helper is installed. The private framework runs only in the short-lived child, containing crashes as well as hangs.

References: [Meta's MobileDevice service documentation](https://fbidb.io/idb/fbdevicecontrol/) and [go-ios's diagnostics reader](https://github.com/danielpaulus/go-ios/blob/main/ios/diagnostics/diagnostics.go). The implementation here is a small independent read-only client.

Validated on 6 November 2026 against the directly connected, already-trusted iPhone: the native reader returned 10.940 W input, 2.149 W device load, and 8.791 W battery power in one sample. The phone supplies its own telemetry cadence; five-second polling does not guarantee five-second hardware updates. A physical hub, untrusted phone, and other iOS/hardware versions have not been tested.
