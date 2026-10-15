# SpaceScout Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Deliver a native, local macOS storage explorer and conservative Trash-based cleanup app, with buildable MIT-licensed source and a public GitHub release.

**Architecture:** A Foundation library owns scan models, filesystem traversal, cleanup policy, and Trash operations. SwiftUI consumes that library and manages background tasks, selection, confirmations, and Finder navigation. Build scripts create a universal application bundle without external package dependencies.

**Tech Stack:** Swift 6.1 toolchain, Swift language mode 5, Swift Package Manager, SwiftUI/AppKit/Foundation, XCTest, shell packaging scripts, GitHub Actions.

## Global Constraints
- Native macOS 13+ application, Apple silicon and Intel.
- No telemetry, accounts, network calls in the application, administrator access, scheduled deletion, or permanent deletion.
- Nothing selected by default; explicit confirmation before Trash.
- Large personal files, models, applications, and cloud folders are review-only; no claim that age proves disuse.
- Cleanup allowed only inside an explicit local cache-root allowlist and direct old Downloads installer files.
- Reject symlinks, path escapes, identity changes, partial measurements, overlapping candidates, and unsupported roots at cleanup time independently of UI state.
- Report allocated-size estimates separately from measured available space. Moving to Trash does not reclaim space until Trash is emptied.
- Test with temporary fixtures, never remove real user files.
- No private scan data, personal paths, secrets, or local audit reports in the public repository.
- A public unsigned prerelease must clearly disclose the absence of Developer ID signing/notarization.

### Task 1: Safe storage engine
**Files:** Package.swift; Sources/SpaceScoutCore/{Models,StorageInfo,ScanPolicy,FileSnapshot,Scanner,CleanupService}.swift; Tests/SpaceScoutCoreTests/*.swift.
**Interfaces:** Public value models: Candidate (Identifiable with stable String id, URL, title, category, allocatedBytes, modifiedAt, reason, eligibility and snapshot), ScanReport (candidates, issues, cancelled, visitedCount), StorageInfo (totalBytes, availableBytes). Public Scanner initialized with home URL and running bundle IDs; synchronous scan with cancellation/progress closures for background execution. Public CleanupService initialized with home URL, injected Trash operation for fixtures, and running app IDs; explicit-confirmation batch operation returns per-item outcomes and never deletes.
- [ ] Establish a dependency-free library package and fixture helpers.
- [ ] Add failing behavior tests before implementation. Required examples: scan allowed cache reports physical allocation; sibling prefix is rejected; symlink root and symlink candidate rejected; replacing a scanned inode prevents cleanup; changing a nested file prevents directory cleanup; cancellation never enables partial directory cleanup; no confirmation prevents all mutations; large personal file remains review-only; fixture Trash operation moves only approved files and reports failure for refused items.
```swift
XCTAssertFalse(report.candidates.first(where: { $0.url == personalFile })?.isEligible ?? true)
XCTAssertThrowsError(try policy.validate(candidateAtSymlink))
XCTAssertTrue(FileManager.default.fileExists(atPath: original.path))
```
Adapt test code to the final public API and document that API in the task report.
- [ ] Implement metadata-only bounded traversal, no symlink following, hardlink deduplication and allocated bytes; sorted results; root policies; stale installer detection (30 days); large Downloads items; Hugging Face models review-only; permission issues; cancellation.
- [ ] Exclude known running-app caches using bundle IDs. Warn users to close developer tools for CLI caches. Keep broad Library/Caches entries review-only unless explicitly allowlisted. No model cache cleanup.
- [ ] Before Trash, revalidate original roots, all path components, inode/device and tree metadata snapshot; reject partial or changed candidates. Reject candidate overlap and duplicates. Do not provide a public arbitrary-root allowlist bypass. Allow home injection only for isolated tests; protected-root rules still apply. Report per-item results.
- [ ] Run focused tests then full swift test, self-review, commit, and document RED/GREEN evidence.

### Task 2: Native application and distribution
**Files:** Sources/SpaceScout/{SpaceScoutApp,AppModel,MainView,ResultsView,Theme,DemoData}.swift; Resources/Info.plist; scripts/{build-app,make-icon}.sh or swift; README.md; LICENSE; CONTRIBUTING.md; SECURITY.md; .github/workflows/ci.yml; Tests/SpaceScoutCoreTests as needed for meaningful UI-model behavior.
**Interfaces:** Consume the public API from Task 1's report. Application executable product named SpaceScout. Build entry point `./scripts/build-app.sh`; output `dist/SpaceScout.app`, `dist/SpaceScout-<version>-universal.zip`, checksums. Version 0.1.0.
- [ ] Add the executable target and build a polished native UI: light warm background, dark navy sidebar, turquoise accent, storage meter, distinct result categories, search, sort by size, selectable eligible rows, Finder reveal, inspector/help text, and clear primary scan/review action.
- [ ] Execute scans and cleanup off the main thread; cancellation and progress; prevent conflicting operations; no preselection; confirmation sheet lists all selected paths and sizes; errors remain visible; never claim trashed bytes are freed. Refresh measured available space afterward.
- [ ] Add `--demo` with clearly labelled synthetic data for public screenshots; ensure all demo cleanup actions are disabled and no demo scan touches user paths.
- [ ] Add `--scan-json` for a read-only headless smoke check using the real engine (no cleanup CLI).
- [ ] Build bundle metadata and a native vector-generated icon; scripts build both architectures, combine with lipo, and ad-hoc sign for local testing. Optional Developer ID environment setting must enable hardened runtime without storing secrets. No disabling Gatekeeper. Use temporary artifact paths scoped to the project.
- [ ] Add MIT license (2026 SpaceScout contributors), clear install/build/use instructions, threat/limitation notes, contributing/security docs, CI test/build/artifact workflow, and unsigned-prerelease release guidance.
- [ ] Compile, run meaningful tests, package both architectures, verify bundle/signature and documented commands, commit, report validation and limitations.

### Final integration and publication
- [ ] Task review after each task; fix all important findings.
- [ ] Inspect demo application visually; save a public-safe screenshot.
- [ ] Run a real read-only scan; keep report outside public repository.
- [ ] Whole-branch review; inspect all tracked paths and scan for personal paths/secrets.
- [ ] Publish public repository and unsigned 0.1.0 prerelease with universal ZIP/checksum and explicit signing limitation.
- [ ] Verify public repository, CI status, release assets; report app/source links and private audit findings.
