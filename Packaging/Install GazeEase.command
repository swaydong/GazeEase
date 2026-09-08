#!/bin/bash

set -euo pipefail
IFS=$'\n\t'

readonly EXPECTED_BUNDLE_ID="com.local.EyeProtection"
readonly EXPECTED_TEAM_ID="3Q9DKW2UKF"
readonly EXPECTED_EXECUTABLE="Eye Protection"
readonly DESTINATION_APP="/Applications/GazeEase.app"
readonly LSREGISTER="/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
SOURCE_APP="$SCRIPT_DIR/GazeEase.app"
STAGE_APP="/Applications/.GazeEase.installing.$$.app"
BACKUP_APP="/Applications/.GazeEase.previous.$$.app"
BACKUP_MOVED=0
NEW_AT_DESTINATION=0
INSTALL_COMPLETED=0

fail() {
    printf '安装失败 / Installation failed: %s\n' "$*" >&2
    exit 1
}

warn() {
    printf '提示 / Note: %s\n' "$*" >&2
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

    [[ -d "$app_path" ]] || fail "找不到 App：$app_path"
    [[ ! -L "$app_path" ]] || fail "拒绝处理符号链接 App：$app_path"
    [[ -f "$app_path/Contents/Info.plist" ]] || fail "App 缺少 Info.plist：$app_path"

    /usr/bin/codesign --verify --deep --strict --verbose=2 "$app_path" >/dev/null

    actual_bundle_id="$(read_info_value "$app_path" CFBundleIdentifier)"
    [[ "$actual_bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || \
        fail "Bundle ID 不匹配：$actual_bundle_id"

    actual_executable="$(read_info_value "$app_path" CFBundleExecutable)"
    [[ "$actual_executable" == "$EXPECTED_EXECUTABLE" ]] || \
        fail "可执行文件名称不匹配：$actual_executable"

    actual_build="$(read_info_value "$app_path" CFBundleVersion)"
    [[ "$actual_build" =~ ^[0-9]+$ ]] || fail "Build 号无效：$actual_build"

    actual_version="$(read_info_value "$app_path" CFBundleShortVersionString)"
    [[ "$actual_version" =~ ^[0-9A-Za-z][0-9A-Za-z._-]*$ ]] || \
        fail "版本号无效：$actual_version"

    signing_output="$(signature_details "$app_path")"
    actual_team="$(/usr/bin/awk -F= '$1 == "TeamIdentifier" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$actual_team" == "$EXPECTED_TEAM_ID" ]] || fail "签名 Team 不匹配：$actual_team"

    signing_authority="$(/usr/bin/awk -F= '$1 == "Authority" { print substr($0, index($0, "=") + 1); exit }' <<< "$signing_output")"
    [[ "$signing_authority" == Apple\ Development:* ]] || \
        fail "此本机安装器只接受 Apple Development 签名，当前为：$signing_authority"

    architectures="$(/usr/bin/lipo -archs "$app_path/Contents/MacOS/$EXPECTED_EXECUTABLE")"
    for required_architecture in arm64 x86_64; do
        case " $architectures " in
            *" $required_architecture "*) ;;
            *) fail "缺少 $required_architecture 架构，当前为：$architectures" ;;
        esac
    done
}

safe_remove_install_artifact() {
    local target="$1"
    case "$target" in
        /Applications/.GazeEase.installing.*.app|/Applications/.GazeEase.previous.*.app|/Applications/GazeEase.app) ;;
        *) return 1 ;;
    esac
    if [[ -e "$target" || -L "$target" ]]; then
        /bin/rm -rf -- "$target"
    fi
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

quit_running_instances() {
    local pids pid executable suffix bundle_root bundle_id matched_pids attempt alive

    pids="$(/usr/bin/pgrep -x "$EXPECTED_EXECUTABLE" 2>/dev/null || true)"
    [[ -n "$pids" ]] || return 0

    matched_pids=""
    suffix="/Contents/MacOS/$EXPECTED_EXECUTABLE"
    while IFS= read -r pid; do
        [[ "$pid" =~ ^[0-9]+$ ]] || continue
        executable="$(/bin/ps -p "$pid" -o comm= 2>/dev/null || true)"
        executable="$(trim_whitespace "$executable")"
        [[ "$executable" == *"$suffix" ]] || continue
        bundle_root="${executable%"$suffix"}"
        [[ -f "$bundle_root/Contents/Info.plist" ]] || continue
        bundle_id="$(read_info_value "$bundle_root" CFBundleIdentifier 2>/dev/null || true)"
        [[ "$bundle_id" == "$EXPECTED_BUNDLE_ID" ]] || continue
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

    fail "护眼之道未能正常退出。请手动退出后重试；安装器不会强制结束进程。"
}

