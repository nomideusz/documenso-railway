# Deploy and Host Documenso on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/documenso-production?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=documenso-production)

[Documenso](https://documenso.com/) is the open-source DocuSign alternative. Upload a PDF, place signature, initials, date and text fields, and send it to one or more recipients in order. Each signed document comes back sealed with a digital signature and a signing certificate, with an audit log of every view and signature. It also has reusable templates, direct signing links, teams and a REST API with webhooks. This template runs the official Documenso image with Postgres, and creates both the signing certificate and your admin account on first boot, so you can sign in and seal documents right away, even without an email provider.

## About Hosting Documenso

The stack is two services: Documenso and Postgres.

- **Upstream's image, pinned.** Documenso runs from the official `documenso/documenso` image at a fixed release (v2.20.0), not `latest`. A thin wrapper ([source](https://github.com/nomideusz/documenso-railway)) adds one entrypoint script for the first-boot steps below. Upgrading means bumping the tag.
- **A signing certificate on first boot.** Documenso can't seal documents without a `.p12` certificate, and that is normally a manual OpenSSL step. On first boot the entrypoint creates a self-signed RSA certificate (valid 10 years, named after your domain) on a volume at `/opt/documenso/cert.p12`, protected by a generated passphrase. Later boots reuse it.
- **An admin who can sign in without SMTP.** Documenso only lets verified email addresses sign in, so a fresh install with no mail server has no working login. On first boot the entrypoint signs up `DOCUMENSO_ADMIN_EMAIL` through Documenso's own sign-up endpoint, on a port Railway doesn't route, then marks the email as verified and grants the account admin rights.
- **Sign-up closed.** Public sign-up is off by default (`NEXT_PUBLIC_DISABLE_SIGNUP=true`), so a stranger who finds your URL can't create an account on your instance. People you send documents to don't need an account to sign.
- **Generated secrets.** `NEXTAUTH_SECRET`, both encryption keys, the certificate passphrase and the admin password are generated at deploy time.
- **Migrations on every boot.** The database migrations run before the server starts, and Railway's health check on `/api/health` only switches traffic once they finish. Uploaded and signed PDFs are stored in Postgres.

## Common Use Cases

- Contracts, NDAs, offer letters and freelance agreements signed online, on your own infrastructure
- Sales and HR paperwork with templates and direct signing links you can share or embed
- Multi-party signing in a set order, with a sealed PDF and audit certificate at the end
- Automating document signing from your own app through the REST API and webhooks

## Dependencies for Documenso Hosting

- Postgres 17 (included, private network only)
- An email provider for sending documents out (optional: SMTP, or Resend over HTTPS)

### Deployment Dependencies

- [Documenso self-hosting documentation](https://docs.documenso.com/developers/self-hosting)
- [Documenso on GitHub](https://github.com/documenso/documenso)
- [Template source on GitHub](https://github.com/nomideusz/documenso-railway)

### Implementation Details

**Sign in.** Enter your email in `DOCUMENSO_ADMIN_EMAIL` when you deploy. When the deploy is green, open the Documenso service's Railway domain and sign in with that email and the `DOCUMENSO_ADMIN_PASSWORD` value from the Documenso service's Variables tab. Change the password afterwards under Settings → Security. Both variables are only read on first boot. The admin panel is at `/admin`.

**Signing invitations need email.** Documenso sends documents to recipients, and confirms completed documents, by email. Without a mail provider you can still sign documents yourself and seal them, and copy a recipient's signing link from the document page and send it some other way, but nobody gets notified automatically. Railway only allows outbound SMTP on the Pro plan. On any plan you can set `NEXT_PRIVATE_SMTP_TRANSPORT=resend` and `NEXT_PRIVATE_RESEND_API_KEY` to send over HTTPS instead. Otherwise fill in the `NEXT_PRIVATE_SMTP_*` variables. Either way, set `NEXT_PRIVATE_SMTP_FROM_ADDRESS`.

**Teammates.** Sign-up is closed, so teammates can't register on their own. To let them, set `NEXT_PUBLIC_DISABLE_SIGNUP=false`. They need working email to verify their address before they can sign in.

**The certificate is self-signed.** Sealed PDFs carry a valid digital signature, but PDF readers such as Adobe Acrobat show it as "validity unknown" because no public authority issued the certificate. That is normal for self-hosted Documenso. To use a certificate from a trusted CA, replace `/opt/documenso/cert.p12` on the volume and set `NEXT_PRIVATE_SIGNING_PASSPHRASE` to its passphrase, or put the base64-encoded file in `NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS`. Don't change the passphrase variable while the generated certificate is still in use.

**Custom domain.** After adding one, set `NEXT_PUBLIC_WEBAPP_URL` to `https://your-domain`. Documenso uses it for signing links, emails and its sign-in origin check.

**Telemetry.** Documenso sends anonymous usage data (app version and installation ID) by default. Set `DOCUMENSO_DISABLE_TELEMETRY=true` to turn it off.

**Back up.** Postgres holds every document. The volume holds the signing certificate. Also keep `NEXT_PRIVATE_ENCRYPTION_KEY` and `NEXT_PRIVATE_ENCRYPTION_SECONDARY_KEY`, which encrypt stored 2FA secrets and tokens.

**Resources.** On Railway, after signing and sealing a document, Documenso used about 480 MB of RAM (peaking at about 510 MB) and Postgres about 130 MB. That is at the Trial plan's 512 MB per-service limit, so use the Hobby plan or above.

## Why Deploy Documenso on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Documenso on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
