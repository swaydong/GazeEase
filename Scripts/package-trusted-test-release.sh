#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

readonly EXPECTED_BUNDLE_ID="com.local.EyeProtection"
readonly EXPECTED_TEAM_ID="3Q9DKW2UKF"
readonly EXPECTED_EXECUTABLE="Eye Protection"
readonly EXPECTED_BUILD="40"
readonly EXPECTED_VERSION="1.1.0"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="$PROJECT_ROOT/Dist"
OUTPUT_DIR="$DIST_DIR/TrustedTest"
SOURCE_BASENAME="GazeEase-${EXPECTED_VERSION}-build${EXPECTED_BUILD}-local"
SOURCE_ARCHIVE="$DIST_DIR/$SOURCE_BASENAME.zip"
SOURCE_CHECKSUM="$SOURCE_ARCHIVE.sha256"
PACKAGE_BASENAME="GazeEase-${EXPECTED_VERSION}-build${EXPECTED_BUILD}-macos-test"
OUTPUT_ARCHIVE="$OUTPUT_DIR/$PACKAGE_BASENAME.zip"
OUTPUT_CHECKSUM="$OUTPUT_ARCHIVE.sha256"
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

verify_test_app() {
    local app_path="$1"
    local allow_debug_entitlement="${2:-false}"
    local actual_bundle_id actual_team actual_executable actual_build actual_version
    local signing_output signing_authority entitlements architectures required_architecture

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
    [[ "$actual_build" == "$EXPECTED_BUILD" ]] || \
        fail "Unexpected build number: $actual_build (expected: $EXPECTED_BUILD)"

    actual_version="$(read_info_value "$app_path" CFBundleShortVersionString)"
    [[ "$actual_version" == "$EXPECTED_VERSION" ]] || \
        fail "Unexpected version: $actual_version (expected: $EXPECTED_VERSION)"

    signing_output="$(signature_details "$app_path")"
    actual_team="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$actual_team" == "$EXPECTED_TEAM_ID" ]] || fail "Unexpected signing team: $actual_team"

    signing_authority="$(/usr/bin/awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$signing_authority" == Apple\ Development:* ]] || \
        fail "Trusted test packages require the existing Apple Development signature. Found: $signing_authority"

    [[ "$signing_output" == *"(runtime)"* ]] || fail "Hardened Runtime is missing from: $app_path"

    entitlements="$(/usr/bin/codesign -d --entitlements :- "$app_path" 2>/dev/null)" || \
        fail "Unable to inspect signing entitlements: $app_path"
    if [[ "$allow_debug_entitlement" != "true" ]]; then
        [[ "$entitlements" != *"com.apple.security.get-task-allow"* ]] || \
            fail "Debug entitlement get-task-allow must not be present in the trusted test app."
    fi
    [[ ! -e "$app_path/Contents/embedded.provisionprofile" ]] || \
        fail "An embedded development provisioning profile must not be included."

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
    if [[ -n "$WORK_ROOT" && -d "$WORK_ROOT" && "$WORK_ROOT" == "${TEMP_BASE%/}/GazeEaseTrustedTest."* ]]; then
        /bin/rm -rf -- "$WORK_ROOT"
    fi
    exit "$result"
}

for required_command in awk codesign ditto lipo plutil security shasum strip unzip xattr; do
    require_command "$required_command"
done

for required_file in \
    "$SOURCE_ARCHIVE" \
    "$SOURCE_CHECKSUM" \
    "$PROJECT_ROOT/Packaging/TRUSTED_TEST_INSTALL.zh-CN.txt" \
    "$PROJECT_ROOT/Packaging/TRUSTED_TEST_INSTALL.en.txt" \
    "$PROJECT_ROOT/PRIVACY.md" \
    "$PROJECT_ROOT/PRIVACY.zh-CN.md" \
    "$PROJECT_ROOT/EyeProtection/Resources/EyeProtection.entitlements" \
    "$PROJECT_ROOT/LICENSE" \
    "$PROJECT_ROOT/ASSETS.md"; do
    [[ -f "$required_file" ]] || fail "Required packaging input is missing: $required_file"
done

if /usr/bin/xattr -p com.apple.quarantine "$SOURCE_ARCHIVE" >/dev/null 2>&1; then
    fail "The source archive is quarantined. Use the directly generated local artifact; this script will not remove quarantine."
fi

(
    cd "$DIST_DIR"
    /usr/bin/shasum -a 256 -c "$(basename "$SOURCE_CHECKSUM")"
) >/dev/null

WORK_ROOT="$(/usr/bin/mktemp -d "${TEMP_BASE%/}/GazeEaseTrustedTest.XXXXXX")"
trap cleanup EXIT

EXTRACTED_DIR="$WORK_ROOT/extracted"
PACKAGE_DIR="$WORK_ROOT/$PACKAGE_BASENAME"
VERIFY_DIR="$WORK_ROOT/verify"
TEMP_ARCHIVE="$WORK_ROOT/$PACKAGE_BASENAME.zip"
TEMP_CHECKSUM="$WORK_ROOT/$PACKAGE_BASENAME.zip.sha256"
SOURCE_APP="$EXTRACTED_DIR/$SOURCE_BASENAME/GazeEase.app"

/bin/mkdir -p "$EXTRACTED_DIR" "$PACKAGE_DIR" "$VERIFY_DIR" "$OUTPUT_DIR"
[[ ! -e "$OUTPUT_ARCHIVE" ]] || fail "Output already exists: $OUTPUT_ARCHIVE"
[[ ! -e "$OUTPUT_CHECKSUM" ]] || fail "Output already exists: $OUTPUT_CHECKSUM"
/usr/bin/ditto -x -k "$SOURCE_ARCHIVE" "$EXTRACTED_DIR"
verify_test_app "$SOURCE_APP" true

