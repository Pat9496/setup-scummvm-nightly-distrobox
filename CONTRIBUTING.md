# Contributing

Bug reports, feature suggestions, and pull requests are welcome.

## Reporting Issues or Suggesting Features

Open an issue describing the problem or idea. For bugs, include your distro and the exact error output; this script has no automated test suite, so real-world reports are how problems actually get found.

## Pull Requests

- Keep changes focused; avoid unrelated refactoring in the same PR.
- Match the existing Bash style (`set -Eeuo pipefail`, minimal comments, English only — see `CLAUDE.md`).
- Run `bash -n setup-scummvm-nightly-distrobox.sh` before submitting. There's no automated test suite, so verifying real behavior requires an actual host with Distrobox and rootless Podman.
- Update `README.md` (and `CLAUDE.md` if it documents the changed behavior) so the docs stay accurate.

By contributing, you agree your contribution is licensed under this project's [MIT license](LICENSE).
