# Short installer URL through Cloudflare

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
