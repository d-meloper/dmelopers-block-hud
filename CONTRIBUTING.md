# Contributing

English | [한국어](CONTRIBUTING.ko-KR.md)

Contributions are welcome when they fit the project direction and can be reviewed safely.

This public repository is the distribution surface for the skin. Maintainer-owned release branches are reviewed here before they become public releases, while implementation changes are prepared in the maintainer's private development workspace first.

## Before You Start

Open an issue first for larger changes, behavior changes, packaging changes, or UI changes.

## Development Notes

- Rainmeter `.ini` and `.inc` files must remain UTF-16 LE with BOM.
- Lua runtime code should remain compatible with Lua 5.1.
- Do not commit local runtime state, logs, backups, generated caches, or private paths.
- Keep public-facing wording user-friendly and avoid internal workflow terminology.
- Korea and Global packages install to the same skin folder: `DMeloper's Block HUD`.

## Pull Requests

Please include:

- What changed.
- Why it changed.
- How it was tested.
- Screenshots or recordings for visual changes.
- Any packaging or update implications.

Community pull requests are treated as proposals. If a change is accepted, the maintainer will apply it through the private development workspace and publish it back here through a release approval pull request.

Release approval pull requests use `publish/v<version>` branches, must pass the `public-export-approval` check, and are merged manually before the GitHub Release tag and assets are finalized.

## Public Release Policy

GitHub Releases carry the public version tag and release notes. ZIP and RMSKIN asset filenames are variant-only and do not include the version.
