import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { readFile } from 'node:fs/promises';

// Uses node built-in test runner: node --test tests/worker.test.mjs
globalThis.crypto ??= webcrypto;
const fixture = '# AIPF_BOOTSTRAP_SUCCESS\n# SOURCE_INTEGRITY_MISMATCH\n';
const marker = 'ec6ad8c1b7bdfc0d5b60d1e7dd8da367784806ad5134880cd43f4edfb4029250';
const digest = createHash('sha256').update(fixture).digest('hex');
const source = await readFile(new URL('../cloudflare/worker.js', import.meta.url), 'utf8');
assert.ok(source.includes(marker), 'expected pinned upstream digest');
const altered = source.replace(marker, digest);
const worker = (await import('data:text/javascript;base64,' + Buffer.from(altered).toString('base64'))).default;
const req = (path='/', method='GET') => new Request('https://get.ai-store-tools.uk'+path, {method});
const run = async (path='/', method='GET') => worker.fetch(req(path,method));

test('health deterministic', async () => {
  const r=await run('/health');
  assert.equal(r.status,200);
  assert.equal(await r.text(),'aipf-bootstrap-endpoint:ok\n');
  assert.equal(r.headers.get('cache-control'),'no-store');
});
test('unknown route fails closed',async()=>assert.equal((await run('/linux')).status,404));
test('unexpected method rejected',async()=>assert.equal((await run('/','POST')).status,405));
test('upstream exception returns 503',async()=>{
  globalThis.fetch=async()=>{throw new Error('offline')};
  const r=await run();assert.equal(r.status,503);assert.match(await r.text(),/UPSTREAM_UNAVAILABLE/);
});
test('upstream non-200 returns 503',async()=>{
  globalThis.fetch=async()=>new Response('redirect',{status:302});
  assert.equal((await run()).status,503);
});
test('unsuitable HTML returns 503',async()=>{
  globalThis.fetch=async()=>new Response('<html>bad</html>');
  assert.equal((await run()).status,503);
});
test('matching exact pinned hash returns expected script and headers',async()=>{
  globalThis.fetch=async()=>new Response(fixture);
  const r=await run();assert.equal(r.status,200);assert.equal(await r.text(),fixture);
  assert.equal(r.headers.get('x-aipf-source-commit').length,40);
});
test('HEAD body omitted',async()=>{
  globalThis.fetch=async()=>new Response(fixture);
  const r=await run('/boot.ps1','HEAD');assert.equal(r.status,200);assert.equal(await r.text(),'');
});
test('spoofed markers fail cryptographic check',async()=>{
  globalThis.fetch=async()=>new Response("Write-Output 'malicious'; # AIPF_BOOTSTRAP_SUCCESS SOURCE_INTEGRITY_MISMATCH");
  const r=await run();assert.equal(r.status,503);assert.match(await r.text(),/integrity mismatch/);
});
test('single-byte change fails check',async()=>{
  globalThis.fetch=async()=>new Response(fixture+' ');
  assert.equal((await run()).status,503);
});
test('empty and oversized payload rejected',async()=>{
  globalThis.fetch=async()=>new Response('');assert.equal((await run()).status,503);
  globalThis.fetch=async()=>new Response('x'.repeat(65537));assert.equal((await run()).status,503);
});
