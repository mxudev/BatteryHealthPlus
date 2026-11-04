#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift build --product power-probe
PROBE_BIN="$(swift build --show-bin-path)/power-probe"
python3 - "$PROBE_BIN" <<'PY'
import plistlib, shutil, sys
from pathlib import Path
root = Path('build/diagnostics/SandboxProbe.app/Contents')
(root / 'MacOS').mkdir(parents=True, exist_ok=True)
shutil.copyfile(sys.argv[1], root / 'MacOS/SandboxProbe')
(root / 'MacOS/SandboxProbe').chmod(0o755)
(root / 'Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier': 'com.batteryhealthplus.sandboxprobe',
    'CFBundleExecutable': 'SandboxProbe', 'CFBundlePackageType': 'APPL',
    'CFBundleName': 'SandboxProbe', 'LSMinimumSystemVersion': '14.0'
}))
PY
/usr/bin/codesign --force --sign - --entitlements Config/Widget.entitlements build/diagnostics/SandboxProbe.app
build/diagnostics/SandboxProbe.app/Contents/MacOS/SandboxProbe --smc