SOURCE_SIGNING_OUTPUT="$(signature_details "$SOURCE_APP")"
SOURCE_TEAM="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }' <<< "$SOURCE_SIGNING_OUTPUT")"
[[ "$SOURCE_TEAM" == "$EXPECTED_TEAM_ID" ]] || fail "Unexpected source signing team: $SOURCE_TEAM"
SOURCE_AUTHORITY="$(/usr/bin/awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }' <<< "$SOURCE_SIGNING_OUTPUT")"
[[ "$SOURCE_AUTHORITY" == Apple\ Development:* ]] || fail "Unexpected source signing authority: $SOURCE_AUTHORITY"
if ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/awk -v identity="$SOURCE_AUTHORITY" \
    'index($0, "\"" identity "\"") { found = 1 } END { exit(found ? 0 : 1) }'; then
    fail "The private key for the source Apple Development identity is not available."
fi

if /usr/bin/xattr -p com.apple.quarantine "$SOURCE_APP" >/dev/null 2>&1; then
    fail "The extracted source app is quarantined. This script will not remove quarantine."
fi

/usr/bin/ditto "$SOURCE_APP" "$PACKAGE_DIR/GazeEase.app"
/usr/bin/ditto "$PROJECT_ROOT/LICENSE" "$PACKAGE_DIR/LICENSE"
/usr/bin/ditto "$PROJECT_ROOT/ASSETS.md" "$PACKAGE_DIR/ASSETS.md"
# Remove compiler debug symbols (including local source paths) before sealing
# the distributable copy. The source archive and installed app stay untouched.
/usr/bin/strip -S "$PACKAGE_DIR/GazeEase.app/Contents/MacOS/$EXPECTED_EXECUTABLE"
/usr/bin/codesign \
    --force \
    --sign "$SOURCE_AUTHORITY" \
    --options runtime \
    --timestamp=none \
    --entitlements "$PROJECT_ROOT/EyeProtection/Resources/EyeProtection.entitlements" \
    "$PACKAGE_DIR/GazeEase.app"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/TRUSTED_TEST_INSTALL.zh-CN.txt" "$PACKAGE_DIR/请先阅读-安装说明.txt"
/usr/bin/ditto "$PROJECT_ROOT/Packaging/TRUSTED_TEST_INSTALL.en.txt" "$PACKAGE_DIR/READ ME - Installation.txt"
/usr/bin/ditto "$PROJECT_ROOT/PRIVACY.zh-CN.md" "$PACKAGE_DIR/PRIVACY.zh-CN.md"
/usr/bin/ditto "$PROJECT_ROOT/PRIVACY.md" "$PACKAGE_DIR/PRIVACY.md"

DELIVERED_ARCHITECTURES="$(/usr/bin/lipo -archs "$PACKAGE_DIR/GazeEase.app/Contents/MacOS/$EXPECTED_EXECUTABLE")"
{
    printf 'GazeEase / 护眼之道 macOS test build\n'
    printf 'Version: %s\n' "$EXPECTED_VERSION"
    printf 'Build: %s\n' "$EXPECTED_BUILD"
    printf 'Bundle ID: %s\n' "$EXPECTED_BUNDLE_ID"
    printf 'Team ID: %s\n' "$EXPECTED_TEAM_ID"
    printf 'Signing: Apple Development\n'
    printf 'Architectures: %s\n' "$DELIVERED_ARCHITECTURES"
    printf 'Notarized: No\n'
    printf 'Distribution: Public test download; not notarized\n'
    printf 'Official releases: https://github.com/swaydong/GazeEase/releases\n'
    printf 'Fresh installation on a separate Mac: Not yet verified\n'
} > "$PACKAGE_DIR/BUILD-INFO.txt"

verify_test_app "$PACKAGE_DIR/GazeEase.app"
[[ ! -e "$PACKAGE_DIR/Install GazeEase.command" ]] || fail "A local-only installer must not be included in the trusted test package."

/usr/bin/ditto -c -k --norsrc --keepParent "$PACKAGE_DIR" "$TEMP_ARCHIVE"
/usr/bin/unzip -tq "$TEMP_ARCHIVE" >/dev/null
/usr/bin/ditto -x -k "$TEMP_ARCHIVE" "$VERIFY_DIR"
verify_test_app "$VERIFY_DIR/$PACKAGE_BASENAME/GazeEase.app"

ARCHIVE_DIGEST="$(/usr/bin/shasum -a 256 "$TEMP_ARCHIVE" | /usr/bin/awk '{print $1}')"
printf '%s  %s\n' "$ARCHIVE_DIGEST" "$PACKAGE_BASENAME.zip" > "$TEMP_CHECKSUM"

/bin/mv "$TEMP_ARCHIVE" "$OUTPUT_ARCHIVE"
/bin/mv "$TEMP_CHECKSUM" "$OUTPUT_CHECKSUM"

printf '\nCreated macOS test package:\n  %s\n  %s\n' "$OUTPUT_ARCHIVE" "$OUTPUT_CHECKSUM"
printf 'This package is Apple Development signed and not notarized. Gatekeeper confirmation is expected.\n'
printf 'Publish as a prerelease with the checksum and installation guide; fresh installation on a separate Mac remains unverified.\n'
