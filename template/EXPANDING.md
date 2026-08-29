# Adding more game servers

One CRCON install manages up to 10 Hell Let Loose game servers. The
shared core deployed by the template (Postgres, Redis, Maintenance,
Webhooks) serves all of them; every additional game server adds exactly
three services: a backend, a supervisor, and a frontend. All servers
share player profiles, blacklists, VIPs, and accounts because they share
the database, and the server switcher in the UI discovers siblings
through the shared Redis.

This runbook adds game server **2**. For servers 3, 4, 5... repeat with
the next number. Two hard rules, straight from upstream:

- **Never reuse a `SERVER_NUMBER`** across live services. It namespaces
  every database record.
- **Never reuse an `HLL_REDIS_DB`** across live services. Redis ships
  with 16 logical databases, so numbers 1-10 are safe.

Use the number N for both. Server 1 already uses `1`.

## Step 1: create the three services

In the deployed project, duplicate the existing services (right-click →
Duplicate) or create them fresh from the sources below. Create all three
before editing variables, because they reference each other's domains.

| New service | Source | Start command / settings |
|---|---|---|
| `Backend2` | this repo, root directory `/template/backend` | identical to `Backend` (no start command, no healthcheck); its `/etc/hosts` alias becomes `frontend_2` automatically from `SERVER_NUMBER` |
| `Supervisor2` | same image | identical to `Supervisor`; **attach a fresh volume at `/scoreboard_db`** (volumes are not copied when duplicating) |
| `Frontend2` | this repo, root directory `/template/frontend` | identical to `Frontend`; generate a Railway domain targeting port 80 (and optionally a second domain targeting port 81 for the public scoreboard) |

Keep the image tag in lockstep with the other backend-family services.

## Step 2: set the variables

Duplicated services inherit the server-1 variables. Everything stays the
same **except** the rows below (a duplicated service copies these too, so
each one must be edited).

### Backend2: changed variables

| Name | Value | Notes |
|---|---|---|
| `HLL_HOST` | *(game server 2's IP)* | |
| `HLL_PORT` | *(game server 2's RCON port)* | |
| `HLL_PASSWORD` | *(game server 2's RCON password)* | |
| `HLL_GAME` | `hll` or `hllv` | per server; a mixed fleet is fine |
| `SERVER_NUMBER` | `2` | |
| `HLL_REDIS_DB` | `2` | |
| `HLL_REDIS_URL` | `redis://${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/2` | note the `/2` |
| `RCONWEB_API_SECRET` | `${{Backend.RCONWEB_API_SECRET}}` | all backends share ONE secret (they share one Django DB); a reference keeps them in lockstep |
| `SUPERVISOR_RPC_URL` | `http://${{Supervisor2.RAILWAY_PRIVATE_DOMAIN}}:9001/RPC2` | |
| `DOMAINS` | `${{Frontend2.RAILWAY_PUBLIC_DOMAIN}},${{RAILWAY_PRIVATE_DOMAIN}},healthcheck.railway.app` | |
| `RCONWEB_EXTERNAL_ADDRESS` | `${{Frontend2.RAILWAY_PUBLIC_DOMAIN}}` | |
| `CRCON_FRONTEND_HOST` | `${{Frontend2.RAILWAY_PRIVATE_DOMAIN}}` | |

Unchanged from `Backend`: all `HLL_DB_*` references, `HLL_REDIS_HOST`,
`HLL_REDIS_PORT`, `LOGGING_*`, `CONFIG_DIR`, `NB_API_*`, `PORT`, the
display-only port variables, and the start command.

### Supervisor2: changed variables

| Name | Value |
|---|---|
| `HLL_HOST` | `${{Backend2.HLL_HOST}}` |
| `HLL_PORT` | `${{Backend2.HLL_PORT}}` |
| `HLL_PASSWORD` | `${{Backend2.HLL_PASSWORD}}` |
| `HLL_GAME` | `${{Backend2.HLL_GAME}}` |
| `SERVER_NUMBER` | `2` |
| `HLL_REDIS_DB` | `2` |
| `HLL_REDIS_URL` | `redis://${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/2` |
| `RCONWEB_EXTERNAL_ADDRESS` | `${{Frontend2.RAILWAY_PUBLIC_DOMAIN}}` |

`RCONWEB_API_SECRET` stays `${{Backend.RCONWEB_API_SECRET}}` (the shared
secret lives on server 1's backend). Database and Redis host references
are unchanged.

### Frontend2: changed variables

| Name | Value |
|---|---|
| `CRCON_API_HOST` | `${{Backend2.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_GAME` | `${{Backend2.HLL_GAME}}` |

`RCONWEB_EXTERNAL_ADDRESS` stays `${{RAILWAY_PUBLIC_DOMAIN}}` (it is a
self-reference and resolves to Frontend2's own domain).

## Step 3: deploy and verify

Deploy the three services. No migration step is needed; Maintenance
already prepared the shared database, and Backend2 waits for it on first
boot just like server 1 did. Then check:

1. Log in at Frontend2's domain (accounts are shared with server 1, but
   you log in per domain; see note below).
2. The live game view populates from game server 2.
3. The server-switcher dropdown in each UI lists the other server.
4. The Services page on server 2 responds (that's `SUPERVISOR_RPC_URL`
   pointing at the right supervisor).

## Notes

- **Logins are per-domain on Railway-provided domains.** Accounts are
  shared, sessions are not. If you attach custom subdomains of one apex
  you control (e.g. `rcon1.example.com`, `rcon2.example.com`), set
  `SESSION_COOKIE_DOMAIN=.example.com` and `CSRF_COOKIE_DOMAIN=.example.com`
  on every backend, and add each custom domain to that backend's
  `DOMAINS` list, to get single sign-on across servers. This cannot work
  on `*.up.railway.app` domains.
- **Cost scales roughly linearly.** Each game server adds a supervisor
  (the heaviest service, ~15 worker processes), a backend, and a
  frontend. The shared Postgres is already sized for 10 servers
  (`max_connections=300`).
- **Removing a server:** delete its three services (and the supervisor's
  volume). Historical data stays in Postgres under that server number;
  don't reuse the number afterwards unless you know the history is
  irrelevant.
