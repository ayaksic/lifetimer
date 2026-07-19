#!/usr/bin/env bash
set -euo pipefail

if [[ -z "${TARGET_BUILD_DIR:-}" || -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]]; then
  echo "Build-info injection requires Xcode target and resources paths." >&2
  exit 64
fi

repository_root="$(git -C "${PROJECT_DIR:-.}" rev-parse --show-toplevel)"
commit="${LIFE_TIMER_SOURCE_COMMIT:-$(git -C "$repository_root" rev-parse --short=12 HEAD)}"
if [[ -n "$(git -C "$repository_root" status --porcelain)" ]]; then
  commit="${commit}-dirty"
fi
sdk_name="${SDK_NAME:-unknown-sdk}"
configuration="${CONFIGURATION:-unknown-configuration}"
runtime_environment="$configuration $sdk_name"
resource_directory="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH"
build_info="$resource_directory/LifeTimerBuildInfo.plist"
mkdir -p "$resource_directory"
/usr/bin/plutil -create xml1 "$build_info"

set_plist_value() {
  local key="$1"
  local value="$2"
  /usr/libexec/PlistBuddy -c "Add :$key string $value" "$build_info"
}

set_plist_value "commit" "$commit"
set_plist_value "runtimeEnvironment" "$runtime_environment"
set_plist_value "cloudKitEnvironment" "Production"
set_plist_value "cloudKitContainer" "iCloud.yaksic.lifetimer"

echo "Embedded Life Timer build identity: $commit ($runtime_environment)"
