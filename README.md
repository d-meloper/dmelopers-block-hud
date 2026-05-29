![DMeloper's Block HUD screenshot](assets/hero-screenshot.png)

# DMeloper's Block HUD

English | [한국어](README.ko-KR.md)

<p align="center">
  <a href="https://github.com/d-meloper/dmelopers-block-hud/releases/latest"><img alt="Latest release" src="https://img.shields.io/badge/release-v1.2.1-9FE870?style=for-the-badge&labelColor=2F334D"></a>
  <a href="https://github.com/d-meloper/dmelopers-block-hud/releases"><img alt="Total downloads" src="https://img.shields.io/badge/downloads-429-FFB07C?style=for-the-badge&labelColor=4A4F63"></a>
  <a href="https://github.com/d-meloper/dmelopers-block-hud/stargazers"><img alt="GitHub stars" src="https://img.shields.io/badge/stars-20-C6C4FF?style=for-the-badge&labelColor=2F334D"></a>
  <a href="https://github.com/d-meloper/dmelopers-block-hud/blob/main/LICENSE"><img alt="MIT License" src="https://img.shields.io/badge/license-MIT-AED8FF?style=for-the-badge&labelColor=4A4F63"></a>
</p>

DMeloper's Block HUD is an unofficial Windows Rainmeter skin inspired by Minecraft-style inventory and hotbar interfaces.

It is designed for users who want a block-based HUD desktop setup. The skin includes a hotbar, inventory panel, system indicators, clock, settings window, and a built-in editor for custom slots and images.

If you are new to Rainmeter or skin installation, the Skin Notion page provides more detailed setup and usage instructions.

[Skin Notion page](https://www.notion.so/aismash/DMeloper-s-Block-HUD-Global-35c2dc0bb4ae801abf7dd76acee80689?source=copy_link)

## Download

Download the latest version from the GitHub Releases page.

https://github.com/d-meloper/dmelopers-block-hud/releases/latest

Check the release notes before downloading. They list which variant assets are available and include SHA256 checksums for published assets. A Korea or Global variant can be temporarily unavailable; if that happens, the release notes will mark it unavailable instead of listing a checksum for it.

Use an `.rmskin` file when installing directly from GitHub. The `.zip` files are packages for the in-skin version manager and updater, and are not recommended for normal manual installation.

Korean users should download `DMelopers-Block-HUD_Korea.rmskin`. English and global users should use `DMelopers-Block-HUD_Global.rmskin`.

| Package | Recommended for | File |
| --- | --- | --- |
| Korea RMSKIN | Korean users, direct installation | `DMelopers-Block-HUD_Korea.rmskin` |
| Global RMSKIN | English/global users, direct installation | `DMelopers-Block-HUD_Global.rmskin` |
| Korea ZIP | Korea version manager/updater only | `DMelopers-Block-HUD_Korea.zip` |
| Global ZIP | Global version manager/updater only | `DMelopers-Block-HUD_Global.zip` |

Both Korea and Global install to the same Rainmeter skin folder.

```text
DMeloper's Block HUD
```

The two variants are not designed to coexist side by side. Installing one variant over the other can overwrite the existing skin folder.

## Requirements

- Windows 7 or later
- Rainmeter installed from https://www.rainmeter.net/
- Recommended environment: Windows 11, 1920x1080 display resolution, 100% display scaling
- Rainmeter hardware acceleration is recommended for smoother rendering

This skin does not support macOS, Linux, or Windows versions earlier than Windows 7.

## Installation

1. Install Rainmeter.
2. Download `DMelopers-Block-HUD_Korea.rmskin` or `DMelopers-Block-HUD_Global.rmskin` from GitHub Releases.
3. Run the downloaded `.rmskin` file.
4. Keep the skin and layout installation options enabled, then select `Install`.
5. The default HUD layout should load automatically after installation.

The ZIP packages are not intended as the normal manual installation path from GitHub. Use an `.rmskin` file when installing or reinstalling the skin manually.

## Update

Use the included `Skin manager` whenever possible.

To update from within the skin, open the inventory from the hotbar, select the gear button to open the settings window, then use `Skin manager` at the bottom of the settings window.

The updater checks the latest version by using the GitHub Release tag and applies the ZIP package that matches the installed variant.

If you are reinstalling or updating manually from GitHub, use an `.rmskin` file. The `.zip` files are reserved for the built-in update path.

If the updater or release page says your variant is temporarily unavailable, wait for that variant to be restored or choose the other variant only if you are comfortable overwriting the same `DMeloper's Block HUD` skin folder.

## Main Features

- Minecraft-style hotbar and inventory layout
- Clickable item slots for programs, folders, files, and web links
- Built-in skin editor for item names, launch targets, images, counts, and image alignment
- Indicators for CPU, RAM, GPU, VRAM, and other system values
- Clock skin with configurable text size, color, and 12/24-hour display
- Settings window with undo, redo, refresh, reset, positioning, theme, font, and startup options
- Manual drag and snap placement options for HUD elements
- Import support for older skin data
- Korea and Global public package variants

## Basic Usage

For setup, customization, and daily usage instructions, see the Skin Notion page.

[Skin Notion page](https://www.notion.so/aismash/DMeloper-s-Block-HUD-Global-35c2dc0bb4ae801abf7dd76acee80689?source=copy_link)

## Custom Images

The included item images are modified for this skin and are not distributed as original Minecraft assets.

If you want item images closer to the original Minecraft look, obtain images from a source you are allowed to use, then apply them through the built-in editor with `Load image`.

## Troubleshooting

Check these items first.

- Refresh Rainmeter.
- Reopen the settings window.
- Check whether `Hide element` or an inventory button hide option is enabled.
- Turn on `Allow drag` and reposition the affected skin.
- Use `Reset skin position only` when one element is misplaced.
- Use `Reset all skin positions` only when the full layout is out of place.
- Open the log folder from the settings or debug area when import, update, or helper actions fail.

Recovery, skin removal, and Rainmeter removal instructions are available on the Skin Notion page.

[Recovery and removal guide](https://www.notion.so/aismash/DMeloper-s-Block-HUD-Global-35c2dc0bb4ae801abf7dd76acee80689?source=copy_link#35c2dc0bb4ae81ad99c3f9a703e748b4)

## Contact / Bug Reports / Contributions

First, please check whether the issue you want to report is already covered in the FAQ.

[FAQ](https://www.notion.so/FAQ-35c2dc0bb4ae813cab5fd531064cfc97?pvs=21)

You can also check whether the issue is already listed under known bugs.

[Known Issues](https://www.notion.so/Known-Issues-35c2dc0bb4ae81e48d6eeccdf86e08cc?pvs=21)

For questions, bug reports, suggestions, or ideas, please use the survey form below.

[DMeloper's Block HUD Support Form](https://www.notion.so/35d2dc0bb4ae81248fd3f54ba15cceaf?pvs=21)

For GitHub contribution proposals, read the contributing guide before opening a pull request.

[Contributing guide](CONTRIBUTING.md)

This public repository is a distribution surface, not the implementation source of truth. Community pull requests are reviewed as proposals, and accepted changes may be applied by the maintainer through the private development workspace before they appear in a release approval pull request.

When reporting a bug, include as much of the following information as possible.

- Skin version
- Package used: Korea or Global
- Installation method: `.rmskin`, `.zip`, or updater
- Windows version
- Rainmeter version
- Steps to reproduce
- Expected result and actual result
- Screenshots or screen recording for visual issues
- Relevant logs

## Support

- Bugs and feature requests: use GitHub Issues.
- Code, documentation, or localization proposals: read `CONTRIBUTING.md` before opening a pull request.
- Security reports: follow `SECURITY.md`; do not open public security issues.
- Installation and usage help: see `SUPPORT.md` first.

## Credits

- Skin creator: [DMeloper](https://litt.ly/dmeloper)
- Rainmeter: https://github.com/rainmeter/rainmeter, https://www.rainmeter.net/
- Mouse plugin: [Mouse.dll](https://github.com/NighthawkSLO/Mouse.dll), [@NighthawkSLO](https://github.com/NighthawkSLO), [@TheAzack9](https://github.com/TheAzack9)
- Galmuri font: https://quiple.dev/galmuri, Lee Minseo

## License And Rights Notice

Original project code and original resources created by the author are distributed under the MIT License. See `LICENSE` for details.

Third-party credits and notices are listed in `THIRD_PARTY_NOTICES.md`.

This skin is not affiliated with, endorsed by, or sponsored by Mojang Studios or Microsoft. Minecraft and related trademarks, names, and copyrights belong to their respective owners.
