# Why Block HUD Uses Helper Programs

English | [한국어](ANTIVIRUS.ko-KR.md)

> [!WARNING]
> Some antivirus products and some scanning engines on VirusTotal currently detect `BlockHudPowerShellHost.exe` or related helper scripts as malware, including virus or Trojan classifications. The project is aware of these reports and continues to review the packaged files and execution paths that can trigger them.

DMeloper's Block HUD is a Rainmeter skin, but not every feature can be implemented safely and consistently with Rainmeter's built-in features and Lua alone.

Some features therefore use the packaged `BlockHudPowerShellHost.exe` and local PowerShell helper scripts. These files are not intended to receive and execute arbitrary code from external sources. They are runtime components that execute features distributed with Block HUD.

## Why are helper programs needed?

Rainmeter is well suited to displaying interfaces, updating meters, handling clicks, and managing skin state, but it has limitations when performing Windows operations such as:

- displaying Windows file and folder selection dialogs
- selecting and converting image files
- safely copying or replacing multiple files
- downloading, validating, and extracting ZIP packages
- checking compatibility and selectively merging existing data
- restoring backups after a failure
- providing settings and management features in separate windows
- returning structured results and error details to Rainmeter

`BlockHudPowerShellHost.exe` connects Rainmeter to these Windows helper operations. Instead of repeatedly creating direct `powershell.exe` windows, it hosts Windows PowerShell internally and returns the result to Block HUD.

## How the helpers are used

### Settings and Editor

Settings and Editor may use helper programs for:

- selecting a program, file, or folder path
- selecting an image for an item
- processing and pixelating a selected icon or image
- editor operations that require a Windows file picker
- immediately applying settings to related skins and data files
- updating multiple settings files consistently
- returning failure information to Settings or Editor

File selection dialogs may require a Windows STA environment, so they cannot always be replaced reliably with a simple Rainmeter command.

### Skin manager and updates

The Skin manager and updater use helpers for operations such as:

- checking official GitHub Release information
- identifying the installed Korea or Global package
- selecting the update asset that matches the installed variant
- downloading the update package
- validating SHA256 and package structure
- safely extracting the package in a temporary directory
- backing up the existing installation
- replacing it with validated files
- rolling back to the previous state after a failure
- reloading the required Rainmeter skins after the update

Download, extraction, validation, backup, and recovery must be treated as one operation during an update. Ordinary Rainmeter click commands cannot safely guarantee this entire sequence.

### Version installation and switching

Managing multiple versions uses helpers for:

- querying the selected release
- preparing the package in an inactive installation location
- checking data compatibility with the existing version
- validating that the installation can be switched safely
- switching the active version
- keeping the existing active version when a switch fails
- reloading the required Rainmeter configurations afterward

### Importing existing data

Importing data from an earlier version requires helpers to:

- locate the previous installation
- check whether its data is compatible
- classify user images and settings data
- distinguish current-version defaults from user data
- create a backup before importing
- selectively merge only allowed data
- restore the original state after a failure
- return the result and log location to Block HUD

Simply overwriting files could damage current settings or user data, so validation and rollback are required.

### Initialization after installation

The following preparation may run immediately after an installation, update, or version switch:

- confirming that required helper files exist
- checking that the executable and scripts match the package
- preparing the per-user runtime host
- displaying initialization progress while antivirus scanning completes
- confirming that Settings, Skin manager, and other helper features can start

Initialization may be temporarily slow while Windows Security or another antivirus product inspects a new executable and PowerShell-related files for the first time.

### Jukebox

Jukebox may use helpers for Windows operations such as:

- selecting local audio files and folders
- processing paths used for playback
- returning player state and operation results
- supporting integration with external music applications
- recording playback and helper errors

### Diagnostics and logs

When a problem occurs, helpers may also be used for:

- creating relevant log files
- collecting results from multiple helper operations
- returning error status and log locations to Rainmeter
- opening the log folder from Settings or Skin manager
- diagnosing installation and update state

## Why antivirus warnings can occur

The following characteristics may overlap with behavior- or reputation-based antivirus detection rules:

- starting PowerShell automation from Rainmeter
- a newly built executable that has not yet established file reputation
- a dedicated host that runs multiple local scripts
- file copy, extraction, backup, and replacement operations
- network and file operations used for updates
- a helper program that runs without a console window
- an executable and script combination first encountered immediately after installation

These characteristics can delay initialization or cause a legitimate component to be classified as a virus, Trojan, or other malware by some antivirus products and VirusTotal scanning engines. A detection name or detection count alone cannot prove that a file is safe or malicious, so always verify both its distribution source and checksum.

## Code-signing limitation

Code signing can help identify the executable's publisher, show whether it was modified after signing, and improve file reputation. It does not guarantee that every antivirus warning will disappear.

DMeloper's Block HUD is developed, distributed, and maintained as a completely free project. The developer cannot currently sustain certificate and signing costs of approximately KRW 200,000 per year, so the release build of `BlockHudPowerShellHost.exe` is not digitally signed at this time.

The project does not hide the executable's unsigned status. Official distribution paths, SHA256 values in release notes, and distribution validation are maintained so users can verify origin and integrity. Executable signing will be reconsidered if the project's cost and operating circumstances change.

## How to verify a download safely

Download Block HUD only from the [official GitHub Releases page](https://github.com/d-meloper/dmelopers-block-hud/releases/latest).

You can verify the SHA256 of a downloaded `.rmskin` file with:

```powershell
Get-FileHash ".\DMelopers-Block-HUD_Korea.rmskin" -Algorithm SHA256
Get-FileHash ".\DMelopers-Block-HUD_Global.rmskin" -Algorithm SHA256
```

The calculated checksum must exactly match the value published in the corresponding release notes. If the checksum differs or you cannot verify the distribution source, do not run the file; download it again from the official Releases page. This guidance does not ask you to disable Windows Security or antivirus protection or add a broad exclusion for the Block HUD folder.

## Planned improvements

Future updates will continue to:

- simplify PowerShell helper execution paths
- preserve the design that does not use direct `powershell.exe` fallback
- preserve the design that does not use nested encoded-command execution
- preserve the design that does not use WMI/CIM-based process discovery
- strengthen the execution contract so only packaged local scripts are explicitly run
- maintain executable identity metadata such as product, publisher, version, and original filename
- verify that built executables match their source, version, and SHA256 records
- continue publishing package-specific SHA256 values in official release notes
- reduce unnecessary repeated execution during installation and updates
- clearly display progress while Windows Security or antivirus scanning is in progress
- further reduce execution behavior that can trigger behavior-based antivirus detection

The project will address this issue by continuing to improve helper execution and provide verifiable official packages, not by asking users to disable security features or configure broad antivirus exclusions.
