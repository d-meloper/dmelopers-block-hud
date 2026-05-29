# Contributing

English | [한국어](CONTRIBUTING.ko-KR.md)

Contributions are welcome when they fit the project direction and can be reviewed safely.

This public repository is the distribution surface and review surface for the skin. It is not the implementation source of truth. Maintainer-owned release branches are reviewed here before they become public releases, while implementation changes are prepared in the maintainer's private development workspace first.

Community pull requests are welcome as proposal and review input. Please do not expect a community PR to be merged directly into public `main`. If a proposal is accepted, the maintainer applies it in the private development workspace, validates it there, and publishes it back here through a maintainer release approval PR or a maintainer metadata-only PR.

## Before You Start

Open an issue first for larger changes, behavior changes, packaging changes, or UI changes.

## Development Notes

- Rainmeter `.ini` and `.inc` files must remain UTF-16 LE with BOM.
- Lua runtime code should remain compatible with Lua 5.1.
- Do not commit built distribution trees, ZIP/RMSKIN release assets, generated caches, local runtime state, logs, backups, or private paths.
- Keep public-facing wording user-friendly and avoid private/internal workflow terminology; use public branch/check policy terms only where they explain pull request behavior.
- Korea and Global packages install to the same skin folder: `DMeloper's Block HUD`.

## Pull Requests

Please include:

- What changed.
- Why it changed.
- How it was tested.
- Screenshots or recordings for visual changes.
- Any packaging or update implications.

Community pull requests are treated as proposals. If a change is accepted, the maintainer will apply it through the private development workspace and publish it back here through a release approval pull request or metadata-only pull request, depending on the change.

Do not create `publish/v<version>` branches unless you are the maintainer preparing an official release approval PR. Do not create `publish/metadata-<topic>` branches unless you are the maintainer preparing an approved public metadata-only PR. These branch patterns and the `public-export-approval` check are maintainer publication tools, not requirements for normal community PRs.

A community PR may show a failing `public-export-approval` check because non-release branches are intentionally guarded. That failure does not block discussion or review of the proposal.

Release approval pull requests are maintainer-only. They use `publish/v<version>` branches, must pass the `public-export-approval` check, and are merged manually before the GitHub Release tag and assets are finalized.

Metadata-only pull requests are also maintainer-only. They use `publish/metadata-<topic>` branches, may change only approved public metadata paths, and do not create or update GitHub Release tags or assets.

## Public Release Policy

GitHub Releases carry the public version tag and release notes. ZIP and RMSKIN asset filenames are variant-only and do not include the version.
