# Waybar development environments

Provide pinned tools for the existing generator, fixture suites, source checks,
and generated-drift gate. Linux uses the full native Make gate; macOS provides
source validation without claiming Linux desktop or process integration support.
Images contain tooling only and mount source explicitly with caller ownership.

Keep settings and secrets separate. Validation must not restart Waybar, modify
live configuration, emit desktop signals, or use live services as fixtures.
Preserve the existing test harness and generated-source ownership. Apple container
requires supported Mac hardware and a Linux builder; record unavailable execution.
