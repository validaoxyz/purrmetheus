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

if ! docker compose version >/dev/null 2>&1; then
    echo "ERROR: Docker Compose v2 is required (the 'docker compose' plugin is unavailable)." >&2
    exit 1
fi

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
: "${CHAIN:=mainnet}"
: "${NODE_LABEL:=hl-node}"
: "${EXPORTER_VERSION:=v4.0.7}"
: "${EXPORTER_EXTRA_FLAGS:=}"
: "${SKIP_VERSION_CHECK:=false}"
: "${SKIP_UPDATE_CHECK:=false}"
# The runtime image follows the invoking user's identity by default. CI or a
# different node account can provide explicit non-root IDs without running the
# generator under sudo.
: "${EXPORTER_UID:=}"
: "${EXPORTER_GID:=}"
: "${INFO_ENDPOINT_URL:=}"
# A deliberately empty value disables the optional projection mount.  Use an
# explicit presence check because `:=` would turn an intentional empty value
# back into the default.
if [ "${CRIT_LOCATIONS_DIR+x}" != x ]; then
    CRIT_LOCATIONS_DIR=/tmp/crit_msg_latest_stats
fi
: "${GRAFANA_ADMIN_USER:=admin}"
: "${GRAFANA_ADMIN_PASSWORD:=admin}"
: "${GRAFANA_PORT:=3000}"
: "${PROMETHEUS_RETENTION:=30d}"

for boolean_name in USE_DOCKER SKIP_VERSION_CHECK SKIP_UPDATE_CHECK; do
    boolean_value=${!boolean_name}
    case "$boolean_value" in
        true|false) ;;
        *)
            echo "ERROR: $boolean_name must be 'true' or 'false' (got '$boolean_value')." >&2
            exit 1
            ;;
    esac
done

CHAIN=$(printf '%s' "$CHAIN" | tr '[:upper:]' '[:lower:]' | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
case "$CHAIN" in
    mainnet) ;;
    testnet) ;;
    *)
        echo "ERROR: CHAIN must be 'mainnet' or 'testnet' (got '$CHAIN')." >&2
        exit 1
        ;;
esac

# Defaults above are assigned after sourcing .env, so export every value that
# envsubst is allowed to render.  Without this explicit export, a sparse .env
# would silently produce empty image, chain, and credential fields.
export CHAIN NODE_LABEL EXPORTER_VERSION GRAFANA_ADMIN_USER \
    GRAFANA_ADMIN_PASSWORD GRAFANA_PORT PROMETHEUS_RETENTION

if [[ "$EXPORTER_VERSION" == *[!A-Za-z0-9._-]* || -z "$EXPORTER_VERSION" ]]; then
    echo "ERROR: EXPORTER_VERSION must be a release tag such as v4.0.7 or 'latest'." >&2
    exit 1
fi

if [[ "$EXPORTER_EXTRA_FLAGS" == *$'\n'* || "$EXPORTER_EXTRA_FLAGS" == *$'\r'* ]]; then
    echo "ERROR: EXPORTER_EXTRA_FLAGS must be a single line of whitespace-delimited CLI tokens." >&2
    exit 1
fi

if ! [[ "$NODE_LABEL" =~ ^[A-Za-z0-9._-]+$ ]]; then
    echo "ERROR: NODE_LABEL may contain only letters, numbers, '.', '_' and '-' (got '$NODE_LABEL')." >&2
    exit 1
fi

if ! [[ "$GRAFANA_PORT" =~ ^[0-9]+$ ]] || [ "${#GRAFANA_PORT}" -gt 5 ] || \
    [[ "$GRAFANA_PORT" =~ ^0[0-9]+$ ]] || ((GRAFANA_PORT < 1 || GRAFANA_PORT > 65535)); then
    echo "ERROR: GRAFANA_PORT must be an integer from 1 to 65535 (got '$GRAFANA_PORT')." >&2
    exit 1
fi

if ! [[ "$PROMETHEUS_RETENTION" =~ ^[0-9]+(ms|s|m|h|d|w|y)([0-9]+(ms|s|m|h|d|w|y))*$ ]]; then
    echo "ERROR: PROMETHEUS_RETENTION must be a Prometheus duration such as 30d (got '$PROMETHEUS_RETENTION')." >&2
    exit 1
