import { test } from 'node:test';
import assert from 'node:assert/strict';
import worker, { MAX_BYTES } from './worker.mjs';

function fixture() {
  const sent = [];
  const env = {
    DIAGNOSTICS_TO: 'developer@example.test', DIAGNOSTICS_FROM: 'reports@example.test',
    REPORT_LIMIT: { limit: async () => ({ success: true }) },
    GLOBAL_LIMIT: { limit: async () => ({ success: true }) },
    EMAIL: { send: async message => { sent.push(message); return { messageId: 'private-provider-id' }; } }
  };
  return { env, sent };
}
function request(body = 'GtaV Mobile diagnostics\nCharacter entered world\n', headers = {}) {
  return new Request('https://diagnostics.example/v1/logs', {
    method: 'POST', headers: { 'content-type': 'text/plain; charset=utf-8',
      'cf-connecting-ip': '192.0.2.1', 'x-app-version': '1.3.5 (14.1)', ...headers }, body
  });
}

test('awaits email acceptance, attaches exact UTF-8 bytes, keeps recipient/provider private', async () => {
  const { env, sent } = fixture();
  let release;
  env.EMAIL.send = message => new Promise(resolve => { sent.push(message); release = resolve; });
  const req = request('GtaV Mobile diagnostics\nTürkçe: şğıİüöç\n', { 'x-note': encodeURIComponent('Çatışmada yavaş') });
  let finished = false;
  const pending = worker.fetch(req, env).then(response => { finished = true; return response; });
  while (!release) await new Promise(resolve => setTimeout(resolve, 0));
  assert.equal(finished, false);
  release({ messageId: 'private-provider-id' });
  const response = await pending;
  assert.equal(response.status, 202);
  const json = await response.json();
  assert.equal(json.accepted, true);
  assert.match(json.id, /^[0-9a-f-]{36}$/);
  assert.equal(sent[0].to, env.DIAGNOSTICS_TO);
  assert.equal(sent[0].from, env.DIAGNOSTICS_FROM);
  assert.match(sent[0].text, /Çatışmada yavaş/);
  assert.equal(new TextDecoder().decode(sent[0].attachments[0].content), 'GtaV Mobile diagnostics\nTürkçe: şğıİüöç\n');
  assert.equal(sent[0].attachments[0].filename, `gtav-${json.id}.log`);
  assert(!JSON.stringify(json).includes('@'));
  assert(!JSON.stringify(json).includes('private-provider-id'));
  assert.equal(response.headers.get('cache-control'), 'no-store');
});

test('rejects unsupported routes/methods/types, empty and non-app reports before sending', async () => {
  const { env, sent } = fixture();
  for (const [req, status] of [
    [new Request('https://diagnostics.example/'), 404],
    [new Request('https://diagnostics.example/v1/logs'), 405],
    [request('text', { 'content-type': 'application/json' }), 415],
    [request(''), 400], [request('arbitrary email'), 400]
  ]) assert.equal((await worker.fetch(req, env)).status, status);
  assert.equal(sent.length, 0);
});

test('enforces byte limit with and without a trustworthy content length', async () => {
  const { env, sent } = fixture();
  assert.equal((await worker.fetch(request('x', { 'content-length': String(MAX_BYTES + 1) }), env)).status, 413);
  const body = new ReadableStream({ start(c) { c.enqueue(new Uint8Array(MAX_BYTES)); c.enqueue(new Uint8Array(1)); c.close(); } });
  const req = new Request('https://diagnostics.example/v1/logs', { method: 'POST', headers: { 'content-type': 'text/plain' }, body, duplex: 'half' });
  assert.equal((await worker.fetch(req, env)).status, 413);
  assert.equal(sent.length, 0);
});

test('rate-limits before reading and fails closed when binding unavailable', async () => {
  const { env, sent } = fixture();
  env.REPORT_LIMIT.limit = async () => ({ success: false });
  const response = await worker.fetch(request(), env);
  assert.equal(response.status, 429);
  assert.equal(response.headers.get('retry-after'), '60');
  assert.equal(sent.length, 0);
  delete env.REPORT_LIMIT;
  assert.equal((await worker.fetch(request(), env)).status, 503);
});

test('never exposes provider errors, accepts arbitrary recipients or reports false success', async () => {
  const { env, sent } = fixture();
  env.EMAIL.send = async () => { throw new Error(`Rejected recipient ${env.DIAGNOSTICS_TO}`); };
  const response = await worker.fetch(request(), env);
  assert.equal(response.status, 503);
  const result = await response.text();
  assert(!result.includes('@'));
  assert(!result.includes('Rejected'));
  assert(!result.includes('true'));
  env.EMAIL.send = async message => { sent.push(message); return { messageId: 'accepted' }; };
  await worker.fetch(request(undefined, { to: 'attacker@example.test', 'x-note': '%0D%0ATo%3A%20attacker%40example.test' }), env);
  assert.equal(sent[0].to, env.DIAGNOSTICS_TO);
});
