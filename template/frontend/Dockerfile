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
# Railway template (e.g. v12.2.1) so the static files match the API version.
ARG CRCON_VERSION=latest

FROM cericmathey/hll_rcon_tool:${CRCON_VERSION} AS djangostatic

# The maintenance flag makes settings.py skip DB access at import time, so
# collectstatic can run without Postgres/Redis being reachable.
ENV HLL_MAINTENANCE_CONTAINER=true \
    LOGGING_PATH=/tmp/ \
    LOGGING_FILENAME=collectstatic.log

RUN mkdir -p /static && cd rconweb && python manage.py collectstatic --noinput

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
