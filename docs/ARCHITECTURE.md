# AIPF Public Bootstrap — architecture and DNS / Cloudflare integration

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


Status: **development / not deployed / no signed stable installer**. Canonical AIPF specification: `vmvINT/AIPF` Issue #2. Public repo `vmvINT/aipf-bootstrap` is only a distribution facade, never a place for private project code, private manifests, passwords, tokens, or corporate data.

## Distribution flow

```text
PowerShell on clean Windows
  -> https://get.ai-store-tools.uk/  (dedicated Cloudflare Custom Domain)
  -> Cloudflare Worker: aipf-bootstrap
  -> pinned GitHub public boot.ps1 (immutable commit)
  -> verified Stage 0 prerequisite installer
  -> locally installed AIPF launcher
  -> GitHub browser/device authentication with scoped permissions
  -> private project identity/manifest (local only)
  -> source SHA-verified SRE_Twin LAB Bootstrap F
  -> offline QA / local receipt
```

Boundaries: TLS to Cloudflare and Cloudflare-to-GitHub; public Worker sees only public bootstrap source and requests, not private repo credentials; local Windows host holds GitHub CLI auth, profile and private working tree. A fixed git commit identifies source content but is **not** proof of an authorized/signed release. Current Worker uses HTTP status and textual sentinels, not cryptographic upstream verification; this must be fixed before production. `irm | iex` is convenient but executes remote code, unsuitable where execution policy or enterprise controls forbid it.

## DNS and Cloudflare

- DNS zone: `ai-store-tools.uk`, owner-controlled through Cloudflare. Do **not** touch apex, `www`, `sync2.link` or existing `nomad-router` Worker.
- Intended hostname: `get.ai-store-tools.uk` (not active until deployed).
- One dedicated Cloudflare Worker named `aipf-bootstrap`; script: `cloudflare/worker.js`; Wrangler config: `cloudflare/wrangler.jsonc`. No Cloudflare credentials in Git.
- Cloudflare UI: Workers & Pages / Compute -> GitHub -> select **only** `vmvINT/aipf-bootstrap`. Separate repo access is approved in GitHub App; no need to grant AIPF/SRE_Twin access to Cloudflare.
- Select code branch `feature/stage0-preflight-20261117` for **test** build; do not auto-deploy unreviewed `main`. Production branch in Cloudflare defaults to repository default and must be explicitly checked under Settings -> Build -> Branch control.
- Configure root directory `cloudflare`, deployment command `npx wrangler deploy` if dashboard supports explicit root. The Worker name and Wrangler `name` must match. No build step required for plain JS. Pin the Wrangler version for reproducible release before production.
- Test using `*.workers.dev` / preview first. Only after QA attach Worker -> Settings -> Domains & Routes -> Add -> Custom Domain `get.ai-store-tools.uk`; Cloudflare then provisions the DNS record and TLS certificate automatically. Do not create a manual DNS CNAME for a Custom Domain.
- Health: `GET /health` returns `aipf-bootstrap-endpoint:ok`; `GET /` serves PowerShell source; unknown routes 404; methods other than GET/HEAD 405. Health being OK does **not** mean installer end-to-end is ready.
- Separate roll-forward (new vetted immutable commit in Worker source) from rollback (restore previously reviewed Worker release). No silent `latest` branch links, secrets in logs or automatic production changes.

## Operations / test checklist

1. Inspect GitHub App permission scope — only public bootstrap repo. Keep deployment credentials in Cloudflare.
2. Git build branch, root directory and deployment command point to the reviewed source, never the public repo root if Wrangler lives in subdirectory.
3. Preview URL responds with expected health text, PowerShell Content-Type, and pinned commit header.
4. Confirm Cloudflare Custom Domain and automatic TLS only once worker and script pass QA. Test from clean Windows 10 LTSC and Windows 11.
5. Log build SHA / Worker version / response status, not access tokens or private repo identifiers. Document incident rollback and ownership of domain renewal.
6. For release gate: pinned package manager dependencies, cryptographic manifest/attestation, failure injection, Windows PowerShell parser/runtime QA, least-privilege controls, independent PR review, release approval.

## Canonical ownership

AIPF #2 owns bootstrap contract and lifecycle; this public repository owns published transport assets; SRE_Twin owns private Bootstrap F. GitHub is the source of truth. Changes to public installer require review + approved release promotion. Cloudflare serves only independently vetted versions; it is not the authoritative source of project code.

Current state: Cloudflare GitHub App selected for `vmvINT/aipf-bootstrap`; Worker project connection and deployment not yet verified. Do not mark DNS/HTTPS active based on UI screenshots alone.

## Dual-domain AIPF bootstrap delivery (owner decision 2026-11-17)

One Cloudflare Worker named `aipf-bootstrap` must serve **two separate Custom Domains** mapped to the same deployment:
- `get.ai-store-tools.uk`
- `get.sync2.link`

Both zones are Cloudflare managed. Add each hostname using Worker → Settings → Domains & Routes → Add → Custom Domain; avoid manual DNS CNAME when Custom Domain automates DNS/TLS. **Do not bind the zone apex** `ai-store-tools.uk` or `sync2.link`, or affect their existing sites/other Workers, including `nomad-router`. Each Custom Domain needs its own DNS/TLS provisioning and independent health/script response check. Same Worker code and pinned release for both domains; upgrading or rolling back this Worker affects both hostnames. Domain failover is not independent when the Worker or upstream GitHub fails.

Desired smoke checks per host: `GET /health` returns `aipf-bootstrap-endpoint:ok`, `GET /` returns plain PowerShell code with matching pinned commit header. The custom domains are **NOT ACTIVE** merely because documented or attached in Cloudflare; verify activation and certificates before advertising an install command. Both one-liners are LAB candidates until Windows and supply-chain QA is complete.

## Cloudflare build failure / repair (2026-11-17)

Observed connected Workers build: cloning/installing PASS; deploying FAILED with `Could not detect a directory containing static files`. Root cause is deploy configuration targeting static assets instead of a Worker entrypoint. The required repo-root config is `/wrangler.jsonc` and points `main` to `./cloudflare/worker.js`. Keep Cloudflare **Root directory empty / repository root** and use **Deploy command: `npx wrangler deploy`**. Build command can be empty; no static assets, Pages, or `--assets` deployment is needed. Ensure Git production branch is deliberately set to `feature/stage0-preflight-20261117` for test only (rather than `main`, which remains notice-only). Do not attach the custom domains until a test Worker deploy succeeds. After correcting settings, trigger a new build on a commit containing the root Wrangler config; retrying an old commit cannot magically add a missing config. Cloudflare docs: https://developers.cloudflare.com/workers/ci-cd/builds/configuration/ ; https://developers.cloudflare.com/workers/ci-cd/builds/troubleshoot/

Note: support for both Windows and Linux is **not identical today**. Same Worker can route `/` and `/linux` by path once Linux distribution endpoint is implemented. The current Worker responds with Windows PowerShell at `/`, while Linux Stage 0/1 exists separately but end-to-end Linux private project boot is not ready. Do not tell users `/linux` is already functional.
