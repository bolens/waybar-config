# Implementation plan

Use locked devenv/nixpkgs for Bash, Python, Node, Corepack-managed pnpm from the
repository manifest, GNU utilities, and native validators. Declare Bash for Make
recipes that already require it. Supply traditional Linux tool paths inside the
development image for existing minimal-PATH fixture tests.

Expose the full Linux `make check` gate and an explicit macOS source-check subset.
Keep existing generator/secrets sharding and filters. Add filtered environment CI
with real Docker validation, native macOS checks, and an always-reporting result.
Verify local native/Podman behavior, then protected PR/main CI and branch cleanup.
No live configuration delivery or version tag is implied.