fi

for value_name in INFO_ENDPOINT_URL CRIT_LOCATIONS_DIR NODE_HOME NODE_BINARY BINARY_HOME \
    GRAFANA_ADMIN_USER GRAFANA_ADMIN_PASSWORD EXPORTER_UID EXPORTER_GID; do
    value=${!value_name:-}
    if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
        echo "ERROR: $value_name must not contain a newline." >&2
        exit 1
    fi
done

if [[ "$INFO_ENDPOINT_URL" == *[[:space:]]* ]]; then
    echo "ERROR: INFO_ENDPOINT_URL must not contain whitespace." >&2
    exit 1
fi

if [ -n "$INFO_ENDPOINT_URL" ] && [[ ! "$INFO_ENDPOINT_URL" =~ ^https?://[^[:space:]]+$ ]]; then
    echo "ERROR: INFO_ENDPOINT_URL must be an http:// or https:// URL (got '$INFO_ENDPOINT_URL')." >&2
    exit 1
fi

if [ -n "$CRIT_LOCATIONS_DIR" ] && [[ "$CRIT_LOCATIONS_DIR" != /* ]]; then
    echo "ERROR: CRIT_LOCATIONS_DIR must be an absolute host path (got '$CRIT_LOCATIONS_DIR')." >&2
    exit 1
fi

# The generated command owns these values because mounts, health checks, and
# Prometheus labels depend on them.  Reject a duplicate instead of allowing a
# later Go flag to silently diverge from the rendered stack.
split_extra_flags() {
    EXTRA_FLAGS_ARRAY=()
    if [[ "$EXPORTER_EXTRA_FLAGS" =~ ^[[:space:]]*$ ]]; then
        return 0
    fi
    read -r -a EXTRA_FLAGS_ARRAY <<< "$EXPORTER_EXTRA_FLAGS"
}

validate_extra_flags() {
    local token name
    PROBE_INFO_ENABLED=false
    EXTENDED_METRICS_ENABLED=false
    # Bash 3.2 with `set -u` treats an empty array expansion as unset.  Test
    # the source string before touching the array so an explicit empty value
    # remains a valid configuration.
    if [[ "$EXPORTER_EXTRA_FLAGS" =~ ^[[:space:]]*$ ]]; then
        return 0
    fi
    split_extra_flags
    for token in "${EXTRA_FLAGS_ARRAY[@]}"; do
        if [[ "$token" != -* || "$token" == "-" ]]; then
            echo "ERROR: EXPORTER_EXTRA_FLAGS accepts only option tokens; use --flag=value for options with a value (got '$token')." >&2
            exit 1
        fi
        name="${token%%=*}"
        case "$name" in
            --probe-info-endpoint|-probe-info-endpoint)
                # Go's flag package accepts both one- and two-dash forms and
                # ParseBool's 1/0/t/f spellings.  Mirror those forms here so a
                # Docker profile cannot silently probe its own loopback when
                # the node URL was omitted.
                if [[ "$token" == *=* ]]; then
                    case "${token#*=}" in
                        1|t|T|true|TRUE|True) PROBE_INFO_ENABLED=true ;;
                        0|f|F|false|FALSE|False) PROBE_INFO_ENABLED=false ;;
                        *)
                            echo "ERROR: invalid boolean value for '$name' in EXPORTER_EXTRA_FLAGS (use true/false or 1/0)." >&2
                            exit 1
                            ;;
                    esac
                else
                    PROBE_INFO_ENABLED=true
                fi
                ;;
            --extended-metrics|-extended-metrics)
                if [[ "$token" == *=* ]]; then
                    case "${token#*=}" in
                        1|t|T|true|TRUE|True) EXTENDED_METRICS_ENABLED=true ;;
                        0|f|F|false|FALSE|False) EXTENDED_METRICS_ENABLED=false ;;
                        *)
                            echo "ERROR: invalid boolean value for '$name' in EXPORTER_EXTRA_FLAGS (use true/false or 1/0)." >&2
                            exit 1
                            ;;
                    esac
                else
                    EXTENDED_METRICS_ENABLED=true
                fi
                ;;
            start|--|-h|--help|-v|--version)
                echo "ERROR: EXPORTER_EXTRA_FLAGS cannot contain the command or terminator '$token'." >&2
                exit 1
                ;;
        esac
        case "$name" in
            --chain|-chain|--node-home|-node-home|--node-binary|-node-binary|\
            --metrics-port|-metrics-port|--skip-version-check|-skip-version-check|\
            --skip-update-check|-skip-update-check|--info-endpoint-url|-info-endpoint-url)
                echo "ERROR: EXPORTER_EXTRA_FLAGS cannot override reserved flag '$name'. Configure the stack setting instead." >&2
                exit 1
                ;;
            --evm|-evm|--enable-otlp|-enable-otlp|--enable-prom|-enable-prom|\
            --disable-prom|-disable-prom|--evm-block-type-metrics|-evm-block-type-metrics|\
            --enable-contract-metrics|-enable-contract-metrics|\
            --enable-replica-metrics|-enable-replica-metrics)
                echo "ERROR: retired hyperliquid-exporter flag '$name'; use the v4 flag documented in .env.sample." >&2
                exit 1
                ;;
        esac
    done
}
validate_extra_flags

if [ "$USE_DOCKER" = "true" ] && [ "$PROBE_INFO_ENABLED" = "true" ] && [ -z "$INFO_ENDPOINT_URL" ]; then
    echo "ERROR: Dockerized-node mode requires INFO_ENDPOINT_URL when --probe-info-endpoint is enabled; the exporter container loopback is not the node." >&2
    exit 1
fi
if [ "$USE_DOCKER" = "true" ] && [ "$PROBE_INFO_ENABLED" = "true" ]; then
    info_url_lower=$(printf '%s' "$INFO_ENDPOINT_URL" | tr '[:upper:]' '[:lower:]')
    info_authority=${info_url_lower#*://}
    info_authority=${info_authority%%/*}
    info_authority=${info_authority%%\?*}
    info_host=${info_authority##*@}
    if [[ "$info_host" == \[*\]* ]]; then
        info_host=${info_host#\[}
        info_host=${info_host%%\]*}
    else
        info_host=${info_host%%:*}
    fi
    case "$info_host" in
        localhost|localhost.|0.0.0.0|127.*|::1|::1%*|0:0:0:0:0:0:0:1|\
        ::ffff:127.*|::ffff:7f*|0:0:0:0:0:ffff:7f*)
        echo "ERROR: INFO_ENDPOINT_URL cannot use loopback in Dockerized-node mode; point it at a published host or service address." >&2
        exit 1
        ;;
    esac
fi

if [ -n "$EXPORTER_UID" ]; then USER_ID=$EXPORTER_UID; else USER_ID=$(id -u); fi
if [ -n "$EXPORTER_GID" ]; then GROUP_ID=$EXPORTER_GID; else GROUP_ID=$(id -g); fi
if ! [[ "$USER_ID" =~ ^[1-9][0-9]{0,9}$ ]] || ((USER_ID > 2147483647)); then
    echo "ERROR: EXPORTER_UID must be a non-root decimal UID from 1 to 2147483647 (got '$USER_ID')." >&2
    exit 1
fi
if ! [[ "$GROUP_ID" =~ ^[1-9][0-9]{0,9}$ ]] || ((GROUP_ID > 2147483647)); then
    echo "ERROR: EXPORTER_GID must be a non-root decimal GID from 1 to 2147483647 (got '$GROUP_ID')." >&2
    exit 1
fi
export USER_ID GROUP_ID
echo "Building for UID=$USER_ID GID=$GROUP_ID, chain=$CHAIN, exporter=$EXPORTER_VERSION"

# Build the JSON-array command passed to the exporter. When the node binary is
# not bind-mounted into the container (USE_DOCKER=true), both binary checks are
# disabled automatically. Host operators can disable either check explicitly
# when egress or local binary policy requires it.
build_exporter_cmd() {
    local flags=( "start" "--chain=${CHAIN}" )
    if [ "$USE_DOCKER" = "true" ] || [ "$SKIP_VERSION_CHECK" = "true" ]; then
        flags+=( "--skip-version-check" )
    fi
    if [ "$USE_DOCKER" = "true" ] || [ "$SKIP_UPDATE_CHECK" = "true" ]; then
        flags+=( "--skip-update-check" )
    fi
    if [ -n "$INFO_ENDPOINT_URL" ]; then
        flags+=( "--info-endpoint-url=${INFO_ENDPOINT_URL}" )
    fi
    # Flags are whitespace-delimited CLI tokens. The splitter treats a
    # whitespace-only value as empty on Bash 3.2 as well as newer Bash.
    if [[ ! "$EXPORTER_EXTRA_FLAGS" =~ ^[[:space:]]*$ ]]; then
        split_extra_flags
        flags+=( "${EXTRA_FLAGS_ARRAY[@]}" )
    fi

    local out="["
    local first=1
    for f in "${flags[@]}"; do
        [ -z "$f" ] && continue
        if [ $first -eq 1 ]; then first=0; else out+=", "; fi
        # jq supplies correct JSON escaping for user-provided flag values.
        out+="$(jq -Rn --arg value "$f" '$value')"
    done
    out+="]"
    echo "$out"
}
export EXPORTER_CMD
EXPORTER_CMD=$(build_exporter_cmd)
# Compose performs its own interpolation after envsubst.  Preserve literal
# dollar signs in user-provided flag values (for example, an endpoint token).
EXPORTER_CMD=${EXPORTER_CMD//\$/\$\$}
export EXPORTER_CMD

# ---------------------------------------------------------------------------
# Bind-mount / volume layout
# ---------------------------------------------------------------------------
# JSON scalar values are valid YAML and prevent credentials and host paths from
# changing the structure of the generated Compose file.  Doubled '$' is
# Compose's escape for a literal dollar sign.
compose_json_scalar() {
    local value=${1//\$/\$\$}
    printf '%s' "$value" | jq -R .
}

if [ "$USE_DOCKER" = "true" ]; then
    export NODE_MODE=docker
    # The reduced profile deliberately does not request host PID visibility;
    # its process and filesystem alerts are disabled by node_mode.
    export EXPORTER_PID_BLOCK=""
    export CONTAINER_NODE_BINARY="/home/hluser/bin/hl-node"
    # The companion Hyperliquid node compose project persists hl-data at
    # /home/hluser/hl/data.  Mounting at the data subdirectory preserves the
    # exporter contract ($NODE_HOME/data/...).  Root-level node state and
    # binaries remain unavailable in this reduced profile, so version/update
    # checks are skipped and their source health is reported accordingly.
    export VOLUME_MOUNTS="      - type: volume
        source: hyperliquid_hl-data
        target: /home/hluser/hl/data
        read_only: true"
    export NODE_BINARY_MOUNT=""
    export EXTRA_VOLUMES="  hyperliquid_hl-data:
    external: true"
    export EXPORTER_TARGET="hl_exporter:8086"
    export EXPORTER_NETWORK_BLOCK="    networks:
      - purrmetheus"
    export PROMETHEUS_EXTRA_HOSTS=""
    echo "Node mode: dockerized (external volume hyperliquid_hl-data)"
else
    export NODE_MODE=host
    export EXPORTER_PID_BLOCK="    pid: host"
    if [ -z "${NODE_HOME:-}" ]; then
        NODE_HOME="${HOME}/hl"
        echo "NODE_HOME unset, defaulting to ${NODE_HOME}"
    fi
    if [ -z "${NODE_BINARY:-}" ]; then
        NODE_BINARY="${HOME}/hl-node"
        echo "NODE_BINARY unset, defaulting to ${NODE_BINARY}"
    fi

    if [[ "$NODE_HOME" != /* || "$NODE_BINARY" != /* ]]; then
        echo "ERROR: NODE_HOME and NODE_BINARY must be absolute host paths in host-node mode." >&2
        exit 1
    fi

    if [ "$NODE_HOME" = "/" ]; then
        echo "ERROR: NODE_HOME=/ is too broad; point it at the node data directory." >&2
        exit 1
    fi

    if [ ! -d "$NODE_HOME" ]; then
        echo "ERROR: NODE_HOME=$NODE_HOME does not exist or is not a directory." >&2
        exit 1
    fi
    NODE_HOME=$(cd "$NODE_HOME" && pwd -P)
    if [ "$NODE_HOME" = "/" ]; then
        echo "ERROR: NODE_HOME resolves to the host root; point it at the node data directory." >&2
        exit 1
    fi
    if [ ! -f "$NODE_BINARY" ] || [ ! -x "$NODE_BINARY" ]; then
        echo "ERROR: NODE_BINARY=$NODE_BINARY does not exist as an executable file." >&2
        exit 1
    fi

    if [ -L "$NODE_BINARY" ]; then
        echo "ERROR: NODE_BINARY must be a regular executable, not a symlink; point it at the resolved binary." >&2
        exit 1
    fi
    NODE_BINARY_DIR=$(cd "$(dirname "$NODE_BINARY")" && pwd -P)
    if [ "$NODE_BINARY_DIR" = "/" ]; then
        echo "ERROR: NODE_BINARY resolves into the host root; use a dedicated binary directory." >&2
        exit 1
    fi
    if [ -z "${BINARY_HOME:-}" ]; then
        BINARY_HOME="$NODE_BINARY_DIR"
    fi
    if [[ "$BINARY_HOME" != /* ]]; then
        echo "ERROR: BINARY_HOME must be an absolute host directory in host-node mode." >&2
        exit 1
    fi
    if [ "$BINARY_HOME" = "/" ]; then
        echo "ERROR: BINARY_HOME=/ is too broad; point it at the directory containing hl-visor." >&2
        exit 1
    fi
    if [ ! -d "$BINARY_HOME" ]; then
        echo "ERROR: BINARY_HOME=$BINARY_HOME does not exist or is not a directory." >&2
        exit 1
    fi
    BINARY_HOME=$(cd "$BINARY_HOME" && pwd -P)
    NODE_BINARY_NAME=$(basename "$NODE_BINARY")
    if [ "$BINARY_HOME" = "$NODE_BINARY_DIR" ]; then
        export CONTAINER_NODE_BINARY="/home/hluser/bin/${NODE_BINARY_NAME}"
        export NODE_BINARY_MOUNT=""
    else
        # Keep BINARY_HOME visible at the path used by the v4 update checker,
        # while exposing a separately located hl-node at a dedicated path.
        export CONTAINER_NODE_BINARY="/home/hluser/node-bin/${NODE_BINARY_NAME}"
        node_binary_home_source=$(compose_json_scalar "${NODE_BINARY_DIR}")
        export NODE_BINARY_MOUNT="      - type: bind
        source: ${node_binary_home_source}
        target: /home/hluser/node-bin
        read_only: true
        bind:
          create_host_path: false"
    fi
    export NODE_HOME BINARY_HOME
    # Long Compose volume syntax keeps spaces, colons, and backslashes in
    # operator paths data rather than YAML punctuation.
    node_home_source=$(compose_json_scalar "${NODE_HOME}")
    binary_home_source=$(compose_json_scalar "${BINARY_HOME}")
    export VOLUME_MOUNTS="      - type: bind
        source: ${node_home_source}
        target: /home/hluser/hl
        read_only: true
        bind:
          create_host_path: false
      - type: bind
        source: ${binary_home_source}
        target: /home/hluser/bin
        read_only: true
        bind:
          create_host_path: false"
    export EXTRA_VOLUMES=""
    export EXPORTER_TARGET="host.docker.internal:8086"
    export EXPORTER_NETWORK_BLOCK="    network_mode: host"
    export PROMETHEUS_EXTRA_HOSTS="    extra_hosts:
      - \"host.docker.internal:host-gateway\""
    echo "Node mode: host (NODE_HOME=$NODE_HOME, BINARY_HOME=$BINARY_HOME)"
fi

# The v4 critical-location monitor reads this fixed path inside the exporter.
# A read-only bind makes the host projection visible without granting write
# access.  In Dockerized-node mode the operator must arrange for the node's
# /tmp projection to be exported to this host path.  Do not ask Docker to
# create a missing source directory: that would look like a successful mount
# while silently hiding the unavailable optional source.
if [ -z "$CRIT_LOCATIONS_DIR" ]; then
    export CRIT_LOCATIONS_MOUNT=""
    echo "Critical-location projection mount disabled"
elif [ -d "$CRIT_LOCATIONS_DIR" ]; then
    CRIT_LOCATIONS_DIR=$(cd "$CRIT_LOCATIONS_DIR" && pwd -P)
    if [ "$CRIT_LOCATIONS_DIR" = "/" ]; then
        echo "ERROR: CRIT_LOCATIONS_DIR resolves to the host root; use the dedicated critical-message projection directory." >&2
        exit 1
    fi
    if [ "$EXTENDED_METRICS_ENABLED" != "true" ]; then
        echo "WARNING: CRIT_LOCATIONS_DIR is mounted, but the v4 critical-location monitor requires --extended-metrics." >&2
    fi
    crit_locations_source=$(compose_json_scalar "${CRIT_LOCATIONS_DIR}")
    export CRIT_LOCATIONS_MOUNT="      - type: bind
        source: ${crit_locations_source}
        target: /tmp/crit_msg_latest_stats
        read_only: true
        bind:
          create_host_path: false"
else
    export CRIT_LOCATIONS_MOUNT=""
    echo "WARNING: CRIT_LOCATIONS_DIR=$CRIT_LOCATIONS_DIR does not exist; critical-location source will be unavailable." >&2
fi

COMPOSE_GRAFANA_ADMIN_USER=$(compose_json_scalar "$GRAFANA_ADMIN_USER")
COMPOSE_GRAFANA_ADMIN_PASSWORD=$(compose_json_scalar "$GRAFANA_ADMIN_PASSWORD")
COMPOSE_CONTAINER_NODE_BINARY=$(compose_json_scalar "$CONTAINER_NODE_BINARY")
# Linux bridge containers do not resolve host.docker.internal unless the
# host-gateway mapping is declared on the client that performs the probe.
# shellcheck disable=SC2089
EXPORTER_EXTRA_HOSTS='    extra_hosts:
      - "host.docker.internal:host-gateway"'
export COMPOSE_GRAFANA_ADMIN_USER COMPOSE_GRAFANA_ADMIN_PASSWORD \
    COMPOSE_CONTAINER_NODE_BINARY NODE_BINARY_MOUNT NODE_MODE
# shellcheck disable=SC2090
export EXPORTER_EXTRA_HOSTS

# ---------------------------------------------------------------------------
# Render templates
# ---------------------------------------------------------------------------
mkdir -p docker prometheus

# Use a strict allow-list of variable names so unrelated `$foo` strings in
# the templates aren't accidentally expanded.
envsubst '${USER_ID} ${GROUP_ID} ${EXPORTER_VERSION}' \
    < docker/templates/Dockerfile.tmpl \
    > docker/Dockerfile

envsubst '${USER_ID} ${GROUP_ID} ${EXPORTER_VERSION} ${EXPORTER_CMD} ${COMPOSE_GRAFANA_ADMIN_USER} ${COMPOSE_GRAFANA_ADMIN_PASSWORD} ${GRAFANA_PORT} ${PROMETHEUS_RETENTION} ${COMPOSE_CONTAINER_NODE_BINARY} ${VOLUME_MOUNTS} ${NODE_BINARY_MOUNT} ${CRIT_LOCATIONS_MOUNT} ${EXTRA_VOLUMES} ${EXPORTER_NETWORK_BLOCK} ${EXPORTER_EXTRA_HOSTS} ${EXPORTER_PID_BLOCK} ${PROMETHEUS_EXTRA_HOSTS} ${EXPORTER_TARGET}' \
    < docker/templates/docker-compose.yaml.tmpl \
    > docker/docker-compose.yaml

envsubst '${CHAIN} ${NODE_LABEL} ${NODE_MODE} ${EXPORTER_TARGET}' \
    < prometheus/prometheus.yml.tmpl \
    > prometheus/prometheus.yml

# The rendered Compose file contains the Grafana bootstrap password. Keep it
# owner-readable only; it is already excluded from Git and the Docker context.
chmod 0600 docker/docker-compose.yaml

echo
echo "Generated:"
echo "  docker/Dockerfile"
echo "  docker/docker-compose.yaml"
echo "  prometheus/prometheus.yml"
echo
echo "Next:  cd docker && docker compose up -d --build"
