# Railway template spec for CRCON

This document is the exact recipe for building the CRCON template in
Railway's template composer (Workspace → Templates → New Template). Railway
templates are composed in the dashboard; there is no config file format, so
this file is the source of truth to type from.

Upstream project: https://github.com/MarechJ/hll_rcon_tool (CRCON, the
community RCON tool for Hell Let Loose).

## How the compose stack maps to Railway

Upstream runs 7 containers via Docker Compose (one game server setup).
Railway gets one service per container:

| Railway service | Source | Role |
|---|---|---|
| `Postgres` | image `postgres:12-alpine` | database |
| `Redis` | image `redis:alpine` | cache / queues |
| `Maintenance` | image `cericmathey/hll_rcon_tool` | one-shot migrations, then sleeps |
| `Webhooks` | image `cericmathey/hll_rcon_tool` | Discord webhook dispatcher |
| `Backend` | image `cericmathey/hll_rcon_tool` | Django API (gunicorn :8000, daphne :8001) |
| `Supervisor` | image `cericmathey/hll_rcon_tool` | ~15 background workers under supervisord |
| `Frontend` | this repo, root dir `/template/frontend` | nginx: admin UI (:80) + public stats (:81) |

Design decisions that differ from upstream compose, and why:

- **No shared bind mounts.** Railway volumes cannot be shared between
  services. The `./config` directory ships inside the backend image at
  `/code/config`, so each backend-family service copies it to `/config` in
  its start command. Django's static files are baked into the Frontend
  image at build time (see `frontend/Dockerfile`) instead of using the
  shared `./static` mount.
- **No `depends_on` ordering.** The Backend start command waits until the
  Maintenance service has finished database migrations (polls
  `manage.py migrate --check`) before starting the web server.
- **TLS at the edge.** Railway terminates HTTPS, so all upstream 443/444
  listeners are dropped and only ports 80 (admin UI) and 81 (public stats)
  exist inside the Frontend container.
- **Private networking is dual-stack** in Railway environments created
  after October 2025, so upstream's IPv4-only binds (`0.0.0.0`) work
  as-is. Do not deploy this template into a legacy IPv6-only environment.
- **Logs** go to ephemeral `/logs` inside each container instead of a
  shared mount. Use Railway's log viewer; the in-app log browser only sees
  the API container's own logs.

Pin one CRCON version everywhere. Use the same tag (e.g. `v12.2.1`) for
the four `cericmathey/hll_rcon_tool` services and for `CRCON_VERSION` in
`frontend/Dockerfile`, and bump them together. `latest` works but risks
version skew between deploy times.

---

## Service 1: Postgres

