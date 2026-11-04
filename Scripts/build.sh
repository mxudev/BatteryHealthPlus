#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
python3 Scripts/generate-project.py
xcodebuild -project BatteryHealthPlus.xcodeproj -scheme BatteryHealthPlus \
  -configuration Release -derivedDataPath build/DerivedData \
  CODE_SIGNING_ALLOWED=NO ARCHS=arm64 build
APP="build/DerivedData/Build/Products/Release/BatteryHealth++.app"
/usr/bin/codesign --force --sign - --entitlements Config/Widget.entitlements "$APP/Contents/PlugIns/BatteryHealthWidget.appex"
/usr/bin/codesign --force --sign - --entitlements Config/App.entitlements "$APP"
print "Built: $PWD/$APP"
if [[ "${1:-}" == "--run" ]]; then open "$APP"; fi
