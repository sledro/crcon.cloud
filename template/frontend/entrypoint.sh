#!/bin/sh
# Railway entrypoint wrapper: renders the Railway nginx config, then hands
# off to the stock upstream frontend entrypoint (game asset copy, runtime
# config generation, nginx start).
set -e

# Private-network hostname of the CRCON backend (API) service, e.g.
# backend.railway.internal. Set in the Railway template as
# ${{Backend.RAILWAY_PRIVATE_DOMAIN}}.
: "${CRCON_API_HOST:?CRCON_API_HOST must be set to the private domain of the backend service}"

# The container's own DNS server, for nginx's `resolver` directive (nginx
# does not read /etc/resolv.conf itself). Bracket IPv6 addresses.
CRCON_DNS="$(awk '/^nameserver/ {print $2; exit}' /etc/resolv.conf)"
case "$CRCON_DNS" in
    *:*) CRCON_DNS="[$CRCON_DNS]" ;;
esac
export CRCON_DNS

# Only substitute our own variables; the nginx config is full of $vars
# that must survive untouched.
envsubst '${CRCON_API_HOST} ${CRCON_DNS}' \
    < /railway/nginx.conf.template \
    > /config/nginx.conf

echo "Rendered /config/nginx.conf with CRCON_API_HOST=${CRCON_API_HOST} CRCON_DNS=${CRCON_DNS}"

exec /code/entrypoint.sh "$@"