- **Source**: Docker image `postgres:12-alpine` (upstream's pinned image;
  CRCON's alembic migrations are tested against it)
- **Start command**: `docker-entrypoint.sh postgres -c max_connections=300`
  (Railway start commands replace the image ENTRYPOINT, so the stock
  entrypoint must be invoked explicitly or initdb never runs)
- **Volume**: mount at `/var/lib/postgresql/data`
- **Variables**:

| Name | Value | Notes |
|---|---|---|
| `POSTGRES_USER` | `rcon` | |
| `POSTGRES_DB` | `rcon` | |
| `POSTGRES_PASSWORD` | `${{secret(32, "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")}}` | CRCON forbids `% @ : / ? $ !` in the DB password, hence the explicit alphanumeric alphabet |
| `PGDATA` | `/var/lib/postgresql/data/pgdata` | subdirectory so initdb tolerates the mount point |

## Service 2: Redis

- **Source**: Docker image `redis:alpine`
- **Start command**: `docker-entrypoint.sh redis-server --save 60 1 --maxclients 100000`
  (mirrors upstream `config/redis.conf`)
- **Volume**: mount at `/data`
- **Variables**: none

## Service 3: Maintenance

Runs alembic + Django migrations and one-time data fixups, then sleeps
forever. Keep it deployed; upstream uses it as the migration runner on
every version upgrade.

- **Source**: Docker image `cericmathey/hll_rcon_tool:v12.2.1`
- **Start command**:

```
sh -c "mkdir -p /logs /config && cp -r /code/config/. /config/ && exec /code/entrypoint.sh maintenance"
```

- **Variables**:

| Name | Value |
|---|---|
| `HLL_MAINTENANCE_CONTAINER` | `true` |
| `HLL_DB_USER` | `${{Postgres.POSTGRES_USER}}` |
| `HLL_DB_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` |
| `HLL_DB_NAME` | `${{Postgres.POSTGRES_DB}}` |
| `HLL_DB_HOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_DB_HOST_PORT` | `5432` |
| `HLL_DB_URL` | `postgresql://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` |
| `HLL_REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_REDIS_HOST_PORT` | `6379` |
| `HLL_REDIS_DB` | `1` |
| `HLL_REDIS_URL` | `redis://${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/1` |

## Service 4: Webhooks

- **Source**: Docker image `cericmathey/hll_rcon_tool:v12.2.1`
- **Start command**:

```
sh -c "mkdir -p /logs /config && cp -r /code/config/. /config/ && exec /code/entrypoint.sh webhook_service"
```

- **Variables**:

| Name | Value |
|---|---|
| `HLL_WH_SERVICE_CONTAINER` | `true` |
| `LOGGING_LEVEL` | `INFO` |
| `LOGGING_PATH` | `/logs/` |
| `CONFIG_DIR` | `/config/` |
| `HLL_DB_USER` | `${{Postgres.POSTGRES_USER}}` |
| `HLL_DB_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` |
| `HLL_DB_NAME` | `${{Postgres.POSTGRES_DB}}` |
| `HLL_DB_HOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_DB_HOST_PORT` | `5432` |
| `HLL_DB_URL` | `postgresql://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` |
| `HLL_REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_REDIS_PORT` | `6379` |
| `HLL_WH_SERVICE_RL_RESET_SECS` | `3` |
| `HLL_WH_SERVICE_RL_REQUESTS_PER` | `5` |
| `HLL_WH_SERVICE_RL_TIME_WINDOW` | `600` |
| `HLL_WH_MAX_QUEUE_LENGTH` | `150` |
| `HLL_WH_LOOP_SLEEP_TIME` | `0.006` |

## Service 5: Backend

The Django API. This is where deployers enter their game server details;
every other service references them from here, so they are typed once.

- **Source**: Docker image `cericmathey/hll_rcon_tool:v12.2.1`
- **Start command** (waits for Maintenance to finish migrating before
  starting the web server):

```
sh -c "mkdir -p /logs /config /static /servicediscovery && cp -r /code/config/. /config/ && until python /code/rconweb/manage.py migrate --check >/dev/null 2>&1; do echo Waiting for database migrations; sleep 5; done; exec /code/entrypoint.sh web"
```

- **Healthcheck path**: `/api/get_version` (unauthenticated, returns 200)
- **Variables** (mark the first three as required user inputs with the
  given descriptions):

| Name | Value | Notes |
|---|---|---|
| `HLL_HOST` | *(user input, required)* | "IP address of your Hell Let Loose game server (no port)" |
| `HLL_PORT` | *(user input, required)* | "RCON port of your game server (not the game or query port)" |
| `HLL_PASSWORD` | *(user input, required)* | "RCON password of your game server" |
| `HLL_GAME` | `hll` | `hll` or `hllv` (Hell Let Loose: Vietnam) |
| `SERVER_NUMBER` | `1` | |
| `LOGGING_LEVEL` | `INFO` | |
| `LOGGING_PATH` | `/logs/` | |
| `CONFIG_DIR` | `/config/` | |
| `HLL_DB_USER` | `${{Postgres.POSTGRES_USER}}` | |
| `HLL_DB_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` | |
| `HLL_DB_NAME` | `${{Postgres.POSTGRES_DB}}` | |
| `HLL_DB_HOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` | |
| `HLL_DB_HOST_PORT` | `5432` | |
| `HLL_DB_URL` | `postgresql://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` | |
| `HLL_REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` | |
| `HLL_REDIS_PORT` | `6379` | |
| `HLL_REDIS_DB` | `1` | |
| `HLL_REDIS_URL` | `redis://${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/1` | |
| `PORT` | `8000` | unused by CRCON; tells Railway which port to healthcheck |
| `RCONWEB_API_SECRET` | `${{secret(64)}}` | encrypts sessions/passwords; never change after first deploy |
| `SUPERVISOR_RPC_URL` | `http://${{Supervisor.RAILWAY_PRIVATE_DOMAIN}}:9001/RPC2` | lets the UI's Services page control workers |
| `NB_API_WORKERS` | `1` | |
| `NB_API_THREADS` | `8` | |
| `DOMAINS` | `${{Frontend.RAILWAY_PUBLIC_DOMAIN}},${{RAILWAY_PRIVATE_DOMAIN}}` | extends Django ALLOWED_HOSTS + CSRF trusted origins; the private entry covers nginx's proxied Host header |
| `RCONWEB_EXTERNAL_ADDRESS` | `${{Frontend.RAILWAY_PUBLIC_DOMAIN}}` | |
| `RCONWEB_PORT` | `443` | display-only on Railway |
| `PUBLIC_STATS_PORT` | `80` | display-only on Railway |
| `PUBLIC_STATS_PORT_HTTPS` | `443` | display-only on Railway |
| `DONT_SEED_ADMIN_USER` | *(empty)* | empty seeds the default `admin`/`admin` login |
| `SENTRY_DSN` | *(empty, optional)* | |

## Service 6: Supervisor

Runs supervisord with all background workers (log loop, stats, automod,
scoreboard, rq workers, cron, ...). This is the heaviest service in the
stack (~15 Python processes).

- **Source**: Docker image `cericmathey/hll_rcon_tool:v12.2.1`
- **Start command**:

```
sh -c "mkdir -p /logs /config /scoreboard_db && cp -r /code/config/. /config/ && exec /code/entrypoint.sh supervisor"
```

- **Volume**: mount at `/scoreboard_db` (SQLite cache used by the
  scoreboard worker; the worker exits if the path is missing)
- **Variables**:

| Name | Value |
|---|---|
| `HLL_HOST` | `${{Backend.HLL_HOST}}` |
| `HLL_PORT` | `${{Backend.HLL_PORT}}` |
| `HLL_PASSWORD` | `${{Backend.HLL_PASSWORD}}` |
| `HLL_GAME` | `${{Backend.HLL_GAME}}` |
| `SERVER_NUMBER` | `1` |
| `LOGGING_LEVEL` | `INFO` |
| `LOGGING_PATH` | `/logs/` |
| `CONFIG_DIR` | `/config/` |
| `HLL_DB_USER` | `${{Postgres.POSTGRES_USER}}` |
| `HLL_DB_PASSWORD` | `${{Postgres.POSTGRES_PASSWORD}}` |
| `HLL_DB_NAME` | `${{Postgres.POSTGRES_DB}}` |
| `HLL_DB_HOST` | `${{Postgres.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_DB_HOST_PORT` | `5432` |
| `HLL_DB_URL` | `postgresql://${{Postgres.POSTGRES_USER}}:${{Postgres.POSTGRES_PASSWORD}}@${{Postgres.RAILWAY_PRIVATE_DOMAIN}}:5432/${{Postgres.POSTGRES_DB}}` |
| `HLL_REDIS_HOST` | `${{Redis.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_REDIS_PORT` | `6379` |
| `HLL_REDIS_DB` | `1` |
| `HLL_REDIS_URL` | `redis://${{Redis.RAILWAY_PRIVATE_DOMAIN}}:6379/1` |
| `RCONWEB_API_SECRET` | `${{Backend.RCONWEB_API_SECRET}}` |
| `RCONWEB_EXTERNAL_ADDRESS` | `${{Frontend.RAILWAY_PUBLIC_DOMAIN}}` |

## Service 7: Frontend

- **Source**: this GitHub repo, **root directory** `/template/frontend`
  (builds `frontend/Dockerfile` from this directory)
- **Public networking**: HTTP, target port **80** (generate a Railway
  domain). The public scoreboard site listens on port 81; deployers who
  want it add a second domain to this service targeting port 81 after
  deploy (Settings → Networking → add domain, pick port 81).
- **Healthcheck path**: `/`
- **Variables**:

| Name | Value |
|---|---|
| `CRCON_API_HOST` | `${{Backend.RAILWAY_PRIVATE_DOMAIN}}` |
| `HLL_GAME` | `${{Backend.HLL_GAME}}` |
| `RCONWEB_EXTERNAL_ADDRESS` | `${{RAILWAY_PUBLIC_DOMAIN}}` |

---

## First-boot sequence (what deployers will see)

1. Postgres and Redis come up in seconds.
2. Maintenance pulls the CRCON image, runs alembic + Django migrations
   (roughly 30-60s), then idles. It is expected to stay "running" forever.
3. Backend prints `Waiting for database migrations` until step 2
   completes, then seeds the database and starts gunicorn/daphne. It
   seeds a default web login of `admin` / `admin`.
4. Supervisor starts its workers; a few restart until Backend is up
   (supervisord retries internally, this is normal).
5. Frontend builds from this repo (pulls both upstream images, runs
   collectstatic), then serves the UI. nginx exits and restarts until the
   Backend's private DNS name resolves; one or two crash-restarts during
   the very first deploy are normal.

Immediately after first login, deployers must change the `admin` password
(admin UI → Settings, or `/admin`).

## Known limitations

- **The template deploys one game server.** Upstream supports up to 10
  game servers per install; on Railway each additional server is three
  more services (backend/supervisor/frontend) added to the deployed
  project. [EXPANDING.md](EXPANDING.md) is the exact runbook.
- **In-app log browser is partial.** Upstream shares `/logs` between all
  containers; here each service keeps its own. Use Railway's log viewer
  for worker logs.
- **Media uploads don't persist or serve.** Upstream serves user uploads
  from a shared static mount. Rarely used; revisit if deployers ask.
- **Requires dual-stack private networking** (Railway environments created
  after mid-October 2025). In older environments the private network is
  IPv6-only and the upstream image binds IPv4 only.

## Publishing checklist

1. Push this repo to GitHub (public) so the Frontend service can build.
2. Compose the template exactly as above, deploy it into a scratch
   project, and verify: login at the Frontend domain, live game view
   populates, Services page (supervisord RPC) responds, scoreboard site
   on the port-81 domain.
3. Fill in the template overview page (description, README, category
   "Gaming"), then publish to the marketplace.
4. Railway's kickback program pays template authors up to 25% of usage
   revenue; enrollment is on the template settings page.
5. On each upstream CRCON release: bump the image tags in the four
   backend-family services, bump `CRCON_VERSION` in
   `frontend/Dockerfile`, commit to main. Deployed instances get a
   one-click update prompt for the repo-based Frontend service; image
   services update on their next redeploy.
