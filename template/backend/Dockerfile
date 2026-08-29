# Railway wrapper image for the CRCON backend (Django API).
#
# Wraps the upstream entrypoint with Railway-specific glue; see
# railway-entrypoint.sh for what and why. No custom start command should
# be set on the Railway service: the wrapper defaults to "web".
#
# Keep CRCON_VERSION in lockstep with the image tags used by the other
# backend-family services in the Railway template.
ARG CRCON_VERSION=v12.2.1

FROM cericmathey/hll_rcon_tool:${CRCON_VERSION}

COPY railway-entrypoint.sh /railway-entrypoint.sh
RUN chmod +x /railway-entrypoint.sh

ENTRYPOINT ["/railway-entrypoint.sh"]
