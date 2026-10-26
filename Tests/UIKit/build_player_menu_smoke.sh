#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
app_dir="${1:?Pass an output .app directory}"
mkdir -p "$app_dir"
xcrun clang++ -fobjc-arc -fblocks -std=c++17 -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -target "$(uname -m)-apple-ios17.5-simulator" \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -framework UIKit -framework Foundation -framework CoreGraphics \
  "$script_dir/PlayerMenuSmoke.mm" \
  "$project_dir/Tweak/UI/SystemMenu.mm" \
  "$project_dir/Tweak/UI/PlayerMenuPresentation.mm" \
  "$project_dir/Tweak/UI/OverlayButtonHost.mm" \
  "$project_dir/Tweak/Runtime/Hooking.mm" -o "$app_dir/PlayerMenuSmoke"
cp "$script_dir/PlayerMenuSmoke-Info.plist" "$app_dir/Info.plist"
codesign --force --sign - "$app_dir"
