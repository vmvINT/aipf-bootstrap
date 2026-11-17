# AIPF Stage 0 + Stage 1 — development preview

This public repository contains generic, prerelease bootstrap source. No private project identifiers, access tokens or manifests belong here.

**NOT a signed or independently verified release. DO NOT pipe remote source into a shell, or run a moving Git branch directly on a trusted host.**

## Clean-host rule
On a new OS, `aipf` does not exist. Use OS native PowerShell or POSIX shell to run a separately downloaded and hash-/signature-verified immutable setup package. Stage 0 installs prerequisites, then Stage 1 installs an `aipf` launcher into the user's PATH.

## Candidate local usage, from an already reviewed copy

Windows PowerShell 5.1+:
```powershell
.\windows\aipf-setup.ps1
.\windows\aipf-setup.ps1 -Apply -Login -InstallPython
aipf version
aipf doctor
```
WinGet supplies Git / GitHub CLI / optional Python. Without WinGet the installer fails with BLOCKED rather than bypassing corporate policy. Installed launcher lives in `%LOCALAPPDATA%\AIPF\bin`; user PATH is updated. Reopen PowerShell if your current shell doesn't yet see it. No silent privilege elevation.

Linux (Debian / Ubuntu / Fedora only):
```sh
sh linux/aipf-setup.sh --plan
sh linux/aipf-setup.sh --apply --login
~/.local/bin/aipf version
~/.local/bin/aipf doctor
```
Approved system repositories (apt/dnf) supply git/curl/gh; when needed sudo requests credentials interactively, never silently. If package manager lacks gh, installer must block rather than add unreviewed third-party repositories. The script does not alter shell profile automatically: add `~/.local/bin` to PATH when needed.

## Stage 1 command contract
- `aipf version` — output launcher version
- `aipf doctor` — report local tool status, without network or secret output
- `aipf boot PROFILE`, `update PROFILE`, `rollback PROFILE` — **currently return BLOCKED_STAGE2_NOT_IMPLEMENTED**, no private download, mutation or production action. This is intentional.

## Test evidence and release gates
- Local Linux synthetic unittest 4/4 PASS on 2026-11-17: POSIX syntax, launcher command guards, plan/apply/idempotence, simple public artifact identifier scan. Tests in `tests/test_stage0.py`.
- NOT executed on native Windows; no Windows PowerShell parser/runtime pass yet.
- NOT executed as a genuine clean-machine installation (Windows 10 LTSC/11, Ubuntu, Fedora). No verified binary/signature or immutable release.
- Stage 2 private manifest, authenticated profile selection, pinned SRE_Twin Bootstrap F integration, secure update/rollback remain to be implemented before claiming `aipf boot twin` works.
- Mandatory independent source review, SHA-256/signature verification, privilege and error-path tests, clean-host tests and release approval.

Git contract: development branch only; no merge, public release or production deployment implied.

## Stage 2 Windows private project integration — development only (2026-11-17)

The Windows launcher now supports **one-time local** profile registration. The public source does not name private projects or contain credentials. For a machine already equipped with a reviewed local copy of this development branch, registration follows the pattern:

```powershell
aipf profile set twin OWNER/PRIVATE_REPOSITORY EXACT_40_CHARACTER_COMMIT_SHA
aipf doctor
aipf boot twin
```

This is a **syntax example, not an installation recommendation yet**. Register an explicitly trusted private repository. It is never auto-discovered: the user must provide the locator once, or a future trusted private provisioning channel must prepopulate it. The local profile is stored under `%LOCALAPPDATA%\AIPF\profiles\twin.json`. The repository identifier is not published by the launcher, but it is visible to the local operating-system account. A commit SHA identifies source; by itself it is not a verified author signature or proof of safety.

`aipf boot twin` uses the installed Git/GitHub CLI/Python 3.11, validates GitHub authorization, clones into a random temporary directory, detaches the exact registered commit, verifies SHA and origin, requires `scripts/bootstrap_git_lab.py` from that commit, executes its `plan`, and delegates `install --source-sha` to the existing private Bootstrap F. `update` delegates `update`; `rollback` delegates `rollback`. The private Bootstrap F owns the managed versions, offline tests, receipts and rollback rules. On failure the launcher attempts temporary checkout cleanup; it never triggers MWS/production commands itself.

**Limitations:** native Windows stage 2 is still untested on a real Windows host; Linux Stage 2 project installation remains BLOCKED because the referenced private Bootstrap F is native-Windows-only. No automatic profile registration, machine policy bypass, signed installer, independent trust roots, or dependency lock has been implemented. No user should run this branch as a trusted release.

### Remaining acceptance gates
- Correctness: Windows PowerShell 5.1 parser, fake Git/gh/Python integration tests, real Windows 10 LTSC and Windows 11 installation, no WinGet case.
- Security: strict trust allowlist and manifest provenance (beyond a user-provided pinned SHA), profile ACL/privacy checks, failure injection and cleanup, credential redaction, checksum/signature verification.
- Release: independently reviewed PR, immutable signed release, trusted download/verification instructions, owner approval for merge/public distribution.
