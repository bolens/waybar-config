# Development environments

> Doc map: [Documentation index](README.md)

Install [Nix and devenv](https://devenv.sh/getting-started/), then run from this checkout:

```sh
devenv shell
repo-check
# Or run the same portable gate non-interactively:
devenv test
```

The shell supplies Bash, Perl, Python, Node, Corepack/pnpm, GNU utilities, jq, dash, Ruff, shfmt, Gitleaks, ShellCheck, and workflow validators. `repo-check` installs the frozen pnpm development dependencies, then runs `make check` on Linux. That gate covers generators, secret fixtures, drift, configuration contracts, and source lint. The full fixture gate can take about 30 minutes; CI runs native and Docker checks in separate jobs. Markdown lint excludes local Nix/direnv tool-store state. The optional live GTK CSS parser probe remains unavailable unless PyGObject/GTK3 is installed; static CSS checks still run.

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
