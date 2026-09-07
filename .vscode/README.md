# VS Code for waybar-config

[Documentation](../docs/README.md)

Open this repository as a folder, or add it as a folder in a multi-root workspace.
Install the recommendations from the Extensions view. Use **Tasks: Run Task** for
the commands below. Tasks run from this repository unless they state another directory.

Use the tool versions documented by the repository. Launch VS Code from the
prepared development shell, or reopen in the existing dev container when available.
Extension recommendations do not install command-line dependencies.

| Task | Command |
| --- | --- |
| make check-fast | `make check-fast` |
| make check | `make check` |
| make check-generator | `make check-generator` |
| make check-secrets | `make check-secrets` |
| make generate | `make generate` |
| Check diff whitespace | `git diff --check` |

This checkout has no application debug entry configured. Use its validation tasks
and the editor support for its source and configuration files.

CSS validation is delegated to the repository checks because Waybar uses GTK CSS.
Edit `data/waybar-settings.jsonc` and generators, then run `make generate`.
