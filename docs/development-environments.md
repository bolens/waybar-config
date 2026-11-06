# Development environments

> Doc map: [Documentation index](README.md)

Install [Nix and devenv](https://devenv.sh/getting-started/), then run from this checkout:

```sh
devenv shell
repo-check
# Or run the same portable gate non-interactively:
devenv test
```

The shell supplies Bash, Perl, Python, Node, Corepack/pnpm, GNU utilities, jq, dash, Ruff, shfmt, Gitleaks, ShellCheck, and workflow validators. `repo-check` installs the frozen pnpm development dependencies, then runs `make check` on Linux. That gate covers generators, secret fixtures, drift, configuration contracts, and source lint. The full fixture gate can take about 30 minutes; CI runs native and Docker checks in separate jobs. Markdown lint excludes local Nix/direnv tool-store state. On Linux the locked shell includes PyGObject/GTK3 for the live CSS parser probe as well as static CSS checks.

On macOS the gate runs syntax, Python/Ruff, suite inventory, docs index, systemd-template path checks, formatting, secret scanning, and CSS/Markdown lint. Linux process/desktop fixture suites are excluded explicitly. Neither platform starts Waybar or applies live settings.

Commit `devenv.lock` with deliberate input updates. Local state and `devenv.local.nix` / `devenv.local.yaml` overrides are ignored. Existing Nix cache settings are used without changing daemon trust.

## Docker and Podman

Build and load the development image, then run a command with a local engine:

```sh
python3 scripts/development-container.py build podman
python3 scripts/development-container.py run podman -- bash scripts/check-development.sh
# Substitute docker for podman to use Docker.
```

Omit the command for an interactive Bash shell. The helper mounts the checkout at `/workspace`, runs with the caller's UID/GID, and uses Podman's keep-id mapping. It forwards arguments and exit status without constructing a shell command. These mounts require a local engine with access to the checkout path; remote Docker daemons need their own source transfer. Paths containing commas are rejected because they cannot be represented by this mount syntax.

The image contains tools, not checkout files. Build archives live under `.devenv/containers/` and are never uploaded by the helper.

## Apple container

[Apple container](https://github.com/apple/container) requires a supported Apple-silicon Mac. Start its runtime according to Apple's installation guide. With a Linux Nix builder configured:

```sh
python3 scripts/development-container.py build apple
python3 scripts/development-container.py run apple -- bash scripts/check-development.sh
```

The helper exports an OCI archive and uses `container image load`. Native ARM Macs target `aarch64-linux`; x86 Linux builds target `x86_64-linux`. [Building Linux images from macOS requires a Linux builder](https://devenv.sh/containers/). This workflow does not assume Apple container implements Docker Compose or Docker's daemon API.

Apple execution is not verified by Linux tests. Development images supply `/usr/bin` tool links for existing minimal-PATH fixtures. They contain no checkout data. Generated files remain owned by the existing generators; follow [the delivery playbook](../RELEASING.md) for source delivery and separate live configuration application.

The shell uses `en_US.UTF-8` so Unicode fixtures and the committed automatic
calendar baseline have consistent character and first-weekday behavior.

## Woodpecker Linux validation

Inside its disposable Docker container, Woodpecker rejects a shallow checkout
in the locked shell, prepares minimal-PATH fixture links, and runs `devenv test`
against the committed lock, followed by
`bash scripts/check-spec-kit.sh` inside that same development shell. The latter
fetches the same immutable fleet validator revision as the retained Spec Kit
workflow. Every push to `main`, pull request, manual pipeline and configured
`main` cron runs both gates; no
changed-path filter can omit a required native result. A full-history clone
supports Git-aware secret scanning.

The pinned Nix container owns its store and configuration. Container-local Nix
sandboxing is disabled because the Docker step is the isolation boundary;
standard unprivileged `nixbld` users execute Nix builds; no host store, daemon, Docker socket, or privileged container is needed.
Nix builds use one job and two cores under the agent's 2-CPU/4-GiB step budget.
The preparation helper refuses a host/non-CI invocation and preserves existing
container tools; it adds only executable Nix-store links to the container
`/usr/bin`, matching the exported development image’s `developmentRoot` strategy.
Local development shells do not run this preparation step.
Cold execution downloads the locked tool closure and requires temporary disk
space; a warm host tool cache does not prove cold-container completion. Use a
60-minute repository pipeline timeout and verify actual runtime before cutover.

GitHub Actions remain enabled by default. The owner may set
`WOODPECKER_LINUX_CI=true` only after current PR and merged-main native success,
required-check migration and a successful actual weekly cron event. That flag
retires duplicate portable Linux validation, including the old weekly CI and
Gitleaks schedules. A single Woodpecker `main` full-validation cron at Monday
06:17 UTC preserves their weekly cadence and includes the full-history scan;
cron configuration is a server setting and is not created by this YAML.
Keep the flag absent or false until all three native event proofs pass.
Native macOS checks and actual Docker/development-container builds remain hosted until suitable runners
exist. Maintainer assignment, labels where configured, and the scheduled Spec Kit
update PR are forge automation with separate write authority. These repositories
publish no packages or releases from CI, so validation needs no publication
secrets or registry credentials. Pipeline and clone image digests are reviewed
pins; existing Dependabot Docker coverage does not monitor `.woodpecker.yml`, so
review those pins explicitly when updating CI images.

## Nix compatibility and warning checks

Use the locked devenv 2.4.0 CLI and reviewed nix2container revision with the
existing unrelated inputs preserved. Keep the git-hooks input and its legacy
alias explicit. Standard `nixbld` users prevent Go build telemetry from creating
the placeholder home in disposable Nix containers. The container helper uses
the 2.x `copy` subcommand registry option.

Accept cache configuration only on the immutable upstream CLI invocation,
never globally for repository flakes. Preserve the existing publication,
source-validation and platform cutover flags; require current native and
hosted execution before accepting the upgrade.
