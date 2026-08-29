# Railway wrapper image for the CRCON supervisor (background workers).
#
# Upstream bind-mounts ./config from the git checkout into every container,
# and the published backend image excludes it via .dockerignore. The
# supervisor is the only service that hard-requires those files (its
# entrypoint runs supervisord -c /config/supervisord.conf, and the cron
# program loads /config/crontab and the logrotate configs), so this image
# bakes them in. The files in config/ are vendored verbatim from upstream's
# config/ directory; re-sync them when bumping CRCON_VERSION.
#
# Keep CRCON_VERSION in lockstep with the image tags used by the other
# backend-family services in the Railway template.
ARG CRCON_VERSION=v12.2.1

FROM cericmathey/hll_rcon_tool:${CRCON_VERSION}

COPY config/ /config/

# ENTRYPOINT is inherited from the upstream image (/code/entrypoint.sh);
# the Railway start command invokes it with the "supervisor" argument.
