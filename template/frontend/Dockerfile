# Railway wrapper image for the CRCON frontend (nginx).
#
# It extends the stock upstream frontend image with two things Railway needs:
#   1. Django's static files (admin CSS/JS) baked in at build time. Upstream
#      shares a ./static bind mount between the backend and frontend
#      containers; Railway volumes cannot be shared between services, so we
#      run collectstatic here instead and copy the result in.
#   2. A Railway-specific nginx config (see nginx.conf.template) that proxies
#      to the backend over Railway's private network instead of a compose
#      network alias.
#
# Pin CRCON_VERSION to the same tag used for the backend services in the
# Railway template so the static files match the API version.
ARG CRCON_VERSION=v12.2.0

FROM cericmathey/hll_rcon_tool:${CRCON_VERSION} AS djangostatic

# collectstatic cannot run at build time: CRCON's Django app opens a
# database connection during startup and there is no Postgres in the build.
# The only app with static files is django.contrib.admin, so copy its
# assets straight from the installed package; the result is identical to
# what collectstatic would produce (STATIC_URL=/djangostatic/ -> /admin/*).
RUN mkdir -p /static \
    && cp -r "$(python -c 'import django, pathlib; print(pathlib.Path(django.__file__).parent / "contrib" / "admin" / "static" / "admin")')" /static/admin

FROM cericmathey/hll_rcon_tool_frontend:${CRCON_VERSION}

# STATIC_URL=/djangostatic/ is served by nginx from /static (see nginx conf)
COPY --from=djangostatic /static /static

# /config normally comes from a bind mount; the upstream entrypoint prefers
# /config/nginx.conf when it exists, which our entrypoint generates there.
RUN mkdir -p /config /certs /railway

COPY nginx.conf.template /railway/nginx.conf.template
COPY entrypoint.sh /railway/entrypoint.sh
RUN chmod +x /railway/entrypoint.sh

ENTRYPOINT ["/railway/entrypoint.sh"]
