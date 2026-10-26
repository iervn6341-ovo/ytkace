#!/bin/bash
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd -P)"
project_dir="$(cd "$script_dir/../.." && pwd -P)"
app_dir="${1:?Pass an output .app directory}"
mkdir -p "$app_dir"
# Keep this source's warning policy aligned with the shipping build. The wider
# UIKit fixture below still exercises older APIs with deprecation suppression.
xcrun clang++ -fobjc-arc -fblocks -std=c++17 -Wall -Wextra -Werror \
  -Werror=deprecated-declarations -target "$(uname -m)-apple-ios17.5-simulator" \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" -fsyntax-only \
  "$project_dir/Tweak/Features/Playback/QualityControls.mm"
xcrun clang++ -fobjc-arc -fblocks -std=c++17 -Wall -Wextra -Werror \
  -Wno-deprecated-declarations -target "$(uname -m)-apple-ios17.5-simulator" \
  -isysroot "$(xcrun --sdk iphonesimulator --show-sdk-path)" \
  -framework UIKit -framework Foundation -framework CoreGraphics -framework QuartzCore \
  "$script_dir/PlayerControlsSmoke.mm" "$project_dir/Tweak/UI/OverlayButtonHost.mm" \
  "$project_dir/Tweak/UI/PlayerMenuPresentation.mm" "$project_dir/Tweak/UI/SystemMenu.mm" \
  "$project_dir/Tweak/UI/NativePlayerMenu.mm" \
  "$project_dir/Tweak/Features/Playback/PlayerGlass.mm" \
  "$project_dir/Tweak/Features/Playback/QualityControls.mm" \
  "$project_dir/Tweak/Runtime/Hooking.mm" -o "$app_dir/PlayerControlsSmoke"
python3 - "$script_dir/PlayerMenuSmoke-Info.plist" "$app_dir/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'rb') as source:
    info = plistlib.load(source)
info.update(CFBundleIdentifier='dev.captionisland.player-controls-smoke', CFBundleExecutable='PlayerControlsSmoke', CFBundleName='Player Controls QA')
info['UIApplicationSceneManifest']['UISceneConfigurations']['UIWindowSceneSessionRoleApplication'][0]['UISceneDelegateClassName'] = 'PlayerControlsSmoke'
with open(sys.argv[2], 'wb') as output:
    plistlib.dump(info, output)
PY
codesign --force --sign - "$app_dir"
