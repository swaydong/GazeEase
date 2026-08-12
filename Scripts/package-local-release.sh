#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

readonly EXPECTED_BUNDLE_ID="com.local.EyeProtection"
readonly EXPECTED_TEAM_ID="3Q9DKW2UKF"
readonly EXPECTED_EXECUTABLE="Eye Protection"
readonly PROJECT_NAME="EyeProtection.xcodeproj"
readonly SCHEME_NAME="EyeProtection"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
TEMP_BASE="${TMPDIR:-/tmp}"
WORK_ROOT=""

fail() {
    printf 'Error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || fail "Required command not found: $1"
}

read_info_value() {
    local app_path="$1"
    local key="$2"
    /usr/bin/plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist" 2>/dev/null
}

signature_details() {
    /usr/bin/codesign -dv --verbose=4 "$1" 2>&1
}

verify_local_app() {
    local app_path="$1"
    local actual_bundle_id actual_team actual_executable actual_build actual_version
    local signing_output signing_authority architectures required_architecture

    [[ -d "$app_path" ]] || fail "App bundle not found: $app_path"
    [[ ! -L "$app_path" ]] || fail "Refusing to package a symbolic-link app bundle: $app_path"
    [[ -f "$app_path/Contents/Info.plist" ]] || fail "Info.plist is missing from: $app_path"

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null

    actual_bundle_id="$(read_info_value "$app_path" CFBundleIdentifier)"
    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || \
        fail "Unexpected bundle identifier: $actual_bundle_id"

    actual_executable="$(read_info_value "$app_path" CFBundleExecutable)"
    [[ "$actual_executable" == "$EXPECTED_EXECUTABLE" ]] || \
        fail "Unexpected executable name: $actual_executable"

    actual_build="$(read_info_value "$app_path" CFBundleVersion)"
    [[ "$actual_build" =~ ^[0-9]+$ ]] || fail "Invalid build number: $actual_build"

    actual_version="$(read_info_value "$app_path" CFBundleShortVersionString)"
    [[ "$actual_version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || \
        fail "Invalid marketing version: $actual_version"

    signing_output="$(signature_details "$app_path")"
    actual_team="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$actual_team" == "$EXPECTED_TEAM_ID" ]] || fail "Unexpected signing team: $actual_team"

    signing_authority="$(/usr/bin/awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$signing_authority" == Apple\ Development:* ]] || \
        fail "This local packager only accepts an Apple Development signature. Found: $signing_authority"

    architectures="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/$EXPECTED_EXECUTABLE")"
    for required_architecture in arm64 x86_64; do
        case " $architectures " in
            *" $required_architecture "*) ;;
            *) fail "Required architecture is missing: $required_architecture (found: $architectures)" ;;
        esac
    done
}

cleanup() {
    local result=$?
    trap - EXIT
    set +e
    if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" && "$WORK_ROOT" == "${TEMP_BASE%/}/GazeEasePackage."* ]]; then
        /bin/rm -rf -- "$WORK_ROOT"
    fi
    exit "$result"
}

require_command xcodebuild
require_command codesign
require_command ditto
require_command lipo
require_command awk
require_command plutil
require_command shasum
require_command unzip

for required_file in \
    "$PROJECT_ROOT/$PROJECT_NAME" \
    "$PROJECT_ROOT/Packaging/Install GazeEase.command" \
    "$PROJECT_ROOT/Packaging/Uninstall GazeEase.command" \
    "$PROJECT_ROOT/README.md" \
    "$PROJECT_ROOT/README.zh-CN.md" \
    "$PROJECT_ROOT/INSTALL.md" \
    "$PROJECT_ROOT/INSTALL.zh-CN.md" \
    "$PROJECT_ROOT/PRIVACY.md" \
    "$PROJECT_ROOT/PRIVACY.zh-CN.md"; do
    [[ -e "$required_file" ]] || fail "Required packaging input is missing: $required_file"
done

WORK_ROOT="$(/usr/bin/mktemp -d "${TEMP_BASE%/}/GazeEasePackage.XXXXXX")"
trap cleanup EXIT

DERIVED_DATA_DIR="$WORK_ROOT/DerivedData"
DIST_DIR="$PROJECT_ROOT/Dist"

