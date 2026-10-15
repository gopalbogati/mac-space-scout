# SpaceScout — proposed first release

15 October 2026. Status: proposed; implementation has not started.

## Purpose
Build a free, open-source macOS application that finds storage-heavy files, explains cleanup candidates, and helps users reclaim space through informed choices. Finding an old or large file is not proof it is unused. The application must never promise a speed increase from a storage scan.

## Recommended approach
Use Swift and SwiftUI with Foundation for a native macOS 13+ application. This provides a small local application, familiar accessibility and Finder integration, and no browser or bundled web runtime. Support Apple silicon and Intel through release builds.

Alternatives: a Tauri desktop application offers easier future Windows/Linux support but adds a web interface and bridge; a command-line tool is simpler to distribute to developers but less suitable for general users. Native macOS best matches the requested audience.

## First-release experience
1. A storage overview shows volume capacity and currently available space.
2. Scan known user cache/build locations and Downloads metadata in the background, with progress and cancellation. Skip symbolic links, cloud-storage roots, and inaccessible locations. Report incomplete coverage clearly.
3. Show results sorted by allocated size, grouped into rebuildable cache candidates, old installers, and large files for review. Include path, size estimate, modified date, and a reason. No items are selected initially. Age alone never means unused.
4. Users can reveal each item in Finder. Cleanup is limited to explicitly selected items under supported local cleanup roots, followed by a confirmation listing paths and sizes. Large personal files and applications are review-only in this release.
5. Use the macOS Trash API for eligible items, never permanent deletion. Revalidate path containment, symlinks, and item identity immediately before acting; refuse changed or unsupported paths. Show per-item success or failure. Exclude items belonging to known running apps when identifiable, and explain that apps should be closed before cache cleanup.
6. Afterward show bytes moved to Trash separately from measured available disk space. Provide a button to open Trash for manual review. Space is not actually reclaimed until Trash is emptied; APFS snapshots and clones can also affect recovered space.

## Boundaries and privacy
The application operates locally without telemetry, accounts, uploads, administrator access, scheduled deletion, or shell-based deletion. Never recursively clean the home directory, system directories, Application Support, browser profiles, Photos libraries, project source, cloud-synced folders, or backups. Do not publish this Mac's scan results or personal paths to GitHub. Root policy is enforced in the cleanup engine, independently of UI selection. Preserve AI models, installed Codex/agent skills, detected Git repositories/project contents, and frequently used data. A cache candidate with any descendant modified within the last 7 days is review-only; older timestamps never establish disuse. Model, skill, and project marker protections apply throughout candidate trees and again before cleanup.

## Components
- Scan engine: bounded background traversal, allocated-size measurement, cancellation, and permission/error reporting.
- Classification policy: a small explicit list of supported cache roots and installer extensions, with conservative labels.
- Cleanup service: fresh validation and macOS Trash operations, with structured per-item outcomes.
- SwiftUI application: overview, result filtering, selection, Finder reveal, and confirmation.
- Build/distribution scripts and automated tests: source build, app packaging, and release checks.

## Validation
Use temporary fixtures to test permitted paths, rejected system/personal paths, symlink escapes, identity changes after scanning, overlapping selections, inaccessible files, cancellation, and size accounting. Tests must not operate on the user's real files. Compile and launch the app on this Mac, inspect the interface, and perform a read-only scan. Only move user files after the user selects or approves the exact candidates.

## Open source and delivery
Proposed repository: gopalbogati/mac-space-scout, public, MIT license. Include source, a plain-language README, screenshots made with sample data, build instructions, contribution guidance, security reporting guidance, automated macOS build/tests, and packaged release artifacts. Publish only project files; keep the private audit outside the repository.

For straightforward distribution to other Macs, use Developer ID signing and Apple notarization if a suitable identity and credentials are available. If unavailable, deliver buildable source and clearly labelled unsigned test artifacts with the limitation documented; never instruct users to disable Gatekeeper globally. A polished installable, signed public release requires those credentials.

## Success criteria
The app builds and launches; provides real local storage data; reports partial scans honestly; never marks age as proof of disuse; requires an explicit selection and confirmation for cleanup; blocks unsupported paths; moves eligible items only to Trash; and has a public GitHub repository with an MIT license and reproducible build instructions.

## References
- Apple storage guidance: https://support.apple.com/en-au/102624
- Apple Trash API: https://developer.apple.com/documentation/foundation/filemanager/trashitem(at:resultingitemurl:)
- Apple notarization guidance: https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution
