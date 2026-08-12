# GazeEase

English · [简体中文](README.zh-CN.md)

GazeEase is a privacy-first macOS menu bar timer that estimates visual fatigue from active computer use. By default, 20 minutes of effective use reaches 100% fatigue and a complete rest takes 20 uninterrupted seconds. Both durations are configurable. Once rest is required, that requirement remains latched until a complete rest finishes.

## Distribution status

This repository currently produces a **private, local Apple Development build** for the developer's own Mac. It is not Developer ID signed or notarized, and it is not intended for public redistribution. Do not remove quarantine attributes, ad-hoc re-sign the app, or treat this package as a public release.

Public distribution requires a stable final bundle identity, a Developer ID Application certificate, a Release build without `get-task-allow`, Apple notarization, stapling, and Gatekeeper verification.

## Install without Xcode

If you received a local GazeEase ZIP package:

> This package is intended for the same developer Mac that built it. A ZIP
> downloaded from GitHub may carry quarantine and is intentionally rejected by
> the local installer; wait for a notarized Developer ID build for normal public download.

1. Extract the ZIP completely.
2. Keep `GazeEase.app` and `Install GazeEase.command` in the same folder.
3. Double-click `Install GazeEase.command`.
4. The installer validates the app and installs it at the fixed path `/Applications/GazeEase.app`.
5. On first launch, follow the app's prompt to enable Input Monitoring. Quit and reopen GazeEase if macOS does not apply the permission immediately.

The installer never grants or resets privacy permissions, changes the launch-at-login setting, or deletes preferences and history. See [Installation and upgrades](INSTALL.md) for complete instructions.

## Features and behavior

- The menu bar shows the current fatigue percentage. Fatigue can exceed 100%; values over 999% use a compact display while the exact value is retained.
- Reminder visuals can use Lake Horizon, Forest Skylight, Snow Ridge Mist, or Twilight Dunes. The selected theme is shared by full-screen reminders, the unified rest countdown, the top prompt, and the expanded menu panel.
- Settings and the expanded menu panel continue the selected scene, palette, and atmosphere instead of merely recoloring buttons.
- Optional random theme rotation defaults to every 60 minutes, accepts 5–1440 minutes, and never repeats the same theme consecutively. A due rotation waits for a safe moment while a reminder or rest surface is visible.
- Ordinary stillness, reading, or thinking is not considered rest by default.
- The first reminder can be a quiet macOS notification, a two-button top prompt, or a two-button full-screen reminder.
- The top and full-screen prompts show **Not Now** and **Start Rest** directly. Ignoring a system notification continues work; clicking it starts rest.
- Choosing **Not Now** closes the current prompt while fatigue, the latched rest requirement, and overload duration continue accumulating. A new reminder appears at every newly reached 100% multiple.
- If keyboard, click, scroll, or significant pointer movement interrupts a manual rest, the top two-button prompt returns so rest can be restarted.
- Starting rest covers every display. Input interrupts the rest attempt.
- The use interval accepts 1–180 minutes; the complete rest duration accepts 5–300 seconds.
- Changing the use interval recalculates fatigue from accumulated effective use. Changing rest duration only affects the rest countdown.
- Optional inactivity rest can clear fatigue after 1–180 minutes with no keyboard, mouse, or trackpad activity. Any input restarts that inactivity timer.
- A locked screen, sleeping display, or system sleep can complete rest after the configured rest duration.
- Fatigue, the latched rest requirement, reminder milestone progress, theme rotation schedule, and the active overload episode survive app restarts.

## Privacy

GazeEase requires Input Monitoring to detect activity and rest interruptions. It does not request Screen Recording permission and does not capture screen content.

All processing and storage are local. The app does not store key contents, mouse coordinates, screenshots, window titles, audio, or clipboard data, and it contains no telemetry or network upload path. See the full [Privacy statement](PRIVACY.md).

## Run from Xcode

Requirements: macOS 14 or later and Xcode 16 or later.

1. Open `EyeProtection.xcodeproj`.
2. Select the `EyeProtection` scheme and `My Mac`.
3. Run the app and enable Input Monitoring when prompted.
4. If the permission does not apply immediately, quit and reopen the app.

To regenerate the project from `project.yml`, install XcodeGen and run:

```sh
xcodegen generate
```

## Create the private local package

The packaging script uses a fresh DerivedData directory, builds a signed Release, validates the exact bundle ID, team, build number, architectures, and Apple Development signature, then creates a ZIP and SHA-256 file in `Dist/`.

```sh
./Scripts/package-local-release.sh
```

The script intentionally refuses Developer ID or ad-hoc signatures because it is only for the current private local workflow. It does not install or launch the resulting package.

## Verification

```sh
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionDerivedData test
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionReleaseDerivedData build
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionAnalyzeDerivedData CODE_SIGNING_ALLOWED=NO analyze
```

The local Release must retain the Apple Development signature produced by Xcode and must be copied as a complete bundle. Never overwrite it with an ad-hoc signature. Keeping the bundle ID, development team, signing identity, and installation path stable gives macOS the best chance of recognizing updates as the same app.

Before any public release, complete Developer ID signing and notarization, then verify multi-display behavior, full-screen spaces, permission revocation, lock/sleep recovery, launch at login, and a two-hour Energy Log on the target Mac.

## Documentation

- [Installation, upgrade, and uninstall](INSTALL.md)
- [安装、升级与卸载](INSTALL.zh-CN.md)
- [Privacy statement](PRIVACY.md)
- [隐私说明](PRIVACY.zh-CN.md)
