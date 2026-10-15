# SpaceScout

A small native macOS app for understanding storage and reviewing conservative cleanup candidates. SwiftUI, local metadata scans, and macOS Trash. Free and open source under the [MIT license](LICENSE).

**0.1.0 preview:** targets macOS 13 or later, Apple silicon and Intel. The packaged preview is **ad-hoc signed, not Developer ID signed or notarized**. Gatekeeper may prevent it from opening. Building from source is recommended for this preview; see [Apple’s app-specific security guidance](https://support.apple.com/en-au/102445). Do not disable system security protections.

## What it does

- Shows measured volume capacity and available space separately from allocated-size estimates.
- Scans supported developer caches and Downloads metadata in the background, with cancellation and visible partial-coverage issues.
- Filters findings by category, searches paths, sorts by size, and explains why an item needs review.
- Starts with nothing selected. Only eligible items can be selected. A confirmation lists every exact selected path and size before fresh engine validation and a move to Trash.
- Preserves AI models, installed skills, detected Git/project contents, cloud storage, applications and personal files. Large Downloads folders and unknown caches are review-only.
- Keeps per-item refusals and failures visible. Provides Open Trash for manual review, with no Empty Trash action.

Moving an item to Trash does **not** immediately reclaim disk space. APFS clones, snapshots and shared storage also make allocated estimates different from potential free-space gains. SpaceScout does not promise a faster Mac.

## Install and run

Download the universal ZIP and SHA-256 checksum from [Releases](https://github.com/gopalbogati/mac-space-scout/releases). Verify the downloaded ZIP with `shasum -a 256 -c SpaceScout-0.1.0-universal.zip.sha256` from its containing directory, unzip it, then move `SpaceScout.app` to a location you choose. The preview signing limitation above applies.

Open SpaceScout and choose **Scan storage**. Results stay in memory. Review the explanations, reveal files in Finder if needed, close related apps and command-line tools, select eligible items, then choose **Review selection**. Confirm only paths you understand. Files that changed since scanning are refused.

For a screenshot-safe demonstration, run from the source checkout after building:

```sh
open dist/SpaceScout.app --args --demo
```

Demo mode displays a permanent synthetic-data notice. Scanning, cleanup, Trash and Finder actions are disabled. Normal launch never scans automatically.

## Build and test

Use a Mac with Swift 6.1 or newer and Apple’s Command Line Tools or Xcode. There are no external package dependencies. The app targets macOS 13+, while automated CI uses a newer macOS runner. The first preview is locally tested on an Apple silicon Mac; Intel and the minimum macOS version are build targets, not claims of hardware testing.

```sh
git clone https://github.com/gopalbogati/mac-space-scout.git
cd mac-space-scout
swift test
./scripts/build-app.sh
open dist/SpaceScout.app
```

The build script compiles `arm64` and `x86_64`, combines and strips the executable, generates the icon using AppKit, and ad-hoc signs the app. It writes:

```text
dist/SpaceScout.app
dist/SpaceScout-0.1.0-universal.zip
dist/SpaceScout-0.1.0-universal.zip.sha256
```

Maintainers with an existing Developer ID Application identity may set `DEVELOPER_ID_APPLICATION` when running the build script. That enables hardened runtime and timestamped signing. The script does not obtain credentials, submit notarization or publish releases. Developer ID signing alone is not notarization.

A read-only JSON smoke scan is available:

```sh
dist/SpaceScout.app/Contents/MacOS/SpaceScout --scan-json > /private/tmp/spacescout-private-scan.json
```

This output includes personal paths. Keep it private; do not attach it to issues or commit it. There is no cleanup command-line mode. Combining `--demo` and `--scan-json` outputs synthetic data only.

## Scope and limits

The cleanup allowlist is limited to immediate children of `Library/Caches/pip`, `Library/Caches/Homebrew`, `Library/Caches/org.swift.swiftpm`, `Library/Caches/com.apple.dt.Xcode`, `Library/Developer/Xcode/DerivedData`, `.npm/_cacache`, `.cache/pip`, and `.cache/uv`, plus direct regular Downloads `.dmg`/`.pkg` installers at least 30 days old. Every recorded cache entry must be at least seven days old. Age never proves disuse. Known running apps, recent activity, model/skill/project markers, hard links, links, incomplete measurements and unsupported paths block cleanup. Marker detection is conservative and can protect more files than expected.

This is a bounded scan, not a full-disk inventory: up to 500,000 entries, 64 levels and 60 seconds. Permissions and exclusions can leave coverage incomplete. The app reports issues rather than asking for administrator privileges or Full Disk Access. It reads metadata, not file contents, and does not traverse arbitrary user-selected roots. Finding nothing eligible is a valid result.

The engine rechecks original roots, identities and tree metadata before Trash. Filesystem changes and the path-based macOS Trash API cannot be made into an atomic transaction; a concurrent change remains possible after the last check. Close related processes and keep backups. No deletion tool can infer whether you still need an old opaque file.

## Privacy, contributions and releases

No accounts, telemetry, uploads, application network calls, background scheduler or permanent deletion. Scan reports are kept in memory and not saved by the app. Finder actions open only user-requested locations. See [security guidance](SECURITY.md) and [contribution instructions](CONTRIBUTING.md).

[Source and issues](https://github.com/gopalbogati/mac-space-scout) · [Releases](https://github.com/gopalbogati/mac-space-scout/releases)

CI tests and builds artifacts; it never publishes a release automatically. A maintainer must review the source, signing status, privacy and checksums before publishing a prerelease. All public screenshots must use labelled demo data.
