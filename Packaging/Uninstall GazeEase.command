#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

readonly EXPECTED_BUNDLE_ID="com.local.EyeProtection"
readonly EXPECTED_TEAM_ID="3Q9DKW2UKF"
readonly EXPECTED_EXECUTABLE="Eye Protection"
readonly INSTALLED_APP="/Applications/GazeEase.app"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

fail() {
    printf '卸载未执行 / Uninstall stopped: %s\n' "$*" >&2
    exit 1
}

read_info_value() {
    local app_path="$1"
    local key="$2"
    /usr/bin/plutil -extract "$key" raw -o - "$app_path/Contents/Info.plist" 2>/dev/null
}

verify_installed_app() {
    local actual_bundle_id actual_team actual_executable actual_build signing_output architectures required_architecture

    [[ -d "$INSTALLED_APP" ]] || fail "未在固定路径找到 GazeEase：$INSTALLED_APP"
    [[ ! -L "$INSTALLED_APP" ]] || fail "拒绝移动符号链接：$INSTALLED_APP"
    /usr/bin/codesign --verify --deep --strict --verbose=2 "$INSTALLED_APP" >/dev/null

    actual_bundle_id="$(read_info_value "$INSTALLED_APP" CFBundleIdentifier)"
    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || \
        fail "Bundle ID 不匹配：$actual_bundle_id"

    actual_executable="$(read_info_value "$INSTALLED_APP" CFBundleExecutable)"
    [[ "$actual_executable" == "$EXPECTED_EXECUTABLE" ]] || \
        fail "可执行文件名称不匹配：$actual_executable"

    actual_build="$(read_info_value "$INSTALLED_APP" CFBundleVersion)"
    [[ "$actual_build" =~ ^[0-9]+$ ]] || fail "Build 号无效：$actual_build"

    signing_output="$(/usr/bin/codesign -dv --verbose=4 "$INSTALLED_APP" 2>&1)"
    actual_team="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$actual_team" == "$EXPECTED_TEAM_ID" ]] || fail "签名 Team 不匹配：$actual_team"

    architectures="$(/usr/bin/lipo -archs "$INSTALLED_APP/Contents/MacOS/$EXPECTED_EXECUTABLE")"
    for required_architecture in arm64 x86_64; do
        case " $architectures " in
            *" $required_architecture "*) ;;
            *) fail "缺少 $required_architecture 架构，当前为：$architectures" ;;
        esac
    done
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

quit_installed_app() {
    local pids pid executable expected_path matched_pids attempt alive

    pids="$(/usr/bin/pgrep -x "$EXPECTED_EXECUTABLE" 2>/dev/null || true)"
    [[ -n "$pids" ]] || return 0

    expected_path="$INSTALLED_APP/Contents/MacOS/$EXPECTED_EXECUTABLE"
    matched_pids=""
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        executable="$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)"
        executable="$(trim_whitespace "$executable")"
        [[ "$executable" == "$expected_path" ]] || continue
        /bin/kill -TERM "$pid" 2>/dev/null || true
        matched_pids="${matched_pids}${pid}"$'\n'
    done <<< "$pids"

    [[ -n "$matched_pids" ]] || return 0

    for attempt in {1..50}; do
        alive=0
        while IFS= read -r pid; do
            [[ "$pid" =~ ^[0-9]+$ ]] || continue
            if /bin/kill -0 "$pid" 2>/dev/null; then
                alive=1
            fi
        done <<< "$matched_pids"
        [[ "$alive" -eq 0 ]] && return 0
        /bin/sleep 0.2
    done

    fail "GazeEase 未能正常退出。请手动退出后重试；卸载器不会强制结束进程。"
}

for required_command in awk codesign lipo pgrep plutil ps; do
    command -v "$required_command" >/dev/null 2>&1 || fail "缺少必要系统命令：$required_command"
done

verify_installed_app
APP_BUILD="$(read_info_value "$INSTALLED_APP" CFBundleVersion)"

printf '%s\n' \
    '卸载前，请先在 GazeEase 设置中关闭“登录时启动”。' \
    'Before uninstalling, turn off “Launch at Login” in GazeEase Settings.' \
    '' \
    '本脚本只会把 App 移到废纸篓。偏好、疲劳历史和系统权限都会保留。' \
    'This script only moves the app to Trash. Preferences, history, and permissions stay intact.' \
    '' \
    '输入 UNINSTALL 后按 Return 继续；其他输入会取消。' \
    'Type UNINSTALL and press Return to continue; anything else cancels.'

CONFIRMATION=""
if [[ -t 0 ]]; then
    IFS= read -r CONFIRMATION
fi
[[ "$CONFIRMATION" == "UNINSTALL" ]] || fail "已取消，没有移动任何文件。"

quit_installed_app

TRASH_DIR="$HOME/.Trash"
[[ -d "$TRASH_DIR" && -w "$TRASH_DIR" ]] || fail "废纸篓目录不可写：$TRASH_DIR"

TIMESTAMP="$(/bin/date '+%Y%m%d-%H%M%S')"
TRASH_APP="$TRASH_DIR/GazeEase-build${APP_BUILD}-${TIMESTAMP}.app"
if [[ -e "$TRASH_APP" || -L "$TRASH_APP" ]]; then
    TRASH_APP="$TRASH_DIR/GazeEase-build${APP_BUILD}-${TIMESTAMP}-$$.app"
fi
[[ ! -e "$TRASH_APP" && ! -L "$TRASH_APP" ]] || fail "废纸篓目标已存在：$TRASH_APP"

/bin/mv "$INSTALLED_APP" "$TRASH_APP"

if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -u "$TRASH_APP" >/dev/null 2>&1 || true
fi

printf '\n已将 GazeEase 移到废纸篓：\n  %s\n' "$TRASH_APP"
printf '%s\n' \
    '没有删除偏好、分析记录或权限，也没有调用系统隐私或登录项重置工具。' \
    '如果忘记关闭登录启动，请在“系统设置 → 通用 → 登录项”中手动关闭残留项。' \
    '如需彻底清理本地数据，请参阅 INSTALL.zh-CN.md；该操作不会由此脚本自动执行。'
