# GazeEase

English · [简体中文](README.zh-CN.md)

GazeEase is a privacy-first macOS menu bar timer that estimates visual fatigue from active computer use. By default, 20 minutes of effective use reaches 100% fatigue and a complete rest takes 20 uninterrupted seconds. Both durations are configurable. Partial recovery below 100% pauses reminders until fatigue reaches 100% again; a complete rest resets fatigue to zero.

## Distribution status

The source is public under the [MIT License](LICENSE). Theme artwork and brand assets have a separate, limited license in [ASSETS.md](ASSETS.md); they are **not** covered by MIT.

Version `1.1.0`, Build `39` is a **source-only public release**, not a ready-to-install public download. Build it with your own development identity using the instructions below. Existing Apple Development local and trusted-test packages are not Developer ID signed or notarized; they are not general-purpose public installers.

<details>
<summary>Existing local packages — maintainer's development Mac only</summary>

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

</details>

## Features and behavior

- The menu bar shows the current fatigue percentage. Fatigue can exceed 100%; values over 999% use a compact display while the exact value is retained.
- Reminder visuals can use Quiet Horizon, Forest Light, Alpine Mist, Twilight Dunes, Moss Garden Rain, Polar Night Glow, Moonlit Bamboo, Rainwashed Sea Cliff, or Cloudfield Wind. The selected theme is shared by full-screen reminders, the unified rest countdown, the top prompt, and the expanded menu panel.
- Settings and the expanded menu panel continue the selected scene, palette, and atmosphere instead of merely recoloring buttons.
- Optional random theme rotation defaults to every 60 minutes, accepts 5–1440 minutes, and never repeats the same theme consecutively. A due rotation waits for a safe moment while a reminder or rest surface is visible.
- Ordinary stillness, reading, or thinking is not considered rest by default.
- The first reminder can be a quiet macOS notification, a two-button top prompt, or a two-button full-screen reminder.
- The top and full-screen prompts show **Not Now** and **Start Rest** directly. Ignoring a system notification continues work; clicking it starts rest.
- Choosing **Not Now** closes the current prompt while fatigue continues accumulating. A new reminder appears at every newly reached 100% multiple; recovery below 100% re-arms these milestones.
- If input interrupts a rest, the recovered fatigue is preserved. The top two-button prompt returns only if fatigue is still at least 100%; below 100%, reminders stay hidden until the threshold is reached again. An interrupted rest remains an interrupted record.
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
3. In **Signing & Capabilities**, select your own Team and a unique Bundle Identifier for your development copy. Update the test target's signing identity if Xcode requests it. Do not reuse the maintainer's Team or app identity.
4. Run the app and enable Input Monitoring for your copy when prompted. Its permission record is separate from an existing installation.
5. If the permission does not apply immediately, quit and reopen the app.

The project is checked in. To regenerate it from `project.yml`, install XcodeGen and run the command below, then reapply your local Team and Bundle Identifier (or set them in your local `project.yml` first). Do not submit personal signing changes.

```sh
xcodegen generate
```

<details>
<summary>Maintainer-only local packaging</summary>

The packaging script uses a fresh DerivedData directory, builds a signed Release, validates the exact bundle ID, team, build number, architectures, and Apple Development signature, then creates a ZIP and SHA-256 file in `Dist/`.

```sh
./Scripts/package-local-release.sh
```

The script intentionally refuses Developer ID or ad-hoc signatures because it is only for the current private local workflow. It does not install or launch the resulting package.

</details>

## Verification

Tests, static analysis, and compile checks do not require the maintainer's signing credentials:

```sh
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionDerivedData CODE_SIGNING_ALLOWED=NO test
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Release -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionReleaseDerivedData CODE_SIGNING_ALLOWED=NO build
xcodebuild -project EyeProtection.xcodeproj -scheme EyeProtection -configuration Debug -destination 'platform=macOS' -derivedDataPath /tmp/EyeProtectionAnalyzeDerivedData CODE_SIGNING_ALLOWED=NO analyze
```

An unsigned compile check is not an installable release. For runtime and permission testing, use your own signed development copy; keep its identity and location stable across your own upgrades.

A future ready-to-install public binary is a separate workflow: Developer ID signing, notarization, stapling, and Gatekeeper verification, followed by target-Mac checks of multi-display behavior, full-screen spaces, permission revocation, lock/sleep recovery, launch at login, and energy usage. Publishing source does not claim these binary-distribution checks are complete.

## Documentation

- [Code license (MIT)](LICENSE) · [Visual asset terms](ASSETS.md)
- [Contributing](CONTRIBUTING.md) · [贡献指南](CONTRIBUTING.zh-CN.md)
- [Installation, upgrade, and uninstall](INSTALL.md)
- [安装、升级与卸载](INSTALL.zh-CN.md)
- [Privacy statement](PRIVACY.md)
- [隐私说明](PRIVACY.zh-CN.md)
