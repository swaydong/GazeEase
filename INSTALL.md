# Install, Upgrade, and Uninstall GazeEase

English · [简体中文](INSTALL.zh-CN.md)

## Scope

These instructions describe the current private local distribution workflow. The package is Apple Development signed for the developer's own Mac. It is not Developer ID signed or notarized for public distribution.

The installer intentionally rejects a quarantined app bundle. Do not remove
quarantine attributes to make this private build launch. A package downloaded
from GitHub is source or release evidence only until a notarized Developer ID build exists.

The canonical installation path is:

```text
/Applications/GazeEase.app
```

Do not run daily builds from changing Xcode, DerivedData, Downloads, or repository paths. Keeping the bundle ID, team, signing identity, and path stable reduces duplicate macOS permission and login-item records.

## Install the local package

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

If Gatekeeper blocks either the command file or app, stop instead of bypassing the warning. The private Apple Development package is only supported on the intended development Mac; another Mac requires a Developer ID-signed and notarized release.

## First launch and Input Monitoring

GazeEase needs Input Monitoring to detect activity and rest interruptions. macOS alone controls this permission; the installer cannot grant it.

1. Open GazeEase.
2. Follow its permission prompt, or open **System Settings → Privacy & Security → Input Monitoring**.
3. Enable GazeEase.
4. Quit and reopen GazeEase if the status does not refresh immediately.

GazeEase does not need Screen Recording permission.

Moving an already-authorized development copy to the canonical path can require one additional authorization. Future upgrades should always use the same path and identity. A later transition from Apple Development to Developer ID may also require authorization again.

## Upgrade

Use the new ZIP's `Install GazeEase.command` exactly as for the first install.

- Preferences, fatigue history, theme settings, and runtime state remain outside the app bundle and are preserved.
- A lower `CFBundleVersion` is rejected.
- Reinstalling the same build requires confirmation.
- The old app remains available for automatic rollback until the new copy passes final validation and macOS accepts the request to open it.
- The installer does not enable or disable launch at login. If macOS shows **Requires Approval** after a migration, approve GazeEase in System Settings or toggle the setting once inside the app.

## Verify an installed local build

```sh
INSTALL_APP="/Applications/GazeEase.app"

codesign --verify --deep --strict --verbose=2 "$INSTALL_APP"
plutil -extract CFBundleIdentifier raw -o - "$INSTALL_APP/Contents/Info.plist"
plutil -extract CFBundleVersion raw -o - "$INSTALL_APP/Contents/Info.plist"
lipo -archs "$INSTALL_APP/Contents/MacOS/Eye Protection"
codesign -dv --verbose=4 "$INSTALL_APP"
codesign -d --entitlements :- "$INSTALL_APP"
```

Expected local identity:

- Bundle ID: `com.local.EyeProtection`
- Team ID: `3Q9DKW2UKF`
- Architectures: `arm64` and `x86_64`
- Authority: Apple Development

Gatekeeper acceptance is not an acceptance criterion for this private development build. It becomes mandatory for a future Developer ID and notarized public release.

## Uninstall while keeping data

1. Open GazeEase Settings and turn off **Launch at Login** first. This lets the app unregister itself from macOS correctly.
2. Double-click `Uninstall GazeEase.command`.
3. Type `UNINSTALL` when prompted.
4. The script verifies the exact installed app, quits it normally, and moves it from `/Applications/GazeEase.app` to the current user's Trash.

This default uninstall is recoverable and preserves preferences, fatigue history, and privacy permissions. If launch at login was not disabled before removal, turn off the remaining item under **System Settings → General → Login Items**.

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

## Create the local ZIP

For maintainers with Xcode and the expected Apple Development identity installed:

```sh
./Scripts/package-local-release.sh
```

The script builds in an isolated temporary DerivedData directory and writes a versioned ZIP plus SHA-256 file to `Dist/`. It refuses to overwrite an existing package of the same version and build.

## Public distribution is a separate workflow

Before sharing GazeEase broadly, replace this local workflow with:

1. A final globally unique bundle identifier and migration plan.
2. Developer ID Application signing with Hardened Runtime and a secure timestamp.
3. A Release entitlement set without `get-task-allow=true`.
4. Apple notarization with `notarytool`.
5. Stapling and Gatekeeper verification.
6. A notarized ZIP or DMG tested on a clean target Mac.

Do not reuse the local packaging script as evidence that those public-distribution requirements are complete.
