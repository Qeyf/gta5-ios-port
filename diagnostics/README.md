# GtaV Mobile diagnostic relay

The app uploads reports only after the player taps Send. `POST /v1/logs` accepts
bounded plain-text reports and sends them as a log attachment through the native
Cloudflare Email binding. The recipient and sender are server secrets named
`DIAGNOSTICS_TO` and `DIAGNOSTICS_FROM`; never put them in the app, source, a
checked-in Wrangler variable or an HTTP response.

The service awaits email acceptance before returning HTTP 202 with
`{"accepted":true,"id":"<UUID>"}`. Acceptance is not a guarantee that the
recipient's mail provider places the message in the Inbox. Provider errors are
never returned verbatim. No report contents or addresses are logged by the
Worker, and Workers invocation persistence is disabled for this service.

Limits: 13 MiB request body; app snapshots preserve up to 6 MiB from each of the
current and previous logs, retaining startup and recent complete UTF-8 lines.
The configured recipient must be a verified Cloudflare destination, whose email
size allowance accommodates the attachment and MIME encoding. Routing/sender
domain authentication must remain valid. Existing root-domain mail records are
not changed by deploying this Worker.

The native rate-limit bindings allow 3 reports per minute per connecting IP and
20 per minute across this service in each Cloudflare location. These limits are
eventually consistent abuse controls, not a global exact quota. No reusable
client secret is embedded in a sideloaded IPA. The app cannot choose a recipient,
sender, subject, attachment name or arbitrary MIME headers.

Deployment uses the settings in `wrangler.jsonc` plus server-only secrets. The
production email binding is additionally restricted to the configured sender and
recipient in private Cloudflare deployment metadata. Preserve secret-text
bindings when updating through the multipart upload API. Tests:

```sh
node --test diagnostics/worker.test.mjs
```

Official references:
- https://developers.cloudflare.com/email-service/api/send-emails/workers-api/
- https://developers.cloudflare.com/email-service/platform/limits/
- https://developers.cloudflare.com/email-service/configuration/send-bindings/
- https://developers.cloudflare.com/workers/runtime-apis/bindings/rate-limit/
- https://developers.cloudflare.com/workers/configuration/secrets/
