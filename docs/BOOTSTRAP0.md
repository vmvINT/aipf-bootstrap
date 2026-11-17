# Bootstrap 0 — clean-host prereq setup (development preview)

This repository contains a *public, generic* preflight and prerequisite setup for Windows and Linux. No private repository URLs, manifests, API credentials, tokens, or privileged domain details are required by these scripts.

**No release has been approved or signed; do not execute directly from a raw branch URL.** This code is a starting point for independent QA, not the promised one-command install.

## Why `aipf` cannot run on a clean OS
A clean OS does not ship an `aipf` executable. Stage 0 is run using PowerShell 5.1+ (Windows) or POSIX sh (Linux). A subsequent, not-yet-implemented Stage 1 will install the `aipf` launcher into PATH. After that, `aipf boot <profile>` can select an authenticated private manifest.

## Local review / dry run
Windows, from the folder containing the reviewed script:
```powershell
.\windows\aipf-setup.ps1
# Installs missing Git and GitHub CLI via WinGet, optionally Python 3.11, then browser auth:
.\windows\aipf-setup.ps1 -Apply -InstallPython -Login
```
This installer does *not* silently elevate. If WinGet is unavailable or blocked, it reports BLOCKED. Newly installed executables may require a reopened shell.

Linux:
```sh
sh linux/aipf-setup.sh --plan
sh linux/aipf-setup.sh --apply
```
Preflight recognizes Debian/Ubuntu and Fedora. Missing system packages require explicit root mode; GitHub CLI is not auto-installed from unreviewed third-party repositories, and absence is a controlled BLOCKED on apply.

## Security/QA/release criteria
- Prefer a signed immutable setup release with independent checksum/attestation, not `irm | iex` / `curl | sh`.
- Source review, PowerShell parser tests, shellcheck, fake-binary mocks, clean Windows 10 LTSC/11, Ubuntu/Fedora, managed/WinGet-less host tests.
- No private repository or secret in public artifacts; first project-specific manifest is fetched only after user authorization and verified by immutable SHA/hash.
- No unapproved privilege escalation, third-party signing key installation, network token output, production changes or implicit push/merge.
- Implement and independently review Stage 1 command launcher, pinning, repair, rollback, and offline doctor before claiming `aipf boot` works.
- Keep failure statuses distinct: BLOCKED when policy/environment prevents operation, FAILED on implementation/run errors.

Status: **PARTIAL IMPLEMENTATION / NOT RELEASED / NOT TESTED ON CLEAN HOST**.
