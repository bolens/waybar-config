# Implementation plan

Own `.woodpecker.yml`, native validation entry points, development tool declarations,
and contributor/delivery documentation. The initial adoption phase kept GitHub
workflows unchanged. This reviewed follow-up adds a default-off retirement flag
for duplicate portable Linux checks, preserving application behavior and native
macOS, actual Docker and forge automation. Reuse `devenv test`, then execute
the fleet Spec Kit validator at the same immutable revision as GitHub Actions.
Clone complete history for secret scans. Let either Linux Docker agent schedule
work under the existing resource policy; do not add writable host capabilities.

Constitution review: validation stays isolated from live state, generated sources
remain authoritative, and operational application remains separately authorized.
Use existing native hooks and validators. Root owns OAuth, secrets, settings,
required checks, integration review, and coordinated cutover. Require exact
PR/main success, protected-context
migration and an actual native weekly cron proof before enabling the flag.
A single Monday 06:17 UTC main cron combines both previous weekly full-validation
and secret-scan schedules without reducing scan cadence.
