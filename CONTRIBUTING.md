# Contributing

Bug reports, hardware compatibility reports, and pull requests are welcome.

For a sensor issue, include the Mac model identifier, macOS version, charging state, and the relevant output from `swift run power-probe`. Review diagnostics before posting: avoid full IORegistry dumps, which can include serial numbers and other device identifiers.

To work on the app:

1. Use an Apple Silicon Mac with macOS 14 or later and Xcode 15 or later.
2. Run `swift test` for the telemetry unit tests.
3. Run `./Scripts/build.sh --run` to build and launch the native app and embedded widget.
4. If you add source files, run `python3 Scripts/generate-project.py` and include the updated Xcode project.

Keep hardware access read-only. Preserve unknown values as unavailable, label calculated estimates, and add representative fixtures when changing undocumented sensor parsing. Document the hardware and OS version used to verify sensor changes.

For interface changes, check the dropdown, overview, floating panel, all three widget sizes, and desktop power-only layouts in both light and dark appearance. Verify that launch shows only the dropdown and that Open Window and Float are explicit actions. Preview fixtures must remain separate from live measurements.

Contributions are provided under the repository's [MIT license](LICENSE).