printf 'Building a private, local Apple Development release...\n'
/usr/bin/xcodebuild \
    -project "$PROJECT_ROOT/$PROJECT_NAME" \
    -scheme "$SCHEME_NAME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA_DIR" \
    ARCHS='arm64 x86_64' \
    ONLY_ACTIVE_ARCH=NO \
    build

BUILT_APP="$DERIVED_DATA_DIR/Build/Products/Release/Eye Protection.app"
verify_local_app "$BUILT_APP"

APP_VERSION="$(read_info_value "$BUILT_APP" CFBundleShortVersionString)"
APP_BUILD="$(read_info_value "$BUILT_APP" CFBundleVersion)"
PACKAGE_BASENAME="GazeEase-${APP_VERSION}-build${APP_BUILD}-local"
PACKAGE_DIR="$WORK_ROOT/$PACKAGE_BASENAME"
ARCHIVE_NAME="$PACKAGE_BASENAME.zip"
CHECKSUM_NAME="$ARCHIVE_NAME.sha256"
TEMP_ARCHIVE="$WORK_ROOT/$ARCHIVE_NAME"
TEMP_CHECKSUM="$WORK_ROOT/$CHECKSUM_NAME"
OUTPUT_ARCHIVE="$DIST_DIR/$ARCHIVE_NAME"
OUTPUT_CHECKSUM="$DIST_DIR/$CHECKSUM_NAME"

/bin/mkdir -p "$PACKAGE_DIR" "$DIST_DIR"

[[ ! -e "$OUTPUT_ARCHIVE" ]] || fail "Output already exists: $OUTPUT_ARCHIVE"
[[ ! -e "$OUTPUT_CHECKSUM" ]] || fail "Output already exists: $OUTPUT_CHECKSUM"

/usr/bin/ditto "$BUILT_APP" "$PACKAGE_DIR/GazeEase.app"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/Install GazeEase.command" "$PACKAGE_DIR/Install GazeEase.command"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/Uninstall GazeEase.command" "$PACKAGE_DIR/Uninstall GazeEase.command"
/usr/bin/ditto "$PROJECT_ROOT/README.md" "$PACKAGE_DIR/README.md"
/usr/bin/ditto "$PROJECT_ROOT/README.zh-CN.md" "$PACKAGE_DIR/README.zh-CN.md"
/usr/bin/ditto "$PROJECT_ROOT/INSTALL.md" "$PACKAGE_DIR/INSTALL.md"
/usr/bin/ditto "$PROJECT_ROOT/INSTALL.zh-CN.md" "$PACKAGE_DIR/INSTALL.zh-CN.md"
/usr/bin/ditto "$PROJECT_ROOT/PRIVACY.md" "$PACKAGE_DIR/PRIVACY.md"
/usr/bin/ditto "$PROJECT_ROOT/PRIVACY.zh-CN.md" "$PACKAGE_DIR/PRIVACY.zh-CN.md"
/bin/chmod 755 "$PACKAGE_DIR/Install GazeEase.command" "$PACKAGE_DIR/Uninstall GazeEase.command"

# Verify the exact renamed bundle that will be delivered, not only the Xcode product.
verify_local_app "$PACKAGE_DIR/GazeEase.app"

/usr/bin/ditto -c -k --norsrc --keepParent "$PACKAGE_DIR" "$TEMP_ARCHIVE"
/usr/bin/unzip -tq "$TEMP_ARCHIVE" >/dev/null

ARCHIVE_DIGEST="$(/usr/bin/shasum -a 256 "$TEMP_ARCHIVE" | /usr/bin/awk '{print $1}')"
printf '%s  %s\n' "$ARCHIVE_DIGEST" "$ARCHIVE_NAME" > "$TEMP_CHECKSUM"

/bin/mv "$TEMP_ARCHIVE" "$OUTPUT_ARCHIVE"
/bin/mv "$TEMP_CHECKSUM" "$OUTPUT_CHECKSUM"

printf '\nCreated local package:\n  %s\n  %s\n' "$OUTPUT_ARCHIVE" "$OUTPUT_CHECKSUM"
printf 'This Apple Development build is private and local-only; it is not notarized for public distribution.\n'
