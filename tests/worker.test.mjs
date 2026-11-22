import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile } from 'node:fs/promises';

// Verify the exact public trust-anchor script is frozen into the Worker:
// there must be NO anonymous GitHub Raw dependency at request time.
const readText = async (url) => (await readFile(url, 'utf8')).replace(/\r\n/g, '\n');
const source = await readText(new URL('../cloudflare/worker.js', import.meta.url));
const boot = await readText(new URL('../boot-private.ps1', import.meta.url));
const stage0 = await readText(new URL('../cloudflare/stage0-reviewed.ps1', import.meta.url));
const worker = (await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'))).default;

const gitBlob = (content) => {
  const body = Buffer.from(content, 'utf8');
  return createHash('sha1').update('blob ' + body.length + '\0').update(body).digest('hex');
};
const req = (path = '/', method = 'GET') => new Request('https://get.sync2.link' + path, {method});
const run = async (path = '/', method = 'GET') => worker.fetch(req(path, method));

test('pinned Stage0 remains identical to verified historical Git raw blob', () => {
  assert.equal(gitBlob(stage0), '7f6b45b45a9c646d5455be3474a6bfeee4bfde68');
  assert.match(boot, /\$stage0Blob\s*=\s*'7f6b45b45a9c646d5455be3474a6bfeee4bfde68'/);
});
test('initial code is embedded and calls no GitHub Raw endpoint', async () => {
  let calls = 0;
  globalThis.fetch = async () => { calls++; throw Error('Public GitHub raw deliberately unavailable'); };
  const result = await run('/');
  assert.equal(result.status, 200);
  assert.equal(await result.text(), boot);
  assert.equal(calls, 0);
  assert.equal(result.headers.get('x-aipf-delivery'), 'embedded-private-github-auth');
});
test('fresh PC Stage0 is embedded and calls no anonymous GitHub Raw endpoint', async () => {
  const result = await run('/stage0');
  assert.equal(result.status, 200);
  assert.equal(await result.text(), stage0);
  assert.equal(result.headers.get('x-aipf-stage0-blob'), gitBlob(stage0));
});
test('fresh PC installer asks Worker, not public GitHub, for Stage0', () => {
  assert.ok(boot.includes("https://get.sync2.link/stage0"));
  assert.ok(boot.includes('& $destination -Apply -Login -InstallPython -SkipLauncher'));
  assert.equal(boot.includes('raw.githubusercontent.com/vmvINT/aipf-bootstrap'), false);
});
test('health is deterministic and HEAD has no body', async () => {
  const health = await run('/health');
  assert.equal(health.status, 200);
  assert.equal(await health.text(), 'aipf-bootstrap-endpoint:ok\n');
  const head = await run('/boot.ps1', 'HEAD');
  assert.equal(head.status, 200);
  assert.equal(await head.text(), '');
  const stageHead = await run('/stage0', 'HEAD');
  assert.equal(stageHead.status, 200);
  assert.equal(await stageHead.text(), '');
});
test('path and methods fail closed', async () => {
  assert.equal((await run('/linux')).status, 404);
  assert.equal((await run('/secrets')).status, 404);
  assert.equal((await run('/', 'POST')).status, 405);
});
test('no runtime remote pull or secret material in Worker', () => {
  assert.equal(source.includes('fetch(SOURCE'), false);
  assert.equal(source.includes('raw.githubusercontent.com'), false);
  assert.equal(source.includes('gho_'), false);
  assert.match(source, /EMBEDDED_BOOT/);
  assert.match(source, /EMBEDDED_STAGE0/);
});

test('public loader reads authenticated private stable manifest, no SHA copied by user', () => {
  assert.ok(boot.includes("$releasePath = 'releases/twin-stable.json'"));
  assert.ok(boot.includes("$releaseRef = 'master'"));
  assert.ok(boot.includes("STABLE_MANIFEST_GIT_BLOB_INVALID"));
  assert.ok(boot.includes("STABLE_MANIFEST_POLICY_MISMATCH"));
  assert.ok(boot.includes("AIPF_RELEASE_CHANNEL=stable"));
  assert.ok(boot.indexOf("if (-not (CheckGh))") < boot.indexOf("$releaseFile=SafeGhJson"));
  assert.equal(boot.includes("$sourceSha = 'cf2622103add7c368ccd12954723c8159237bc78'"), false);
});
