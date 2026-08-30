# Verbatim upstream CRCON image, pinned. The maintenance and webhooks
# services build from this directory instead of pulling the image
# directly so that a CRCON version bump is a single commit here and
# every service in a deployment updates through Railway's one-click
# "update available" flow. No entrypoint or start-command changes; each
# service's start command picks its role.
ARG CRCON_VERSION=v12.2.0
FROM cericmathey/hll_rcon_tool:${CRCON_VERSION}
