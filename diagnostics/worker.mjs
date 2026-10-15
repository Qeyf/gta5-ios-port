// Recipient and sender are Cloudflare secrets, never supplied by the app.
export const MAX_BYTES = 13 * 1024 * 1024;

function reply(status, body, extra = {}) {
  return Response.json(body, { status, headers: {
    'cache-control': 'no-store', 'x-content-type-options': 'nosniff', ...extra
  } });
}

async function boundedBody(request) {
  const declared = request.headers.get('content-length');
  if (declared !== null && (!/^\d+$/.test(declared) || Number(declared) > MAX_BYTES)) return null;
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    for (;;) {
      const { done, value } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BYTES) { await reader.cancel(); return null; }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  const bytes = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  return bytes;
}

function metadata(request, name, limit) {
  let value = request.headers.get(name) || '';
  try { value = decodeURIComponent(value); } catch { value = ''; }
  return value.replace(/[\x00-\x1f\x7f]/g, ' ').slice(0, limit);
}

export default {
  async fetch(request, env) {
    if (new URL(request.url).pathname !== '/v1/logs') return reply(404, { error: 'not_found' });
    if (request.method !== 'POST') return reply(405, { error: 'method' }, { allow: 'POST' });
    if (!/^text\/plain(?:\s*;|$)/i.test(request.headers.get('content-type') || '')) return reply(415, { error: 'content_type' });
    try {
      if (!env.EMAIL || !env.REPORT_LIMIT || !env.GLOBAL_LIMIT || !env.DIAGNOSTICS_TO || !env.DIAGNOSTICS_FROM) {
        return reply(503, { error: 'unavailable' });
      }
      // Cloudflare supplies this header. No IP address is stored or emailed.
      const actor = request.headers.get('cf-connecting-ip') || 'unknown';
      if (!(await env.REPORT_LIMIT.limit({ key: actor })).success ||
          !(await env.GLOBAL_LIMIT.limit({ key: 'all-reports' })).success) {
        return reply(429, { error: 'rate_limit' }, { 'retry-after': '60' });
      }
      const bytes = await boundedBody(request);
      if (bytes === null) return reply(413, { error: 'too_large' });
      if (!bytes.byteLength || !new TextDecoder().decode(bytes.subarray(0, 128)).startsWith('GtaV Mobile diagnostics\n')) {
        return reply(400, { error: 'invalid_report' });
      }
      const id = crypto.randomUUID();
      const version = metadata(request, 'x-app-version', 80);
      const device = metadata(request, 'x-device', 240);
      const note = metadata(request, 'x-note', 400);
      // Await the provider before acknowledging. Do not log payloads, addresses,
      // IPs or exception strings (provider errors can contain the recipient).
      await env.EMAIL.send({
        from: env.DIAGNOSTICS_FROM, to: env.DIAGNOSTICS_TO,
        subject: `GtaV Mobile diagnostic report ${id}`,
        text: `Report: ${id}\nApp: ${version}\nDevice: ${device}\nUser note: ${note || '(none)'}\n\nUser-initiated diagnostic upload. Game logs are attached.`,
        attachments: [{ filename: `gtav-${id}.log`, content: bytes.buffer,
          type: 'text/plain; charset=utf-8', disposition: 'attachment' }]
      });
      return reply(202, { accepted: true, id });
    } catch {
      return reply(503, { error: 'unavailable' });
    }
  }
};
