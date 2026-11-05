# Implementation plan

Own `.woodpecker.yml`, native validation entry points, development tool declarations,
and contributor/delivery documentation. Keep application behavior and existing
GitHub workflows unchanged in this first phase. Reuse `devenv test`, then execute
the fleet Spec Kit validator at the same immutable revision as GitHub Actions.
Clone complete history for secret scans. Let either Linux Docker agent schedule
work under the existing resource policy; do not add writable host capabilities.

Constitution review: validation stays isolated from live state, generated sources
remain authoritative, and operational application remains separately authorized.
Use existing native hooks and validators. Root owns OAuth, secrets, settings,
required checks, integration review, and subsequent cutover.
