#!/bin/sh
# Railway entrypoint wrapper: renders the Railway nginx config, then hands
# off to the stock upstream frontend entrypoint (game asset copy, runtime
# config generation, nginx start).
set -e

# Private-network hostname of the CRCON backend (API) service, e.g.
# backend.railway.internal. Set in the Railway template as
# ${{Backend.RAILWAY_PRIVATE_DOMAIN}}.
: "${CRCON_API_HOST:?CRCON_API_HOST must be set to the private domain of the backend service}"

# Only substitute our own variable; the nginx config is full of $vars that
# must survive untouched.
envsubst '${CRCON_API_HOST}' \
    < /railway/nginx.conf.template \
    > /config/nginx.conf

echo "Rendered /config/nginx.conf with CRCON_API_HOST=${CRCON_API_HOST}"

exec /code/entrypoint.sh "$@"
