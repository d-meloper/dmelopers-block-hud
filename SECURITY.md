# Security Policy

English | [한국어](SECURITY.ko-KR.md)

## Supported Versions

Security fixes are provided for the latest public GitHub release only unless a later policy explicitly states otherwise.

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
