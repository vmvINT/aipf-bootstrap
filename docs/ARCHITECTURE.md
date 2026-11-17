# AIPF Public Bootstrap — architecture and DNS / Cloudflare integration

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
