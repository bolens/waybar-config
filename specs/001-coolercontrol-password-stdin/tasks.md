# Tasks: CoolerControl password handoff

- [x] T001 Inspect credential sinks and document decisions in specs/001-coolercontrol-password-stdin/research.md.
- [x] T002 [US1] Require stdin credentials in scripts/ci/tests/generator/coolercontrol-module-auth.sh and scripts/ci/tests/secrets/coolercontrol-sync-auth.sh.
- [x] T003 [US1] Replace password files with pipes in scripts/services/coolercontrol/coolercontrol-api.py, coolercontrol-api-dump.sh, coolercontrol-check-auth.sh, and coolercontrol-set-ui-pass.sh.
- [x] T004 [US1] Verify isolated login, failure cleanup, generation, and repository gates; record evidence in specs/001-coolercontrol-password-stdin/quickstart.md.
