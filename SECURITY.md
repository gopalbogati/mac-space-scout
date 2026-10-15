# Security and privacy

SpaceScout operates locally. The app has no accounts, telemetry, network requests, uploads, scheduled cleanup, administrator flow, shell deletion or permanent-delete API. Results remain in memory until the app closes; explicit `--scan-json` output is the operator’s responsibility and contains private paths.

The 0.1.x preview is the currently supported line. Preview artifacts are ad-hoc signed and are not Developer ID signed or notarized unless a particular release explicitly provides verified signing and notarization details. Prefer a source build for review.

## Reporting

For a suspected vulnerability, use [GitHub private vulnerability reporting](https://github.com/gopalbogati/mac-space-scout/security/advisories/new) if it is available. If that feature is unavailable, open a minimal issue requesting a private reporting channel without publishing exploit details, private filenames or scan data. Do not attach real storage reports. Synthetic fixture paths and a minimal reproduction are sufficient.

## Trust boundaries

The UI cannot authorize unsupported paths. The engine validates the cleanup allowlist, protected components and containing project markers, recent activity, ownership, symlink-free ancestry, original item identity and a complete original metadata snapshot. Changed or incomplete candidates, models, skills, projects and hardlinked items are refused. Unknown cache roots and large personal files are review-only. Protection is deliberately conservative.

Checks are bounded. The operating system’s path-based Trash call is not an atomic transaction with metadata validation: another process can change a file after the final check. Close related processes and use backups. The tool does not defend against a malicious process with equal access to your files, prove a file is unused, or guarantee recovery after the user empties Trash. Allocated byte estimates are not guarantees of reclaimed capacity.

All mutation tests must use temporary fixtures and an injected operation into a fixture Trash folder. Do not test cleanup against real user data. Public screenshots must use `--demo`, which disables real scans and all file operations.
