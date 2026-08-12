# Contributing to GazeEase

Thank you for helping improve GazeEase. The project is a privacy-preserving
macOS eye-care timer, so changes should remain focused, local-first, and easy to
review.

For Chinese instructions, see [CONTRIBUTING.zh-CN.md](CONTRIBUTING.zh-CN.md).

## Project principles

- Do not collect key values, pointer coordinates, screenshots, window titles,
  audio, or clipboard contents.
- Do not add screen recording, analytics, telemetry, network requests, or cloud
  synchronization unless the repository owner has explicitly approved the
  product change first.
- Ordinary inactivity must not silently become verified rest unless it follows
  the user-configured inactivity-rest behavior.
- Keep fatigue, reminder, and rest behavior deterministic and covered by tests.
- Prefer small, reviewable changes over broad refactors.

## Development setup

You need:

- macOS 14 or later;
- Xcode 16 or later;
- [XcodeGen](https://github.com/yonaskolb/XcodeGen).

Generate the Xcode project before building:

```sh
xcodegen generate --spec project.yml
```

The app needs Input Monitoring permission for full runtime verification. Unit
tests and unsigned CI builds must not require that permission.

## Making a change

1. Open an issue first for behavior changes, new permissions, new data
   collection, or significant visual work.
2. Create a focused branch and keep unrelated cleanup out of the change.
3. Add or update tests for behavior changes.
4. Regenerate the Xcode project after changing `project.yml` or source-file
   membership.
5. Do not commit local build output, Xcode user state, generated screenshots,
   signing credentials, or packaged apps.

Match the existing Swift 6, SwiftUI, AppKit, and actor-isolation conventions.
Add comments only when intent is not clear from the code.

## Verification

Run the focused tests first, followed by the full suite when the change can
affect shared behavior:

```sh
xcodebuild \
  -project EyeProtection.xcodeproj \
  -scheme EyeProtection \
  -destination 'platform=macOS' \
  -derivedDataPath /tmp/GazeEaseDerivedData \
  CODE_SIGNING_ALLOWED=NO \
  CODE_SIGNING_REQUIRED=NO \
  test
```

For reminder, menu, settings, or full-screen changes, also inspect the relevant
deterministic screenshots. Do not add the complete generated `Preview/` tree to
a pull request; include only the smallest evidence needed for review.

## Privacy and security

Describe any effect on permissions, local storage, retention, or user-visible
privacy behavior in the pull request. Report vulnerabilities through the
private process in [SECURITY.md](SECURITY.md), not through a public issue.

## Artwork and licensing

The repository's code license does not cover the theme backgrounds, brand
artwork, derived previews, or screenshots described in [ASSETS.md](ASSETS.md).
Do not reuse third-party artwork or submit generated artwork without documenting
its provenance and permitted use.

## Pull request checklist

- [ ] The change has a focused scope and a clear user-facing reason.
- [ ] Behavior changes have tests.
- [ ] Focused and relevant full tests pass.
- [ ] No secrets, personal paths, generated output, or packaged apps are added.
- [ ] Privacy, permissions, persistence, and accessibility impacts are stated.
- [ ] Visual changes include compact review evidence where appropriate.
