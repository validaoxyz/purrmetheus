#!/usr/bin/env bash
# Generates docker/Dockerfile, docker/docker-compose.yaml and
# prometheus/prometheus.yml from their templates by substituting values from
# .env.  Run from the repo root.
set -euo pipefail

cd "$(dirname "$0")"

# ---------------------------------------------------------------------------
# Sanity checks
# ---------------------------------------------------------------------------
for cmd in envsubst docker jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        case "$cmd" in
            envsubst) hint="install with 'apt install gettext-base' or 'brew install gettext'" ;;
            jq)       hint="install with 'apt install jq' or 'brew install jq'" ;;
            docker)   hint="install Docker Engine + the Compose plugin" ;;
        esac
        echo "ERROR: missing dependency: $cmd ($hint)" >&2
        exit 1
    fi
done

if [ ! -f .env ]; then
    echo "ERROR: .env file not found." >&2
    echo "       Run: cp .env.sample .env  and edit it before running this script." >&2
    exit 1
fi

set -a
# shellcheck disable=SC1091
source .env
set +a

# ---------------------------------------------------------------------------
# Defaults + derived values
# ---------------------------------------------------------------------------
: "${USE_DOCKER:=false}"
: "${IS_VALIDATOR:=false}"
: "${CHAIN:=mainnet}"
: "${NODE_LABEL:=hl-node}"
: "${EXPORTER_VERSION:=v3.0.0}"
: "${EXPORTER_EXTRA_FLAGS:=}"
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=admin}"
: "${GRAFANA_PORT:=3000}"
: "${PROMETHEUS_RETENTION:=30d}"

case "$CHAIN" in
    mainnet|testnet) ;;
    *)
        echo "ERROR: CHAIN must be 'mainnet' or 'testnet' (got '$CHAIN')." >&2
        exit 1
        ;;
esac

export USER_ID=$(id -u)
export GROUP_ID=$(id -g)
echo "Building for UID=$USER_ID GID=$GROUP_ID, chain=$CHAIN, exporter=$EXPORTER_VERSION"

# Build the JSON-array command passed to the exporter.  When the node binary
# is not bind-mounted into the container (USE_DOCKER=true), --skip-version-check
# and --skip-update-check stop the exporter from trying to look it up.
build_exporter_cmd() {
    local flags=( "start" "--chain=${CHAIN}" )
    if [ "$USE_DOCKER" = "true" ]; then
        flags+=( "--skip-version-check" "--skip-update-check" )
    fi
    # shellcheck disable=SC2206
    local extra=( ${EXPORTER_EXTRA_FLAGS} )
    flags+=( "${extra[@]}" )

    local out="["
    local first=1
    for f in "${flags[@]}"; do
        [ -z "$f" ] && continue
        if [ $first -eq 1 ]; then first=0; else out+=", "; fi
        out+="\"$f\""
    done
    out+="]"
    echo "$out"
}
export EXPORTER_CMD
EXPORTER_CMD=$(build_exporter_cmd)

# ---------------------------------------------------------------------------
# Bind-mount / volume layout
# ---------------------------------------------------------------------------
if [ "$USE_DOCKER" = "true" ]; then
    export VOLUME_MOUNTS="      - hyperliquid_hl-data:/home/hluser/hl:ro"
    export EXTRA_VOLUMES="  hyperliquid_hl-data:
    external: true"
    echo "Node mode: dockerized (external volume hyperliquid_hl-data)"
else
    if [ -z "${NODE_HOME:-}" ]; then
        NODE_HOME="${HOME}/hl"
        echo "NODE_HOME unset, defaulting to ${NODE_HOME}"
    fi
    if [ -z "${NODE_BINARY:-}" ]; then
        NODE_BINARY="${HOME}/hl-visor"
        echo "NODE_BINARY unset, defaulting to ${NODE_BINARY}"
    fi

    if [ ! -d "$NODE_HOME" ]; then
        echo "WARNING: NODE_HOME=$NODE_HOME does not exist on host." >&2
    fi
    if [ ! -e "$NODE_BINARY" ]; then
        echo "WARNING: NODE_BINARY=$NODE_BINARY does not exist on host." >&2
    fi

    BINARY_HOME=$(dirname "$NODE_BINARY")
    export NODE_HOME BINARY_HOME
    export VOLUME_MOUNTS="      - ${NODE_HOME}:/home/hluser/hl:ro
      - ${BINARY_HOME}:/home/hluser/bin:ro"
    export EXTRA_VOLUMES=""
    echo "Node mode: host (NODE_HOME=$NODE_HOME, BINARY_HOME=$BINARY_HOME)"
fi

# ---------------------------------------------------------------------------
# Render templates
# ---------------------------------------------------------------------------
mkdir -p docker prometheus

# Use a strict allow-list of variable names so unrelated `$foo` strings in
# the templates aren't accidentally expanded.
envsubst '${USER_ID} ${GROUP_ID} ${EXPORTER_VERSION}' \
    < docker/templates/Dockerfile.tmpl \
    > docker/Dockerfile

envsubst '${USER_ID} ${GROUP_ID} ${EXPORTER_VERSION} ${EXPORTER_CMD} ${GRAFANA_ADMIN_USER} ${GRAFANA_ADMIN_PASSWORD} ${GRAFANA_PORT} ${PROMETHEUS_RETENTION} ${VOLUME_MOUNTS} ${EXTRA_VOLUMES}' \
    < docker/templates/docker-compose.yaml.tmpl \
    > docker/docker-compose.yaml

envsubst '${CHAIN} ${NODE_LABEL}' \
    < prometheus/prometheus.yml.tmpl \
    > prometheus/prometheus.yml

echo
echo "Generated:"
echo "  docker/Dockerfile"
echo "  docker/docker-compose.yaml"
echo "  prometheus/prometheus.yml"
echo
echo "Next:  cd docker && docker compose up -d --build"