finish_install() {
    local result=$?
    trap - EXIT
    set +e

    if [[ "$INSTALL_COMPLETED" -eq 1 ]]; then
        safe_remove_install_artifact "$STAGE_APP"
        safe_remove_install_artifact "$BACKUP_APP"
    else
        if [[ "$NEW_AT_DESTINATION" -eq 1 ]]; then
            safe_remove_install_artifact "$DESTINATION_APP"
        fi
        if [[ "$BACKUP_MOVED" -eq 1 && -d "$BACKUP_APP" && ! -e "$DESTINATION_APP" ]]; then
            if /bin/mv "$BACKUP_APP" "$DESTINATION_APP"; then
                printf '已恢复原版本 / Previous version restored.\n' >&2
                if [[ -x "$LSREGISTER" ]]; then
                    "$LSREGISTER" -f "$DESTINATION_APP" >/dev/null 2>&1 || true
                fi
            else
                printf '无法自动恢复；原版本仍位于：%s\n' "$BACKUP_APP" >&2
            fi
        fi
        safe_remove_install_artifact "$STAGE_APP"
    fi

    exit "$result"
}

[[ -d "$SOURCE_APP" ]] || fail "请将安装脚本与 GazeEase.app 保持在同一文件夹。"
for required_command in awk codesign ditto lipo open pgrep plutil ps; do
    command -v "$required_command" >/dev/null 2>&1 || fail "缺少必要系统命令：$required_command"
done
[[ -d /Applications && -w /Applications ]] || \
    fail "/Applications 当前不可写。请使用具有管理员权限的 macOS 账户运行安装器。"
[[ ! -e "$STAGE_APP" && ! -L "$STAGE_APP" ]] || fail "临时安装路径已存在：$STAGE_APP"
[[ ! -e "$BACKUP_APP" && ! -L "$BACKUP_APP" ]] || fail "临时备份路径已存在：$BACKUP_APP"

verify_local_app "$SOURCE_APP"
SOURCE_BUILD="$(read_info_value "$SOURCE_APP" CFBundleVersion)"
SOURCE_VERSION="$(read_info_value "$SOURCE_APP" CFBundleShortVersionString)"

if /usr/bin/xattr -p com.apple.quarantine "$SOURCE_APP" >/dev/null 2>&1; then
    fail "当前是私有本机开发包，但下载来源为受隔离文件。请不要绕过 Gatekeeper；请改用同一台开发 Mac 生成的本机包，或等待 Developer ID 公证版本。"
fi

if [[ -e "$DESTINATION_APP" || -L "$DESTINATION_APP" ]]; then
    verify_local_app "$DESTINATION_APP"
    INSTALLED_BUILD="$(read_info_value "$DESTINATION_APP" CFBundleVersion)"
    if (( 10#$SOURCE_BUILD < 10#$INSTALLED_BUILD )); then
        fail "拒绝从 Build $INSTALLED_BUILD 降级到 Build $SOURCE_BUILD。"
    fi
    if [[ "$SOURCE_BUILD" == "$INSTALLED_BUILD" ]]; then
        printf '当前已安装相同的 Build %s。按 Return 重新安装，或按 Control-C 取消。\n' "$SOURCE_BUILD"
        [[ -t 0 ]] || fail "非交互模式下不会自动重装相同 Build。"
        IFS= read -r _
    fi
fi

trap finish_install EXIT

printf '正在验证并准备护眼之道 %s (Build %s)...\n' "$SOURCE_VERSION" "$SOURCE_BUILD"
/usr/bin/ditto "$SOURCE_APP" "$STAGE_APP"
verify_local_app "$STAGE_APP"

quit_running_instances

if [[ -e "$DESTINATION_APP" || -L "$DESTINATION_APP" ]]; then
    /bin/mv "$DESTINATION_APP" "$BACKUP_APP"
    BACKUP_MOVED=1
fi

/bin/mv "$STAGE_APP" "$DESTINATION_APP"
NEW_AT_DESTINATION=1
verify_local_app "$DESTINATION_APP"

if [[ -x "$LSREGISTER" ]]; then
    "$LSREGISTER" -f "$DESTINATION_APP" >/dev/null 2>&1 || \
        warn "Launch Services 注册未完成，但 App 已安全安装。"
fi

/usr/bin/open "$DESTINATION_APP"
INSTALL_COMPLETED=1

printf '\n安装完成 / Installation complete:\n  %s\n' "$DESTINATION_APP"
printf '安装器未修改输入监控权限、登录项、偏好或历史数据。\n'
printf '若这是首次迁移到固定路径，请按 App 引导确认“输入监控”权限。\n'
