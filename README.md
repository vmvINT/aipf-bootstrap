# AIPF Stable Bootstrap — one command

For an authorized Windows laptop, the intended installation and update command is always:

```powershell
irm https://get.sync2.link | iex
```

The public Cloudflare Worker serves a small **static** reviewed PowerShell loader.
After GitHub browser authentication, the loader reads the current **private**
`vmvINT/AIPF:master/releases/twin-stable.json` release pointer. That pointer
selects an exact immutable AIPF Bootstrap commit and SHA-256. The private
installer verifies the file and then installs/updates the SRE_Twin version
pinned by that AIPF release. The launcher preserves the last active version
for rollback. Users never copy hashes or choose candidate branches.

**For release owners:** promote a reviewed SRE_Twin build by updating the
private release manifest to the validated AIPF bootstrap candidate.
No Cloudflare redeployment is needed for ordinary SRE_Twin releases.
The initial one-time Worker migration must pass CI and the live-domain
byte-for-byte check. Do not treat a GitHub merge as proof of Cloudflare
deployment until that check passes.

The Worker publicly exposes only the bootstrap trust anchor and Stage0
prerequisites. Neither the private release manifest nor corporate secrets,
cases or source code are provided anonymously. GitHub access remains required.
This is a LAB tool; real provider availability and RCA quality need a
network-connected owner run after each substantial model integration change.
