#!/usr/bin/env bash
# Railway entrypoint wrapper for the CRCON backend (Django API).
#
# Does three things upstream's compose setup gets for free:
#   1. Maps the compose-style hostname "frontend_<SERVER_NUMBER>" to the
#      Railway frontend service in /etc/hosts, refreshed in the
#      background. CRCON's multi-server registry stores that literal name
#      in Redis and calls http://frontend_<N>/api/get_connection_info to
#      build the UI server list; in compose, Docker DNS resolves it.
#   2. Waits for the Maintenance service to finish database migrations
#      (compose expresses this with depends_on + healthchecks).
#   3. Creates the directories upstream provides as bind mounts.
set -e

FRONTEND_HOST="${CRCON_FRONTEND_HOST:-frontend.railway.internal}"
ALIAS="frontend_${SERVER_NUMBER:-1}"

refresh_hosts_alias() {
    while true; do
        ip="$(getent hosts "$FRONTEND_HOST" | awk '{print $1; exit}')"
        if [ -n "$ip" ]; then
            current="$(awk -v a="$ALIAS" '$2 == a {print $1; exit}' /etc/hosts)"
            if [ "$current" != "$ip" ]; then
                # /etc/hosts is bind-mounted; sed -i's rename fails on it,
                # so rewrite via truncate instead.
                filtered="$(awk -v a="$ALIAS" '$2 != a' /etc/hosts)"
                printf '%s\n%s %s\n' "$filtered" "$ip" "$ALIAS" > /etc/hosts
            fi
        fi
        sleep 60
    done
}

mkdir -p /logs /static /servicediscovery

refresh_hosts_alias &

until python /code/rconweb/manage.py migrate --check >/dev/null 2>&1; do
    echo "Waiting for database migrations"
    sleep 5
done

if [ "$#" -eq 0 ]; then
    set -- web
fi
exec /code/entrypoint.sh "$@"
