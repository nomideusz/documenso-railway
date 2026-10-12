#!/bin/sh
# Railway entrypoint for Documenso: signing certificate, migrations, first admin.
set -e
cd /app/apps/remix

# 1. Signing certificate. Template variables can't produce a .p12 and Railway's
#    pre-deploy step runs without the volume, so create a self-signed one on the
#    volume on first boot. It is reused on every later boot.
CERT="${NEXT_PRIVATE_SIGNING_LOCAL_FILE_PATH:-/opt/documenso/cert.p12}"
if [ -z "$NEXT_PRIVATE_SIGNING_LOCAL_FILE_CONTENTS" ] && [ ! -f "$CERT" ]; then
  host="${NEXT_PUBLIC_WEBAPP_URL#*://}"
  host="${host%%/*}"
  echo "Creating a self-signed signing certificate for ${host:-Documenso} at $CERT"
  mkdir -p "$(dirname "$CERT")"
  tmp="$(mktemp -d)"
  openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -subj "/CN=${host:-Documenso}" \
    -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
  openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$CERT" \
    -passout env:NEXT_PRIVATE_SIGNING_PASSPHRASE
  rm -rf "$tmp"
fi

# 2. Migrations (what upstream's start.sh does).
export NEXT_PRIVATE_DIRECT_DATABASE_URL="${NEXT_PRIVATE_DIRECT_DATABASE_URL:-$NEXT_PRIVATE_DATABASE_URL}"
npx prisma migrate deploy --schema ../../packages/prisma/schema.prisma

# 3. First admin. Documenso only lets verified emails sign in and has no admin
#    bootstrap, so without SMTP a fresh deploy has no usable login. Sign the
#    account up through the app's own endpoint on a side port Railway doesn't
#    route (sign-up forced on for this process only), then verify it and grant
#    ADMIN. Runs once: skipped as soon as a user with this email exists.
if [ -n "$DOCUMENSO_ADMIN_EMAIL" ]; then
  if node -e '
    const { PrismaClient } = require("@prisma/client");
    const p = new PrismaClient();
    p.user.findFirst({ where: { email: process.env.DOCUMENSO_ADMIN_EMAIL.toLowerCase() } })
      .then((u) => p.$disconnect().then(() => process.exit(u ? 0 : 1)));
  '; then
    echo "Admin $DOCUMENSO_ADMIN_EMAIL already exists"
  else
    echo "Creating admin $DOCUMENSO_ADMIN_EMAIL"
    NEXT_PUBLIC_DISABLE_SIGNUP=false NEXT_PUBLIC_DISABLE_EMAIL_PASSWORD_SIGNUP=false PORT=3999 \
      node build/server/main.js &
    pid=$!
    i=0
    until wget -q -O /dev/null http://127.0.0.1:3999/api/health; do
      i=$((i + 1))
      if [ "$i" -gt 120 ] || ! kill -0 "$pid" 2>/dev/null; then echo "Bootstrap server did not start"; exit 1; fi
      sleep 1
    done
    node -e '
      const { PrismaClient } = require("@prisma/client");
      const email = process.env.DOCUMENSO_ADMIN_EMAIL.toLowerCase();
      (async () => {
        const res = await fetch("http://127.0.0.1:3999/api/auth/email-password/signup", {
          method: "POST",
          headers: { "Content-Type": "application/json", Origin: new URL(process.env.NEXT_PUBLIC_WEBAPP_URL).origin },
          body: JSON.stringify({ name: "Admin", email, password: process.env.DOCUMENSO_ADMIN_PASSWORD }),
        });
        if (res.status !== 201) throw new Error("signup returned " + res.status + ": " + (await res.text()));
        const p = new PrismaClient();
        await p.user.update({ where: { email }, data: { emailVerified: new Date(), roles: ["USER", "ADMIN"] } });
        await p.$disconnect();
      })().catch((e) => { console.error(e.message); process.exit(1); });
    ' || { kill "$pid"; exit 1; }
    kill "$pid"
    wait "$pid" 2>/dev/null || true
    echo "Admin $DOCUMENSO_ADMIN_EMAIL created"
  fi
fi

exec node build/server/main.js
