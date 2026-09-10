# Install, Upgrade, and Uninstall GazeEase

English · [简体中文](INSTALL.zh-CN.md)

## Download and install the test build

Version `1.1.0` (Build `40`) is available as an **unnotarized test prerelease** for macOS 14 or later. The app contains both `arm64` and `x86_64` builds for Apple silicon and Intel Macs. You do not need Xcode.

1. Download [`GazeEase-1.1.0-build40-macos-test.zip`](https://github.com/swaydong/GazeEase/releases/download/v1.1.0-test.40/GazeEase-1.1.0-build40-macos-test.zip) from the [official release page](https://github.com/swaydong/GazeEase/releases/tag/v1.1.0-test.40).
2. Extract the complete ZIP. You can compare its SHA-256 with the checksum on the same official release.
3. Drag `GazeEase.app` into **Applications**.
4. Open GazeEase from Applications.

The app is signed with **Apple Development**, not Developer ID, and has **not been notarized by Apple**. This is a test download, not a guarantee of Gatekeeper acceptance or compatibility with every Mac. It has not yet been tested on a separate clean Mac. Share the official release page rather than repackaging or forwarding an altered app.

The installation path remains:

```text
/Applications/GazeEase.app
```

Keeping the app at this path reduces duplicate macOS permission and login-item records. Do not run your daily copy from Downloads or changing build directories.

## If macOS blocks the first launch

Only proceed if you trust this project's official release, have verified the download source, and have no reason to think the app was altered.

If the warning says the developer cannot be verified or Apple cannot check the app for malicious software:

1. Dismiss the alert.
2. Open **System Settings → Privacy & Security**.
3. Find the blocked GazeEase entry under Security and select **Open Anyway**.
4. Authenticate and confirm **Open** when prompted.

Follow [Apple's official instructions](https://support.apple.com/en-us/102445). If the option is unavailable, stop and report the full warning; a managed Mac may prohibit it. If macOS says the app **“is damaged”** or **“will damage your computer,” do not continue**. Remove that copy and report the complete alert to the maintainer.

Do not disable Gatekeeper, remove quarantine attributes, or re-sign the downloaded app to force it to run.

<details>
<summary>Maintainer-only local package: a different installation workflow</summary>

The older `-local.zip` package and its `Install GazeEase.command` are for the maintainer's intended development Mac, not this public test download. That installer intentionally rejects quarantined app bundles; do not remove quarantine to work around it.

1. Extract the complete `GazeEase-<version>-build<build>-local.zip` archive.
2. Optionally compare its SHA-256 against the adjacent `.sha256` file.
3. Keep `GazeEase.app` and `Install GazeEase.command` together.
4. Double-click `Install GazeEase.command`.
5. The installer validates all of the following before replacing anything:
   - Bundle ID `com.local.EyeProtection`
   - Team ID `3Q9DKW2UKF`
   - Apple Development signature and complete code seal
   - Numeric build number
   - `arm64` and `x86_64` architectures
6. The installer copies and verifies a staging bundle, asks the running app to terminate, and then performs an in-place replacement. If replacement or final validation fails, it restores the previous app path.
7. GazeEase opens from `/Applications/GazeEase.app` after a successful install.

The installer never uses `tccutil`, clears permissions, strips quarantine, ad-hoc re-signs the bundle, changes the launch-at-login setting, or deletes application data.

If Gatekeeper blocks that command file or local app, stop. Other testers should use the `-macos-test.zip` release and the manual installation workflow above instead.

</details>

## First launch and Input Monitoring

GazeEase needs Input Monitoring to detect activity and rest interruptions. macOS alone controls this permission; installing the app cannot grant it.

1. Open GazeEase.
2. Follow its permission prompt, or open **System Settings → Privacy & Security → Input Monitoring**.
3. Enable GazeEase.
4. Quit and reopen GazeEase if the status does not refresh immediately.

GazeEase does not need Screen Recording permission.

Moving an already-authorized development copy to the canonical path can require one additional authorization. Future upgrades should always use the same path and identity. A later transition from Apple Development to Developer ID may also require authorization again.

## Manual upgrades

There is no automatic updater.

1. Quit GazeEase normally so it can save its state.
2. Download a newer test package from the official release page and extract it.
3. Drag the new `GazeEase.app` into Applications and choose **Replace**.
4. Reopen the app. If macOS asks for approval or Input Monitoring again, follow the steps above.

Preferences, fatigue history, and theme settings are stored outside the app bundle and are retained when only the app is replaced. Do not remove local data as part of an upgrade. Keep a known-working package if you want a fallback; manual replacement does not perform the local installer's automatic rollback or downgrade checks.

If macOS shows **Requires Approval** for Launch at Login, approve GazeEase in System Settings or toggle the setting once inside the app.

## Known test-build limitations

- First-launch approval may be needed on each Mac and again after an update.
- A company- or school-managed Mac may block the app or Input Monitoring entirely.
- Development signing can expire or be revoked; a replacement build may be needed.
- Updates are manual. There is no claim that an unnotarized test build will run on every Mac.
- Verification on another clean Mac is still pending; please report your macOS version, chip, and the full warning if installation fails.

<details>
<summary>Optional signature and architecture verification</summary>

```sh
INSTALL_APP="/Applications/GazeEase.app"

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
plutil -extract CFBundleIdentifier raw -o - "$INSTALL_APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw -o - "$INSTALL_APP/Contents/Info.plist"
lipo -archs "$INSTALL_APP/Contents/MacOS/Eye Protection"
codesign -dv --verbose=4 "$INSTALL_APP"
codesign -d --entitlements :- "$INSTALL_APP"
```

Expected test-build identity:

- Bundle ID: `com.local.EyeProtection`
- Team ID: `3Q9DKW2UKF`
- Architectures: `arm64` and `x86_64`
- Authority: Apple Development

These checks verify the code seal and build identity, not Apple notarization or trustworthiness by themselves. The package is not notarized.

</details>

## Uninstall while keeping data

1. Open GazeEase Settings and turn off **Launch at Login** first. This lets the app unregister itself from macOS correctly.
2. Quit GazeEase normally.
3. Move `/Applications/GazeEase.app` to Trash in Finder.

Moving only the app to Trash is recoverable and preserves preferences, fatigue history, and privacy permissions. If launch at login was not disabled before removal, turn off the remaining item under **System Settings → General → Login Items**. The maintainer's older local package also includes a guarded `Uninstall GazeEase.command`; that script is not required for the public test package.

## Optional complete local-data removal

Only do this after quitting and uninstalling GazeEase, and only if you do not want to keep history for a future reinstall. The uninstall script deliberately does not perform these steps.

Remove the preference domain:

```sh
defaults delete com.local.EyeProtection
```

Then remove these three exact SwiftData files in Finder, if present:

```text
~/Library/Application Support/EyeProtection.store
~/Library/Application Support/EyeProtection.store-shm
~/Library/Application Support/EyeProtection.store-wal
```

To remove the system permission record, use **System Settings → Privacy & Security → Input Monitoring**. No project script invokes `tccutil` or resets privacy databases.

## Maintainer: create a local ZIP

For maintainers with Xcode and the expected Apple Development identity installed:

```sh
./Scripts/package-local-release.sh
```

The script builds in an isolated temporary DerivedData directory and writes a versioned ZIP plus SHA-256 file to `Dist/`. It refuses to overwrite an existing package of the same version and build.

## Future notarized distribution

The current test ZIP can be downloaded publicly, but a smoother Developer ID-notarized release requires a separate workflow:

1. A final globally unique bundle identifier and migration plan.
2. Developer ID Application signing with Hardened Runtime and a secure timestamp.
3. A Release entitlement set without `get-task-allow=true`.
4. Apple notarization with `notarytool`.
5. Stapling and Gatekeeper verification.
6. A notarized ZIP or DMG tested on a clean target Mac.

Neither a local package nor this test download is evidence that these notarization steps are complete.
