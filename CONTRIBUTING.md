# Contributing

Start with a small issue or pull request explaining the user-visible behavior. Use Swift 6.1+ on macOS, `swift test`, then `./scripts/build-app.sh`. Keep the application native and dependency-free. CI builds both supported architectures and uploads a preview artifact; passing CI does not establish notarization or test Intel hardware.

Safety changes need tests with isolated temporary fixture homes, never real user cleanup. Keep the scanner and cleanup policy separate from UI selection. Every cleanup request must receive fresh engine validation and exact-path user confirmation. No automatic selection, permanent deletion, administrator access, telemetry, arbitrary cleanup-root configuration, or model/skill/project cleanup.

Do not submit private scan JSON, personal paths, installed inventory, screenshots of a real scan, credentials, signing material, or local audit reports. Use synthetic `/Users/demo` paths and `--demo` screenshots. Test logs must be inspected before sharing. Do not weaken policy to make a screenshot look more impressive.

Before submitting, run `swift test`, the universal packaging script, `git diff --check`, and inspect the diff for private data. Describe validation and known platform gaps in the PR. UI changes should include a demo-mode screenshot with the visible Demo notice.

A release is a manual maintainer action. Inspect artifact contents and executable strings, confirm `lipo` includes arm64 and x86_64, verify `codesign --verify --deep --strict`, and verify the ZIP checksum. A release without Developer ID signing and completed notarization must explicitly say so and remain a preview. Never instruct users to disable Gatekeeper. Version changes must update Info.plist, the build script, and documentation together.

Contributions are licensed under the project’s MIT license.
