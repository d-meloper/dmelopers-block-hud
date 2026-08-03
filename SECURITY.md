# Security Policy

English | [한국어](SECURITY.ko-KR.md)

## Supported Versions

Security fixes are provided for the latest public GitHub release only unless a later policy explicitly states otherwise.

## Release And Updater Integrity

Release notes publish an exact `SHA256 <hash> <asset>` entry for each distributed ZIP and RMSKIN asset. The public updater feed publishes a Korea or Global updater ZIP hash only when that exact release-note entry and the GitHub release asset's `sha256:` digest both exist and agree.

Beginning with the first release that contains checksum-verifying updater support, network-driven updates and current-version resets fail closed:

- Repository, variant, exact asset name, and SHA-256 must come from the same verified metadata.
- The downloaded ZIP is checked after staging and again immediately before extraction.
- Missing, malformed, stale, or mismatched metadata or package bytes stop the operation before extraction, compatibility processing, or user-state changes.

Version 1.4.0 and earlier do not retroactively gain this runtime verification. Existing local package and import workflows remain compatibility paths and do not require a published checksum unless they are invoked through a network or latest-update handoff.

For a manual download, run `Get-FileHash <file> -Algorithm SHA256` in PowerShell and compare the result with the release-note entry for the exact filename. If the updater reports a checksum mismatch, do not bypass it; retain the version, variant, asset name, expected hash, and actual hash, then report the issue privately.

SHA-256 detects corruption, an incorrect or replaced asset, and publication metadata drift. It does not determine whether software is malware, prove publisher identity, or protect against an attacker who can replace both an artifact and all trusted checksum metadata. Block HUD does not currently claim code-signing or TUF-style signed metadata protection.

## Reporting A Vulnerability

Do not report security issues in public GitHub Issues.

Use GitHub private vulnerability reporting if it is available on this repository. If it is not available, contact the maintainer through the public profile/support route and request a private reporting channel.

## What Counts As A Security Issue

Please report issues involving:

- Unsafe updater behavior.
- Unsafe ZIP or RMSKIN extraction behavior.
- Unexpected command execution.
- Unsafe PowerShell helper behavior.
- Path traversal.
- Exposure of private local paths or sensitive local data.
- Plugin binary trust concerns.
- Download or update flows that can be redirected unexpectedly.

## What Usually Does Not Count

Please use normal GitHub Issues for:

- Visual layout bugs.
- Settings behavior bugs.
- Rainmeter configuration mistakes.
- Problems caused by unsupported manual file edits.
- Feature requests.

## Response Expectations

The maintainer will review valid security reports as time allows. Public disclosure should wait until a fix or mitigation is available.
