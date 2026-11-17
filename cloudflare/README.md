# Short installer URL through Cloudflare

## 2026-11-17 — self-contained Worker prior to PRIVATE visibility

**Observed production:** Cloudflare Dashboard owner screenshot showed `aipf-bootstrap` connected to `vmvINT/aipf-bootstrap`, production branch `main`, active prior version `9d6859d3`. A later owner screenshot showed newly deployed version `942cfab8` after PR #14 merge, initially 0% traffic during rollout. More conclusive, a **real owner native Windows command** `irm https://get.sync2.link | iex` printed `AIPF_PRIVATE_CLIENT_VERIFIED=PASS`, `PRIVATE_ARTIFACT_VERIFIED=PASS`, private E2E source `520eb405...` and Stage0 PASS. It failed at **offline Python tests only**: 177 tests/1 error `test_physical_dispatch`, `TemporaryDirectory` WinError145. Thus HTTP entry/private GitHub authorization worked, but E2E install/production router **NOT ACCEPTED**. Existing SRE Issue #4 Role A P0 owns this retry, no duplicate agent.

**Owner intent:** `vmvINT/aipf-bootstrap` PUBLIC -> PRIVATE after tests. Old Worker fetches public `raw.githubusercontent.com/vmvINT/aipf-bootstrap/<sha>/boot-private.ps1`, and boot-private fetches public `windows/aipf-setup.ps1` on fresh PCs without `gh`. Both fail as soon as repository becomes PRIVATE.

**Proposed replacement (this PR; NOT YET ACTIVE):** Self-contained Worker source `cloudflare/worker.js` includes byte-exact initial public PowerShell loader `boot-private.ps1` and reviewed Stage0 script `windows/aipf-setup.ps1`. HTTP GET `/` and `/boot.ps1` serve boot, GET `/stage0` serves Stage0; `/health` stays unchanged; all served without using public GitHub Raw at runtime. The public initial loader obtains official `gh` with verified prereqs if needed, then GitHub OAuth and fetches **private** AIPF and **private** SRE source. No PAT, secrets or corporate data in public Worker. Existing historical public clones/forks remain irreversible.

**Release and privacy sequence, no long PowerShell SHA commands for owner:**
1. Review the self-contained Worker PR; require native Windows PowerShell parser, exact Git blob Stage0 hash, Node unit tests, Worker no-public-network tests and short-host /health route.
2. Authorized merge into **`vmvINT/aipf-bootstrap:main`** (the actual production branch). Cloudflare Git Build automatically deploys from `main`; **verify** new Ready deployment and 100% traffic, never assume GitHub merge = live.
3. Before executing remote PowerShell, read-only GET `https://get.sync2.link/health`, `/`, `/stage0` and compare source bytes/digests to reviewed embedded bundle; GitHub raw may be deliberately unavailable.
4. On owner Windows 10 LTSC, with existing `gh` and no risk to F04, run the single short command `irm https://get.sync2.link | iex` after agent A fixes WinError145 and new SRE pin is propagated through private bundle; verify installer/rollback and internal provider approvals. There is no safe license to claim E2E works from CI alone.
5. **Only then** change repository visibility Public -> Private via GitHub Settings -> General -> Danger Zone -> Change repository visibility. The Worker will keep serving embedded public minimal loader (its source intentionally publicly visible). Check Cloudflare GitHub App has `vmvINT/aipf-bootstrap` PRIVATE contents access; if not, adjust selected repository grant. Changing visibility may impact CI/builds, existing forks and pages.
6. Trigger a non-sensitive approved `main` deployment after visibility change and verify Cloudflare Build from PRIVATE GitHub and `get.sync2.link` one-line again. The deployed Worker usually continues serving even if new GitHub build permissions fail: restore GitHub App scope or visibility per operator runbook; **do not put tokens into Worker**.
7. Keep immutable previous Cloudflare deployment available for quick rollback, but note its *raw-public-fetch* version **will stop functioning** after privacy change. For rollback after privacy, use last good **self-contained** deployment, not the older raw-public version.

**Gates:** until POST-private build and private-source one-command owner acceptance, `VISIBILITY_CHANGE=NOT_APPROVED`. No automatic GitHub visibility mutation is performed by this PR.


Intended hostname: `get.ai-store-tools.uk`. Its DNS is controlled in Cloudflare; no existing apex or www records must be changed.

## Installation (after independent release security review)
1. Open **Cloudflare Dashboard → Workers & Pages → Create Worker**, name `aipf-bootstrap`.
2. Replace the default Worker code with the reviewed `cloudflare/worker.js` from the pinned GitHub commit and deploy. Do not paste API keys or tokens.
3. In **Worker → Domains → Add Domain → Custom Domain**, enter `get.ai-store-tools.uk`. Cloudflare provisions DNS and HTTPS automatically. Do not manually add CNAME if using Custom Domain.
4. Verify `https://get.ai-store-tools.uk/health` returns `aipf-bootstrap-endpoint:ok` and check the script response is PowerShell (not HTML); then independently validate source security before promoting any installer as stable.

**Not operational until the Worker is deployed and Custom Domain is attached.** GitHub access alone does not provide Cloudflare deployment access.

## Target UX (Windows PowerShell)
```powershell
irm https://get.ai-store-tools.uk | iex
```
The Worker returns the immutable GitHub file at commit `bf6f93d555b5bbcde6346a8c954eda95a7d5b2c2`; it has no private credentials or repository names. Do not re-point it to an unpinned branch.

## Security/release gaps
- The command pipes remote code into PowerShell. TLS + pinning reduce update risk, but it is **not** signed executable/Authenticode. Enterprise execution policy may block it.
- Worker currently checks HTTP status and sentinel strings; this **is not cryptographic content verification**. Before production, embed an independently obtained SHA-256 of the upstream script and compare with WebCrypto `crypto.subtle.digest`, or serve signed artifact and verify via trusted signature.
- Stage 0/1/2 still require clean Windows QA; private repo discovery may be ambiguous; WinGet may be blocked.
- This is a **development LAB candidate**, not a verified release.

## Both owned domains

Attach two Custom Domains to the **same** `aipf-bootstrap` Worker: `get.ai-store-tools.uk` and `get.sync2.link`. Use Cloudflare Worker settings → Domains & Routes → Add → Custom Domain separately for each. Keep both apex domains and existing services unchanged. Verify `/health`, `/` and TLS independently for each hostname. A single Worker failure affects both aliases; they are aliases, not isolated failover.
