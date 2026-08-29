# CRCON Railway template

Everything needed to deploy [CRCON](https://github.com/MarechJ/hll_rcon_tool),
the community RCON tool for Hell Let Loose, on [Railway](https://railway.com)
in a few clicks: no VPS, no Docker Compose, no manual `.env` editing.

CRCON gives Hell Let Loose server admins a full web admin UI, live game
view, automod, blacklists, VIP management, Discord webhooks, and a public
scoreboard site. Upstream ships it as a 7-container Docker Compose stack;
this directory adapts that stack to Railway services.

## What's here

- [`frontend/`](frontend/): the one custom image the template needs. It
  wraps the stock upstream frontend (nginx) image with a Railway-aware
  nginx config and bakes in Django's static files at build time (Railway
  volumes can't be shared between services the way upstream's bind mounts
  are). Everything else deploys straight from upstream's Docker Hub
  images with custom start commands.
- [`TEMPLATE.md`](TEMPLATE.md): the full recipe for Railway's template
  composer: every service, start command, variable, volume, and
  healthcheck, plus first-boot behavior and known limitations.
- [`EXPANDING.md`](EXPANDING.md): runbook for managing additional game
  servers (2-10) from one deployed install: three extra services per
  game server, with exactly which variables change.

## Architecture

```
                        Railway edge (TLS)
                          |           |
              admin domain :443   stats domain :443
                          |           |
                     [Frontend nginx :80 / :81]
                          |  (private network)
              /api /ws    v
                     [Backend  gunicorn :8000, daphne :8001]
                          |                     ^
                          |    [Supervisor workers] -- RPC :9001
                          |         |
        [Maintenance (migrations)]  |
                          |         |
                     [Postgres]  [Redis]      [Webhooks -> Discord]
```

Deployers enter three things at deploy time: their game server's IP, RCON
port, and RCON password. Everything else (database credentials, API
secret, service wiring) is generated or referenced automatically.

## Deploying / developing

- To build the template in the Railway dashboard, follow
  [`TEMPLATE.md`](TEMPLATE.md) step by step.
- To change the nginx behavior, edit
  [`frontend/nginx.conf.template`](frontend/nginx.conf.template); the
  entrypoint substitutes `${CRCON_API_HOST}` at container start.
- To track a new CRCON release, bump `CRCON_VERSION` in
  [`frontend/Dockerfile`](frontend/Dockerfile) and the image tags in the
  template's four backend-family services together.
