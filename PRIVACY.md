# GazeEase Privacy Statement

English · [简体中文](PRIVACY.zh-CN.md)

Last updated: August 12, 2026

## Summary

GazeEase is a local-only macOS eye-rest timer. It detects whether the computer is being actively used, estimates fatigue, validates rest attempts, and presents local reminders. It contains no account system, advertising, telemetry, cloud synchronization, or network upload path.

This statement describes the current private local build identified by `com.local.EyeProtection`.

## Permission used

GazeEase requests **Input Monitoring** permission so it can detect keyboard, click, scroll, trackpad, and pointer activity. This is used only to:

- Accumulate effective-use time.
- Detect inactivity when the optional inactivity-rest setting is enabled.
- Interrupt a manual rest when activity resumes.

Pointer movement may be evaluated transiently to determine whether movement is significant. Mouse coordinates are not stored.

GazeEase does **not** request Screen Recording permission. It does not capture, inspect, save, or transmit screen images.

## Data stored locally

GazeEase stores only the information needed for timing, reminders, restart recovery, and the local Today/7 Days analysis view:

- Input activity type and timing, without key contents.
- Fatigue samples and effective-use duration.
- Overload episodes and reminder-response timing.
- Rest attempt start/end times, source, result, and interruption reason.
- Daily aggregate metrics.
- Preferences such as durations, reminder mode, theme, random-theme schedule, and inactivity-rest setting. Launch-at-login status is queried from macOS rather than copied into the analysis database.
- Runtime state required to restore fatigue and an unresolved rest requirement after restart.

Current local storage locations include:

```text
~/Library/Preferences/com.local.EyeProtection.plist
~/Library/Application Support/EyeProtection.store
~/Library/Application Support/EyeProtection.store-shm
~/Library/Application Support/EyeProtection.store-wal
```

## Data not stored or collected

GazeEase does not store or collect:

- Key contents or typed text.
- Mouse coordinates.
- Screenshots, screen recordings, or screen pixels.
- Window titles or document contents.
- Audio or microphone data.
- Clipboard contents.
- Browsing history.
- Account, contact, precise location, payment, advertising, or device-fingerprint data.

No third-party analytics or advertising SDK is included. No personal data is uploaded to the developer or another service.

## Retention

Automatic local retention currently keeps:

- Fatigue samples for 7 days.
- Overload episodes and rest-attempt details for 30 days.
- Daily summaries for 365 days.

Older records are removed locally when GazeEase starts its maintenance flow.

## User controls and deletion

The Settings window provides **Clear All Analysis Data** for locally stored analysis records. Uninstalling with `Uninstall GazeEase.command` intentionally keeps preferences and history so a reinstall can resume normally.

For complete removal, first quit and uninstall GazeEase, then follow the explicit local-data removal steps in [INSTALL.md](INSTALL.md). GazeEase scripts never run `tccutil`, reset the system privacy database, or silently delete history.

Input Monitoring permission remains controlled by macOS and can be removed manually under **System Settings → Privacy & Security → Input Monitoring**.

## Local notifications and system state

Reminder notifications are created locally through macOS. GazeEase also observes local lock, display-sleep, and system-sleep state so a sufficiently long system rest can complete the configured rest interval. These signals are not uploaded.

## Distribution limitation

The current package is a private Apple Development-signed build for local use. A future public release should publish an updated privacy statement together with its final bundle identity, distribution channel, and support contact.
