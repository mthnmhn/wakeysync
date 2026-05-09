# Umami Deployment Plan for WakeySync Telemetry

This document is intended to be executed by an agent (or carefully by a human) on a Linux server the operator owns. It deploys [Umami](https://umami.is/) behind HTTPS, creates a project for WakeySync, and produces the two values that need to be plugged into the app's `Info.plist`.

The plan is opinionated and should not need substantive decisions during execution. Where a value must be chosen, a sensible default is given and clearly marked.

---

## 0. Outputs the agent must produce

By the end of this plan, the agent must report back exactly:

1. The public Umami URL (e.g. `https://analytics.wakeysync.dev`).
2. The Umami **website ID** (a UUID) for the WakeySync project.
3. A public read-only share URL for the dashboard, if requested.
4. The admin password for the Umami dashboard (delivered to the operator out-of-band — never committed).

These three values get pasted into:

- `WakeySync-Info.plist` keys `WSUmamiEndpoint` and `WSUmamiWebsiteId`.
- `PRIVACY.md` "public dashboard" section.

---

## 1. Prerequisites the operator must provide

Before starting, confirm with the operator that the following exist. If any are missing, stop and ask. Do not proceed with placeholders.

| Prereq | Example | How to verify |
|---|---|---|
| A Linux VPS reachable over SSH | `203.0.113.10` | `ssh user@host echo ok` returns `ok` |
| A user with sudo or root access | `ubuntu` | `ssh user@host sudo -n true` succeeds |
| A DNS A record pointing to the VPS | `analytics.wakeysync.dev` | `dig +short analytics.wakeysync.dev` returns the VPS IP |
| Ports 80 and 443 open in the firewall | | `nc -zv host 80` and `nc -zv host 443` succeed |
| At least 1 GB RAM and 5 GB disk free | | `free -m`, `df -h /` |
| OS: Ubuntu 22.04 / 24.04 (the plan assumes this) | `lsb_release -a` | |

If the operator wants the agent to register a domain or DNS record, that is out of scope for this plan and must be done manually first.

---

## 2. High-level architecture

```
                ┌───────────────────────────────────────────────┐
                │                   VPS                         │
                │                                               │
  Internet ────▶│  Caddy :443 (TLS, auto-renew)                 │
                │     │                                         │
                │     ▼                                         │
                │  Umami :3000  (Node app, Docker)              │
                │     │                                         │
                │     ▼                                         │
                │  Postgres :5432  (Docker, named volume)       │
                │                                               │
                └───────────────────────────────────────────────┘
```

Caddy is chosen over nginx because it auto-provisions and renews Let's Encrypt certificates with no extra config. Postgres over MySQL because Umami's recent releases prefer it and it is what the official Docker compose uses.

All three services run as Docker containers under one `docker compose` file in `/opt/umami/`.

---

## 3. Step-by-step execution

The agent should run each block, verify the success check, and only then proceed. If any verification fails, stop and surface the error to the operator.

### 3.1 Connect and update the OS

```bash
ssh <user>@<host>
sudo apt update && sudo apt upgrade -y
sudo apt install -y curl ca-certificates ufw
```

**Verify:** `lsb_release -a` shows the expected Ubuntu version. `apt list --upgradable 2>/dev/null` shows zero packages.

### 3.2 Configure the firewall

```bash
sudo ufw allow OpenSSH
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw --force enable
sudo ufw status
```

**Verify:** `sudo ufw status` shows 22, 80, 443 as `ALLOW`. Postgres (5432) and Umami (3000) must NOT be in the public allow list — they are container-internal only.

### 3.3 Install Docker Engine + Compose plugin

Use Docker's official repo, not the distro package (which is often outdated).

```bash
curl -fsSL https://get.docker.com | sudo sh
sudo usermod -aG docker "$USER"
# Log out and back in for the group change to take effect, or use `sudo` for the rest.
```

**Verify:**
```bash
docker --version          # >= 24.x
docker compose version    # >= v2.x
```

### 3.4 Create the project directory and secrets

```bash
sudo mkdir -p /opt/umami
sudo chown "$USER":"$USER" /opt/umami
cd /opt/umami
```

Generate three random secrets. The agent must not reuse a hardcoded value.

```bash
APP_SECRET=$(openssl rand -hex 32)
DB_PASSWORD=$(openssl rand -hex 24)
ADMIN_PASSWORD=$(openssl rand -base64 18 | tr -d '=+/')
echo "ADMIN_PASSWORD (deliver to operator out-of-band): $ADMIN_PASSWORD"
```

**Important:** Never write `ADMIN_PASSWORD` to a file under version control. Deliver it to the operator over a secure channel and tell them to store it in a password manager.

Write `/opt/umami/.env` (mode 600):

```bash
cat > /opt/umami/.env <<EOF
DATABASE_URL=postgresql://umami:${DB_PASSWORD}@db:5432/umami
DATABASE_TYPE=postgresql
APP_SECRET=${APP_SECRET}
POSTGRES_DB=umami
POSTGRES_USER=umami
POSTGRES_PASSWORD=${DB_PASSWORD}
EOF
chmod 600 /opt/umami/.env
```

**Verify:** `ls -l .env` shows mode `-rw-------`.

### 3.5 Write the docker-compose file

Create `/opt/umami/docker-compose.yml`:

```yaml
services:
  umami:
    image: ghcr.io/umami-software/umami:postgresql-latest
    restart: always
    env_file: .env
    expose:
      - "3000"
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:3000/api/heartbeat || exit 1"]
      interval: 10s
      timeout: 5s
      retries: 6

  db:
    image: postgres:16-alpine
    restart: always
    env_file: .env
    volumes:
      - umami-db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U umami"]
      interval: 10s
      timeout: 5s
      retries: 6

  caddy:
    image: caddy:2-alpine
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
      - caddy-config:/config
    depends_on:
      - umami

volumes:
  umami-db:
  caddy-data:
  caddy-config:
```

Note: there is **no public port mapping** on `umami` or `db`. They are reachable only inside the compose network. Caddy is the only thing facing the internet.

### 3.6 Write the Caddyfile

Create `/opt/umami/Caddyfile`. Substitute the actual hostname:

```caddyfile
analytics.wakeysync.dev {
    encode zstd gzip
    reverse_proxy umami:3000

    # Defense-in-depth: the WakeySync app posts JSON to /api/send.
    # Static dashboard assets and admin live under /, /api, /share.

    header {
        Strict-Transport-Security "max-age=31536000; includeSubDomains"
        X-Content-Type-Options "nosniff"
        Referrer-Policy "no-referrer"
    }

    log {
        output file /data/access.log {
            roll_size 10mb
            roll_keep 5
        }
        format console
    }
}
```

**Verify:** `caddy validate --config /opt/umami/Caddyfile` would fail because Caddy isn't installed on the host — that's expected. The container will validate on start.

### 3.7 Bring up the stack

```bash
cd /opt/umami
docker compose pull
docker compose up -d
```

Watch the logs until Umami reports it is ready:

```bash
docker compose logs -f umami
# Expect lines like: "ready - started server on 0.0.0.0:3000"
# Press Ctrl-C to stop following.
```

**Verify:**
```bash
docker compose ps           # all three services Up / healthy
curl -fsS https://analytics.wakeysync.dev/api/heartbeat
# Expect: {"status":"ok"} or 200 with a small JSON body
```

If `curl` fails with a TLS error, wait 30 seconds and retry — Caddy may still be acquiring the certificate. If it persists for >2 minutes, check `docker compose logs caddy` for ACME errors (most commonly: DNS not pointing at the VPS yet).

### 3.8 Initial admin login and password change

Umami ships with default admin credentials: username `admin`, password `umami`. **Change this immediately.**

1. Open `https://analytics.wakeysync.dev/login` in a browser.
2. Log in as `admin` / `umami`.
3. Settings → Profile → Change password → set it to the `ADMIN_PASSWORD` generated in 3.4.
4. Log out and log back in to confirm.

**Verify:** logging in with `admin` / `umami` now fails.

### 3.9 Create the WakeySync project

In the Umami dashboard:

1. Navigate to **Settings → Websites → Add website**.
2. Fill in:
   - **Name:** `WakeySync`
   - **Domain:** `wakeysync.app`  *(matches the `WSUmamiHostname` in the app's Info.plist)*
3. Save.
4. Open the new entry → click **Edit** → copy the **Website ID** (UUID, e.g. `e5f6a1b2-...`).

Record this UUID — it is one of the two values the operator needs.

### 3.10 Configure CORS (only if needed)

Umami accepts cross-origin POSTs to `/api/send` by default in recent versions, but native macOS apps don't send an `Origin` header anyway, so no CORS work is normally required. If the agent sees `403` responses with origin-related logs, set the env var `CORS_MAX_AGE=86400` and add `TRACKER_SCRIPT_NAME=tracker.js` to `.env`, then `docker compose up -d --force-recreate umami`.

### 3.11 Smoke-test the event endpoint

From the agent's machine (not the VPS):

```bash
curl -fsS -X POST https://analytics.wakeysync.dev/api/send \
  -H "Content-Type: application/json" \
  -H "User-Agent: WakeySync/0.0.0-test (macOS 14.0; TestModel)" \
  -d '{
    "type": "event",
    "payload": {
      "website": "<PASTE-WEBSITE-ID-HERE>",
      "hostname": "wakeysync.app",
      "screen": "1x1",
      "language": "en-US",
      "url": "/",
      "name": "smoke_test",
      "data": { "app_version": "0.0.0", "macos": "14.0", "mac_model": "TestModel" }
    }
  }'
```

**Verify:** the response is HTTP 200 with a small JSON body. Within ~30 seconds the event appears in Umami → WakeySync → Events with name `smoke_test`.

### 3.12 (Optional) Create a public share link

In Umami → WakeySync → Settings → toggle **Share URL**. Copy the resulting `/share/<id>/wakeysync` URL. This produces a read-only dashboard the operator can link from `PRIVACY.md` and the README.

### 3.13 Set up automated backups

Schedule a daily pg_dump and 7-day rotation. Create `/opt/umami/backup.sh`:

```bash
cat > /opt/umami/backup.sh <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
BACKUP_DIR=/opt/umami/backups
mkdir -p "$BACKUP_DIR"
TS=$(date +%Y%m%d-%H%M%S)
docker compose -f /opt/umami/docker-compose.yml exec -T db \
  pg_dump -U umami umami | gzip > "$BACKUP_DIR/umami-$TS.sql.gz"
find "$BACKUP_DIR" -name 'umami-*.sql.gz' -mtime +7 -delete
EOF
chmod +x /opt/umami/backup.sh
```

Add a cron entry:

```bash
( crontab -l 2>/dev/null; echo "30 3 * * * /opt/umami/backup.sh" ) | crontab -
```

**Verify:** run `/opt/umami/backup.sh` once by hand, confirm a `.sql.gz` lands in `/opt/umami/backups/`.

If the operator wants off-server backups, the agent should additionally configure rclone or `aws s3 cp` here, but that requires credentials and is out of scope unless the operator provides them.

### 3.14 Set up update routine

Umami releases new images regularly. To update:

```bash
cd /opt/umami
docker compose pull
docker compose up -d
docker image prune -f
```

Schedule monthly via cron, or have the operator run it manually after reading release notes:

```bash
( crontab -l 2>/dev/null; echo "0 4 1 * * cd /opt/umami && docker compose pull && docker compose up -d && docker image prune -f" ) | crontab -
```

---

## 4. Hand-off to the WakeySync codebase

After 3.9 and 3.11 succeed, edit `WakeySync-Info.plist`:

```xml
<key>WSUmamiEndpoint</key>
<string>https://analytics.wakeysync.dev</string>
<key>WSUmamiWebsiteId</key>
<string>e5f6a1b2-...your-uuid...</string>
<key>WSUmamiHostname</key>
<string>wakeysync.app</string>
```

Then build and run the app, opt in via the consent dialog, click **Sync current time**, and confirm `app_launched` and either `sync_succeeded` or a `sync_failed_*` event lands in Umami within 30 seconds.

If desired, paste the Share URL from 3.12 into `PRIVACY.md` under the "Where the data lives" section.

---

## 5. Failure modes and rollback

| Symptom | Likely cause | Fix |
|---|---|---|
| `curl /api/heartbeat` hangs | DNS not pointing at VPS, or port 443 blocked | `dig`, then check cloud-provider firewall in addition to ufw |
| Caddy logs `no certificate available` | DNS just propagated; rate-limited by Let's Encrypt | Wait 1 hour, retry. If repeated, switch to `acme_ca https://acme-staging-v02.api.letsencrypt.org/directory` while debugging |
| Umami logs `password authentication failed for user "umami"` | DB password mismatch between `.env` and a pre-existing volume | `docker compose down -v` deletes the volume — only do this on a fresh install with no data |
| Events return 200 but never appear in dashboard | Wrong `website` UUID, or `hostname` mismatch with what's configured in Umami | Re-check 3.9 |
| Disk fills up | Large access logs | Tighten Caddy `roll_size` / `roll_keep`, and prune old Umami sessions: see Umami docs `umami-cli cleanup` |

To completely tear down (for a re-do):

```bash
cd /opt/umami
docker compose down -v   # WARNING: deletes the database
sudo rm -rf /opt/umami
```

---

## 6. Security notes the agent should respect

- **Never** publish or commit `APP_SECRET`, `DB_PASSWORD`, or the admin password.
- **Never** open ports 3000 or 5432 to the internet. They must remain container-internal.
- **Never** disable HTTPS or skip the Let's Encrypt step "to make testing easier."
- The Mac app must always POST to `https://`. There is no plaintext fallback.
- If the operator later adds a CDN (Cloudflare etc.) in front of Caddy, ensure it is in "DNS only" mode or that Umami's IP-hashing still receives the real client IP via `X-Forwarded-For` — otherwise unique counts will collapse to 1.

---

## 7. Estimated time

For an experienced operator with the prerequisites already in place: ~25 minutes end-to-end, most of which is waiting for Docker pulls and the first TLS certificate.
