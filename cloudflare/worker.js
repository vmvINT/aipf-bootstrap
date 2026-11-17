// Cloudflare Worker: immutable AIPF Windows LAB bootstrap endpoint.
// Development candidate. No credentials or private repository addresses.
// The upstream is an exact Git commit, never main/latest.
const SOURCE = "https://raw.githubusercontent.com/vmvINT/aipf-bootstrap/0674935a75b1486b05bb2fd9925db55629768981/boot.ps1";
const EXPECTED_SHA256 = "ac1cb9e6d1d3236e1d4203c21d7fd23ecbaef9ef4dc91f094de3b869456fd892";

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (request.method !== "GET" && request.method !== "HEAD") {
      return new Response("Method Not Allowed", { status: 405, headers: { Allow: "GET, HEAD" } });
    }
    if (url.pathname === "/health") {
      return new Response("aipf-bootstrap-endpoint:ok\n", {
        status: 200,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }
      });
    }
    if (url.pathname !== "/" && url.pathname !== "/boot.ps1") {
      return new Response("Not Found", { status: 404 });
    }
    // GitHub raw content must not silently redirect to a different host.
    let upstream;
    try {
      upstream = await fetch(SOURCE, { redirect: "manual", cf: { cacheTtl: 300, cacheEverything: true } });
    } catch {
      return new Response("# AIPF_BOOTSTRAP_UPSTREAM_UNAVAILABLE\nthrow 'AIPF_BOOTSTRAP_UPSTREAM_UNAVAILABLE'\n", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }
      });
    }
    if (upstream.status !== 200) {
      return new Response("# AIPF_BOOTSTRAP_UPSTREAM_STATUS\nthrow 'AIPF_BOOTSTRAP_UPSTREAM_STATUS'\n", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }
      });
    }
    const bytes = await upstream.arrayBuffer();
    if (bytes.byteLength === 0 || bytes.byteLength > 65536) {
      return new Response("Upstream source size rejected", { status: 503, headers: { "Cache-Control": "no-store" } });
    }
    const hashBytes = new Uint8Array(await crypto.subtle.digest("SHA-256", bytes));
    const digest = Array.from(hashBytes, b => b.toString(16).padStart(2, "0")).join("");
    if (digest !== EXPECTED_SHA256) {
      return new Response("Upstream integrity mismatch", { status: 503, headers: { "Cache-Control": "no-store" } });
    }
    const script = new TextDecoder("utf-8", { fatal: true }).decode(bytes);
    if (!script.includes("AIPF_BOOTSTRAP_SUCCESS") || !script.includes("SOURCE_INTEGRITY_MISMATCH")) {
      return new Response("# AIPF_BOOTSTRAP_CONTENT_INVALID\nthrow 'AIPF_BOOTSTRAP_CONTENT_INVALID'\n", {
        status: 503,
        headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" }
      });
    }
    return new Response(request.method === "HEAD" ? null : script, {
      status: 200,
      headers: {
        "Content-Type": "text/plain; charset=utf-8",
        "Cache-Control": "public, max-age=300",
        "X-Content-Type-Options": "nosniff",
        "X-Robots-Tag": "noindex",
        "X-AIPF-Source-Commit": "0674935a75b1486b05bb2fd9925db55629768981"
      }
    });
  }
};
