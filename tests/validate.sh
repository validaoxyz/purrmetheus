#!/usr/bin/env bash
# Validate the checked-in purrmetheus stack and, with --full, its pinned
# upstream release and runnable image.
set -euo pipefail

ROOT_DIR=$(cd "$(dirname "$0")/.." && pwd -P)
cd "$ROOT_DIR"
FULL=false
REQUIRE_DOCKER=${REQUIRE_DOCKER:-0}
VERIFY_RELEASE_ASSETS=${VERIFY_RELEASE_ASSETS:-1}
UPSTREAM_DIR=${UPSTREAM_DIR:-"$ROOT_DIR/../hyperliquid-exporter"}
case "${1:-}" in
    "") ;;
    --full) FULL=true ;;
    --require-docker) REQUIRE_DOCKER=1 ;;
    *) echo "usage: $0 [--full|--require-docker]" >&2; exit 2 ;;
esac
if [ "${2:-}" = "--require-docker" ]; then
    REQUIRE_DOCKER=1
elif [ -n "${2:-}" ]; then
    echo "usage: $0 [--full|--require-docker]" >&2
    exit 2
fi

TMP_ROOT=$(mktemp -d "${TMPDIR:-/tmp}/purrmetheus-validate.XXXXXX")
cleanup() { rm -rf -- "$TMP_ROOT"; }
trap cleanup EXIT
PASS_COUNT=0
SKIP_COUNT=0
pass() { PASS_COUNT=$((PASS_COUNT + 1)); printf 'PASS  %s\n' "$*"; }
skip() { SKIP_COUNT=$((SKIP_COUNT + 1)); printf 'SKIP  %s\n' "$*"; }
fail() { printf 'FAIL  %s\n' "$*" >&2; exit 1; }

for command_name in bash envsubst jq docker git curl tar python3; do
    command -v "$command_name" >/dev/null 2>&1 || fail "missing command: $command_name"
done
if command -v sha256sum >/dev/null 2>&1; then
    SHA256_TOOL=sha256sum
elif command -v shasum >/dev/null 2>&1; then
    SHA256_TOOL=shasum
else
    fail "missing SHA-256 utility (sha256sum or shasum)"
fi
docker compose version >/dev/null 2>"$TMP_ROOT/compose-version.err" \
    || fail "Docker Compose v2 plugin is unavailable"
pass "required tools and Docker Compose v2"

PROMTOOL_PATH=${PROMTOOL:-}
if [ -z "$PROMTOOL_PATH" ]; then
    for candidate in \
        "$(command -v promtool 2>/dev/null || true)" \
        /opt/homebrew/bin/promtool /usr/local/bin/promtool \
        /tmp/*/prometheus-*/promtool /tmp/*/promtool; do
        if [ -n "$candidate" ] && [ -x "$candidate" ]; then
            PROMTOOL_PATH=$candidate
            break
        fi
    done
fi
[ -n "$PROMTOOL_PATH" ] && [ -x "$PROMTOOL_PATH" ] \
    || fail "promtool not found; set PROMTOOL=/path/to/promtool"
pass "promtool: $PROMTOOL_PATH"

/bin/bash -n generate_config.sh || fail "generate_config.sh syntax"
pass "generate_config.sh syntax"
if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning generate_config.sh || fail "shellcheck"
    pass "shellcheck"
else
    skip "shellcheck is not installed"
fi
git diff --check || fail "whitespace errors in the worktree diff"
pass "git diff --check"

python3 - grafana/dashboards/hyperliquid.json <<'PY'
import json
import sys

path = sys.argv[1]

def unique_pairs(pairs):
    result = {}
    for key, value in pairs:
        if key in result:
            raise ValueError("duplicate JSON key: " + key)
        result[key] = value
    return result

with open(path, encoding="utf-8") as handle:
    dashboard = json.load(handle, object_pairs_hook=unique_pairs)

panels = []
def walk(value):
    if isinstance(value, dict):
        if isinstance(value.get("panels"), list):
            panels.extend(value["panels"])
        for child in value.values():
            walk(child)
    elif isinstance(value, list):
        for child in value:
            walk(child)

walk(dashboard)
ids = [p.get("id") for p in panels if isinstance(p, dict) and "id" in p]
if len(ids) != len(set(ids)):
    raise ValueError("dashboard panel IDs are not unique")
by_id = {p.get("id"): p for p in panels if isinstance(p, dict)}
for required in (14, 27, 44, 53, 54, 55, 63, 72, 77, 990):
    if required not in by_id:
        raise ValueError("missing required panel " + str(required))
if by_id[14].get("type") != "table" or "hl_software_version" not in by_id[14].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("software build panel is not a metadata table")
if "format" in by_id[14].get("targets", [{}])[0]:
    raise ValueError("software build panel must let Grafana infer the instant vector frame")
if by_id[990].get("type") != "table" or by_id[990].get("targets", [{}])[0].get("expr") != "hl_exporter_build_info":
    raise ValueError("exporter build panel is not a metadata table")
if "sum by(job, instance)" not in by_id[21].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("jailed-validator aggregation drops the target identity")
if "validator" not in by_id[27].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("signed-action panel does not retain validator identity")
if "reference_lag_populated" not in by_id[54].get("targets", [{}])[1].get("expr", ""):
    raise ValueError("reference lag panel is not presence-gated")
disk_expr = by_id[72].get("targets", [{}])[0].get("expr", "")
if "hl_node_disk_statfs_up" not in disk_expr or "hl_node_disk_total_bytes > 0" not in disk_expr:
    raise ValueError("disk panel is not guarded against stale or zero-capacity data")
if "snapshot_status" not in by_id[53].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("snapshot panel is not source-gated")
if "hl_validator_api_cache_stale" not in by_id[20].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("validator summary panels are not stale-cache gated")
if "hl_validator_api_cache_stale" not in by_id[25].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("validator stake table is not stale-cache gated")
if "source=\"node_state\"" not in by_id[63].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("persisted checkpoint panel is not source-gated")
if 'node_mode=\"host\"' not in by_id[80].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("TCP socket panel is not restricted to host PID/network mode")
if "sum by (job, instance, direction)" not in by_id[82].get("targets", [{}])[0].get("expr", ""):
    raise ValueError("traffic aggregation drops the target identity")

rows = [p for p in dashboard.get("panels", []) if isinstance(p, dict) and p.get("type") == "row"]
if len(rows) != 10 or any(p.get("panels") != [] for p in rows):
    raise ValueError("dashboard rows must remain flat and have no nested panels")
if any(isinstance(p, dict) and isinstance(p.get("panels"), list) and p.get("type") != "row"
       for p in dashboard.get("panels", [])):
    raise ValueError("non-row dashboard objects must not contain nested panels")

# Grafana stores children of collapsed rows with global grid coordinates.  A
# following top-level row must begin after every child rectangle, or Grafana
# hides the later row and its panels during import. Panels in one section may
# intentionally share a y coordinate, so the cursor advances at row boundaries.
cursor = 0
for panel in dashboard.get("panels", []):
    if not isinstance(panel, dict) or not isinstance(panel.get("gridPos"), dict):
        continue
    grid = panel["gridPos"]
    y = grid.get("y")
    h = grid.get("h")
    if not isinstance(y, (int, float)) or not isinstance(h, (int, float)):
        raise ValueError("dashboard panel has invalid grid coordinates")
    if y < cursor:
        raise ValueError(f"top-level panel {panel.get('id')} overlaps prior dashboard row content")
    if panel.get("type") != "row":
        continue
    cursor = max(cursor, y + h)
    if panel.get("collapsed"):
        for child in panel.get("panels", []):
            child_grid = child.get("gridPos", {})
            child_y = child_grid.get("y")
            child_h = child_grid.get("h")
            if not isinstance(child_y, (int, float)) or not isinstance(child_h, (int, float)):
                raise ValueError(f"collapsed row {panel.get('id')} has invalid child coordinates")
            cursor = max(cursor, child_y + child_h)
for panel in panels:
    for target in panel.get("targets", []) if isinstance(panel, dict) else []:
        if not target.get("expr"):
            raise ValueError("dashboard target has no expression")
for name in ("hl_consensus_validator_count", "hl_consensus_qc_participation_rate",
             "hl_evm_account_count", "hl_exporter_monitor_last_tick_seconds"):
    if name in open(path, encoding="utf-8").read():
        raise ValueError("obsolete metric remains in dashboard: " + name)
PY
pass "dashboard JSON structure, IDs, and v4 metric guards"

JQ_EXPRS="$TMP_ROOT/dashboard-expressions"
jq -r '.. | objects | .targets? // empty | .[]? | .expr? // empty' \
    grafana/dashboards/hyperliquid.json > "$JQ_EXPRS" \
    || fail "extracting dashboard expressions"
DASHBOARD_RULES="$TMP_ROOT/dashboard-rules.yml"
{
    printf 'groups:\n'
    expression_number=0
    while IFS= read -r expression; do
        [ -n "$expression" ] || continue
        expression_number=$((expression_number + 1))
        expression=${expression//\$__interval/5m}
        expression=${expression//\$__rate_interval/5m}
        quoted_expression=$(jq -Rn --arg value "$expression" '$value')
        printf '  - name: dashboard_%03d\n    rules:\n      - record: purrmetheus_dashboard_%03d\n        expr: %s\n' \
            "$expression_number" "$expression_number" "$quoted_expression"
    done < "$JQ_EXPRS"
} > "$DASHBOARD_RULES"
[ "$expression_number" -gt 0 ] || fail "dashboard has no PromQL targets"
"$PROMTOOL_PATH" check rules "$DASHBOARD_RULES" >/dev/null \
    || fail "dashboard PromQL expressions"
pass "dashboard PromQL expressions ($expression_number targets)"

"$PROMTOOL_PATH" check rules prometheus/alerts.yml >/dev/null \
    || fail "alert rule syntax"
"$PROMTOOL_PATH" test rules tests/prometheus/alerts.test.yml >/dev/null \
    || fail "alert rule fixtures"
EXPECTED_ALERTS="$TMP_ROOT/expected-alerts"
ACTUAL_ALERTS="$TMP_ROOT/actual-alerts"
printf '%s\n' \
    HyperliquidExporterDown HyperliquidExporterNotReady \
    HyperliquidNodeProcessDown HyperliquidVisorProcessDown NodeNotInSync \
    HyperliquidSnapshotEvidenceStale DiskFillingUp DiskFillingUpWarning BugEmitted \
    MaxPeersReached BlockApplySlow HyperliquidCoreHeightStalled \
    HyperliquidCoreHeightSlow PersistedABCIHeightGap \
    HyperliquidEVMTxReceiptCountMismatch HyperliquidEVMParseErrors \
    HyperliquidExporterMonitorExited HyperliquidExporterMonitorPanicked \
    HyperliquidExporterErrorReportsDropped HyperliquidExporterSourceReadOrSchemaFailed \
    HyperliquidUnknownActionTypeObserved SoftwareOutdated \
    HyperliquidValidatorAPIStaleFallback HyperliquidTmpMaterialStale | sort > "$EXPECTED_ALERTS"
sed -n 's/^[[:space:]]*- alert: //p' prometheus/alerts.yml | sort > "$ACTUAL_ALERTS"
cmp -s "$EXPECTED_ALERTS" "$ACTUAL_ALERTS" || fail "alert inventory differs from fixture"
if grep -Eq 'hl_consensus_validator_count|hl_consensus_qc_participation_rate|hl_evm_account_count|hl_exporter_monitor_last_tick_seconds|hl_p2p_tcp_connections_total|hl_p2p_peer_history_total' prometheus/alerts.yml; then
    fail "obsolete metric remains in alerts"
fi
pass "Prometheus v4.0.7 alert rules and fixtures"

copy_case() {
    local case_name=$1
    local case_dir="$TMP_ROOT/$case_name"
    mkdir -p "$case_dir/docker/templates" "$case_dir/prometheus" \
        "$case_dir/node" "$case_dir/bin" "$case_dir/visor" "$case_dir/crit"
    cp generate_config.sh "$case_dir/"
    cp docker/templates/*.tmpl "$case_dir/docker/templates/"
    cp prometheus/prometheus.yml.tmpl "$case_dir/prometheus/"
    cp prometheus/alerts.yml "$case_dir/prometheus/"
    cp .dockerignore "$case_dir/"
    printf '%s\n' '#!/bin/sh' 'exit 0' > "$case_dir/bin/hl-node"
    chmod 0755 "$case_dir/bin/hl-node"
    printf '%s\n' "$case_dir"
}
write_env() {
    local case_dir=$1
    shift
    printf '%s\n' "$@" > "$case_dir/.env"
}
run_generator() {
    local case_dir=$1
    (cd "$case_dir" && /bin/bash generate_config.sh >stdout.log 2>stderr.log)
}
expect_generator_failure() {
    local case_dir=$1
    local label=$2
    if run_generator "$case_dir"; then
        fail "$label unexpectedly succeeded"
    fi
    pass "$label rejected"
}
compose_json() {
    local case_dir=$1
    (cd "$case_dir" && docker compose -f docker/docker-compose.yaml config --format json >compose.json 2>compose.stderr)
    printf '%s/compose.json\n' "$case_dir"
}
check_generated_prometheus() {
    local case_dir=$1
    local config_path="$case_dir/prometheus/prometheus.yml"
    local local_config="$case_dir/prometheus/prometheus.local.yml"
    sed "s#- /etc/prometheus/alerts.yml#- $case_dir/prometheus/alerts.yml#" \
        "$config_path" > "$local_config"
    "$PROMTOOL_PATH" check config "$local_config" >/dev/null \
        || fail "generated Prometheus config ($case_dir)"
}
mode_of() {
    if stat -f '%Lp' "$1" >/dev/null 2>&1; then stat -f '%Lp' "$1"; else stat -c '%a' "$1"; fi
}

HOST_CASE=$(copy_case generator-host)
write_env "$HOST_CASE" \
    'USE_DOCKER=false' "NODE_HOME=$HOST_CASE/node" \
    "NODE_BINARY=$HOST_CASE/bin/hl-node" "CRIT_LOCATIONS_DIR=$HOST_CASE/crit" \
    'CHAIN="  MAINNET  "' 'EXPORTER_EXTRA_FLAGS=--evm-metrics'
run_generator "$HOST_CASE" || fail "host generator"
check_generated_prometheus "$HOST_CASE"
HOST_COMPOSE=$(compose_json "$HOST_CASE") || fail "host Compose normalization"
jq -e '
    .services.hl_exporter.network_mode == "host" and
    .services.hl_exporter.pid == "host" and
    .services.hl_exporter.environment.NODE_BINARY == "/home/hluser/bin/hl-node" and
    ([.services.hl_exporter.volumes[]?.source // ""] | index("../.env") == null)
' "$HOST_COMPOSE" >/dev/null || fail "host Compose contract"
jq -e '
    ([.services.node_exporter.volumes[]? | select(.target == "/host/root") | .read_only] | any)
' "$HOST_COMPOSE" >/dev/null || fail "node_exporter root mount is not read-only"
! grep -F '/:/host/root:ro,rslave' "$HOST_CASE/docker/docker-compose.yaml" >/dev/null \
    || fail "node_exporter root mount still requires unsupported propagation"
bind_false_count=$(grep -Ec '^          create_host_path: false$' "$HOST_CASE/docker/docker-compose.yaml" || true)
[ "$bind_false_count" -ge 3 ] || fail "host bind mounts may create missing source paths"
grep -F 'node_mode: '\''host'\''' "$HOST_CASE/prometheus/prometheus.yml" >/dev/null \
    || fail "host Prometheus node_mode label"
grep -F "'host.docker.internal:8086'" "$HOST_CASE/prometheus/prometheus.yml" >/dev/null \
    || fail "host Prometheus target"
[ "$(mode_of "$HOST_CASE/docker/docker-compose.yaml")" = 600 ] \
    || fail "generated Compose permissions"
grep -F 'host.docker.internal:host-gateway' "$HOST_CASE/docker/docker-compose.yaml" >/dev/null \
    || fail "host exporter host-gateway mapping"
pass "host generator, labels, mounts, target, and secret-file mode"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    "BINARY_HOME=$HOST_CASE/visor" 'EXPORTER_EXTRA_FLAGS='
run_generator "$HOST_CASE" || fail "separate BINARY_HOME generator"
check_generated_prometheus "$HOST_CASE"
SEPARATE_BINARY_COMPOSE=$(compose_json "$HOST_CASE") || fail "separate BINARY_HOME Compose normalization"
jq -e '
    .services.hl_exporter.environment.NODE_BINARY == "/home/hluser/node-bin/hl-node" and
    ([.services.hl_exporter.volumes[]?.target // ""] | index("/home/hluser/bin") != null) and
    ([.services.hl_exporter.volumes[]?.target // ""] | index("/home/hluser/node-bin") != null)
' "$SEPARATE_BINARY_COMPOSE" >/dev/null || fail "separate BINARY_HOME was not mounted independently"
pass "separate hl-visor directory is preserved for v4 update checks"

DOCKER_CASE=$(copy_case generator-docker)
write_env "$DOCKER_CASE" \
    'USE_DOCKER=true' 'CHAIN=" testnet "' "CRIT_LOCATIONS_DIR=$DOCKER_CASE/crit" \
    'EXPORTER_EXTRA_FLAGS=--evm-metrics'
run_generator "$DOCKER_CASE" || fail "Dockerized-node generator"
check_generated_prometheus "$DOCKER_CASE"
DOCKER_COMPOSE=$(compose_json "$DOCKER_CASE") || fail "Docker Compose normalization"
jq -e '
    (.services.hl_exporter | has("pid") | not) and
    (.services.hl_exporter.networks | has("purrmetheus")) and
    .services.hl_exporter.environment.NODE_BINARY == "/home/hluser/bin/hl-node" and
    .volumes."hyperliquid_hl-data".external == true and
    ([.services.hl_exporter.volumes[]?.target // ""] | index("/home/hluser/hl/data") != null)
' "$DOCKER_COMPOSE" >/dev/null || fail "Dockerized-node Compose contract"
grep -F 'node_mode: '\''docker'\''' "$DOCKER_CASE/prometheus/prometheus.yml" >/dev/null \
    || fail "Docker Prometheus node_mode label"
grep -F "'hl_exporter:8086'" "$DOCKER_CASE/prometheus/prometheus.yml" >/dev/null \
    || fail "Docker Prometheus target"
grep -F 'host.docker.internal:host-gateway' "$DOCKER_CASE/docker/docker-compose.yaml" >/dev/null \
    || fail "Docker exporter host-gateway mapping"
pass "Dockerized-node generator, reduced profile, and external volume"

write_env "$DOCKER_CASE" 'USE_DOCKER=true' \
    'INFO_ENDPOINT_URL=http://host.docker.internal:3001/info' \
    'EXPORTER_EXTRA_FLAGS=--probe-info-endpoint'
run_generator "$DOCKER_CASE" || fail "Docker probe configuration"
check_generated_prometheus "$DOCKER_CASE"
DOCKER_PROBE_COMPOSE=$(compose_json "$DOCKER_CASE") || fail "Docker probe Compose normalization"
jq -e '.services.hl_exporter.command | index("--info-endpoint-url=http://host.docker.internal:3001/info") != null' \
    "$DOCKER_PROBE_COMPOSE" >/dev/null || fail "Docker probe URL was not rendered"
pass "Docker probe uses an explicit non-loopback info endpoint"

write_env "$DOCKER_CASE" 'USE_DOCKER=true' 'EXPORTER_EXTRA_FLAGS=--probe-info-endpoint'
expect_generator_failure "$DOCKER_CASE" "Docker probe without URL"
for loopback_url in \
    'http://127.0.0.1:3001/info' \
    'http://127.1:3001/info' \
    'http://0.0.0.0:3001/info' \
    'http://localhost:3001/info' \
    'http://localhost.:3001/info' \
    'http://[::ffff:127.0.0.1]:3001/info' \
    'http://[::1]:3001/info'; do
    write_env "$DOCKER_CASE" 'USE_DOCKER=true' "INFO_ENDPOINT_URL=$loopback_url" \
        'EXPORTER_EXTRA_FLAGS=--probe-info-endpoint'
    expect_generator_failure "$DOCKER_CASE" "Docker loopback probe ($loopback_url)"
done

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'CRIT_LOCATIONS_DIR=' 'EXPORTER_EXTRA_FLAGS=   '
run_generator "$HOST_CASE" || fail "empty extra flags"
HOST_EMPTY_COMPOSE=$(compose_json "$HOST_CASE") || fail "empty flags Compose normalization"
jq -e '.services.hl_exporter.command == ["start", "--chain=mainnet"]' \
    "$HOST_EMPTY_COMPOSE" >/dev/null || fail "empty flags changed the exporter command"
pass "empty and whitespace-only flags on Bash 3.2"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'SKIP_VERSION_CHECK=true' 'SKIP_UPDATE_CHECK=true' 'EXPORTER_EXTRA_FLAGS='
run_generator "$HOST_CASE" || fail "host skip-check toggles"
HOST_SKIP_COMPOSE=$(compose_json "$HOST_CASE") || fail "host skip-check Compose normalization"
jq -e '.services.hl_exporter.command == ["start", "--chain=mainnet", "--skip-version-check", "--skip-update-check"]' \
    "$HOST_SKIP_COMPOSE" >/dev/null || fail "host skip-check toggles were not rendered"
pass "host binary-check toggles are rendered independently"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'SKIP_VERSION_CHECK=maybe'
expect_generator_failure "$HOST_CASE" "invalid skip-check boolean"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'CHAIN=TESTNET' 'EXPORTER_EXTRA_FLAGS=--probe-info-endpoint=false'
run_generator "$HOST_CASE" || fail "chain normalization and false probe flag"
compose_json "$HOST_CASE" >/dev/null || fail "normalized chain Compose"
grep -F 'chain: '\''testnet'\''' "$HOST_CASE/prometheus/prometheus.yml" >/dev/null \
    || fail "chain was not normalized"
pass "case-insensitive chain normalization and bool flag aliases"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    "GRAFANA_ADMIN_PASSWORD='pa\$\$word'" \
    "EXPORTER_EXTRA_FLAGS='--contract-metrics=foo\$bar'"
run_generator "$HOST_CASE" || fail "special dollar values"
SPECIAL_DOLLAR_COMPOSE=$(compose_json "$HOST_CASE") \
    || fail "special dollar Compose normalization"
jq -e '
    .services.grafana.environment.GF_SECURITY_ADMIN_PASSWORD == "pa$$$$word" and
    (.services.hl_exporter.command | index("--contract-metrics=foo$$bar") != null)
' "$SPECIAL_DOLLAR_COMPOSE" >/dev/null \
    || fail "Compose did not preserve escaped dollar values after normalization"
pass "dollar-sign credentials and option values stay structurally escaped"

write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    "CRIT_LOCATIONS_DIR=$HOST_CASE/crit" 'EXPORTER_EXTRA_FLAGS=--evm-metrics'
run_generator "$HOST_CASE" || fail "critical-location baseline"
grep -E 'CRIT_LOCATIONS_DIR is mounted.*requires --extended-metrics' \
    "$HOST_CASE/stderr.log" >/dev/null || fail "missing extended-metrics warning"
write_env "$HOST_CASE" \
    "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    "CRIT_LOCATIONS_DIR=$HOST_CASE/crit" 'EXPORTER_EXTRA_FLAGS=--extended-metrics'
run_generator "$HOST_CASE" || fail "critical-location extended profile"
! grep -q 'requires --extended-metrics' "$HOST_CASE/stderr.log" \
    || fail "extended-metrics warning remained enabled"
pass "critical-location mount is explicit about its extended-metrics dependency"

write_env "$HOST_CASE" 'NODE_HOME=relative' "NODE_BINARY=$HOST_CASE/bin/hl-node"
expect_generator_failure "$HOST_CASE" "relative NODE_HOME"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" 'NODE_BINARY=relative'
expect_generator_failure "$HOST_CASE" "relative NODE_BINARY"
write_env "$HOST_CASE" 'NODE_HOME=/' "NODE_BINARY=$HOST_CASE/bin/hl-node"
expect_generator_failure "$HOST_CASE" "root NODE_HOME"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" 'NODE_BINARY=/hl-node'
expect_generator_failure "$HOST_CASE" "root binary directory"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/missing" "NODE_BINARY=$HOST_CASE/bin/hl-node"
expect_generator_failure "$HOST_CASE" "missing NODE_HOME"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/missing"
expect_generator_failure "$HOST_CASE" "missing NODE_BINARY"
for invalid_port in 08 09 0001; do
    write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" \
        "NODE_BINARY=$HOST_CASE/bin/hl-node" "GRAFANA_PORT=$invalid_port"
    expect_generator_failure "$HOST_CASE" "invalid port $invalid_port"
done
ln -sf hl-node "$HOST_CASE/bin/hl-node-link"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node-link"
expect_generator_failure "$HOST_CASE" "symlinked NODE_BINARY"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    $'GRAFANA_ADMIN_PASSWORD="line\nbreak"'
expect_generator_failure "$HOST_CASE" "multiline Grafana password"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'EXPORTER_UID=0'
expect_generator_failure "$HOST_CASE" "root exporter UID"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'EXPORTER_EXTRA_FLAGS=--probe-info-endpoint=yes'
expect_generator_failure "$HOST_CASE" "invalid boolean flag"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    'EXPORTER_EXTRA_FLAGS=start'
expect_generator_failure "$HOST_CASE" "positional extra flag"
ln -sf / "$HOST_CASE/crit-root"
write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
    "CRIT_LOCATIONS_DIR=$HOST_CASE/crit-root" 'EXPORTER_EXTRA_FLAGS=--extended-metrics'
expect_generator_failure "$HOST_CASE" "critical-location path resolving to root"
for retired_flag in \
    --evm --enable-otlp --enable-prom --disable-prom --evm-block-type-metrics \
    --enable-contract-metrics --enable-replica-metrics; do
    write_env "$HOST_CASE" "NODE_HOME=$HOST_CASE/node" "NODE_BINARY=$HOST_CASE/bin/hl-node" \
        "EXPORTER_EXTRA_FLAGS=$retired_flag"
    expect_generator_failure "$HOST_CASE" "retired flag $retired_flag"
done
pass "invalid paths, ports, symlinks, credentials, and flags fail closed"

grep -Fx '*' .dockerignore >/dev/null || fail ".dockerignore is not restrictive"
! grep -Fx '!docker/' .dockerignore >/dev/null \
    || fail ".dockerignore re-includes the whole docker directory"
grep -Fx '!docker/Dockerfile' .dockerignore >/dev/null || fail ".dockerignore omits Dockerfile allowlist"
! grep -Eq '^!docker/(docker-compose\.yaml|templates/)' .dockerignore \
    || fail ".dockerignore re-includes generated config or templates"
pass "Docker context policy excludes local configuration and repository data"

if [ "$FULL" != true ]; then
    pass "standard validation complete"
    printf '\n%d checks passed; %d skipped.\n' "$PASS_COUNT" "$SKIP_COUNT"
    exit 0
fi

release_version=$(sed -n 's/^EXPORTER_VERSION=//p' .env.sample | head -1)
[ -n "$release_version" ] || fail "could not read EXPORTER_VERSION from .env.sample"
release_json="$TMP_ROOT/release.json"
if command -v gh >/dev/null 2>&1 && gh api repos/validaoxyz/hyperliquid-exporter/releases/latest > "$release_json" 2>"$TMP_ROOT/gh.err"; then
    pass "queried the upstream release API with gh"
elif curl -fsSL --retry 3 -H 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/validaoxyz/hyperliquid-exporter/releases/latest > "$release_json" 2>"$TMP_ROOT/curl.err"; then
    pass "queried the upstream release API with curl"
else
    fail "unable to query the upstream release API"
fi
latest_tag=$(jq -er '.tag_name' "$release_json") || fail "malformed upstream release JSON"
[ "$latest_tag" = "$release_version" ] \
    || fail "sample pins $release_version but upstream latest is $latest_tag"
for architecture in amd64 arm64; do
    asset_name="hl_exporter_linux_${architecture}"
    asset_url=$(jq -er --arg name "$asset_name" \
        '.assets[] | select(.name == $name) | .browser_download_url' "$release_json") \
        || fail "missing upstream asset $asset_name"
    asset_digest=$(jq -r --arg name "$asset_name" \
        '.assets[] | select(.name == $name) | (.digest // "")' "$release_json" | sed 's/^sha256://')
    if [ -z "$asset_digest" ]; then
        sums="$TMP_ROOT/SHA256SUMS-$architecture"
        curl -fsSL --retry 3 \
            "https://github.com/validaoxyz/hyperliquid-exporter/releases/download/${latest_tag}/SHA256SUMS" > "$sums" \
            || fail "missing SHA256SUMS for $latest_tag"
        asset_digest=$(awk -v name="$asset_name" '$2 == name || $2 == "./" name { print $1; exit }' "$sums")
    fi
    printf '%s\n' "$asset_digest" | grep -Eq '^[0-9a-fA-F]{64}$' \
        || fail "invalid digest for $asset_name"
    if [ "$VERIFY_RELEASE_ASSETS" = 1 ]; then
        asset_file="$TMP_ROOT/$asset_name"
        curl -fsSL --retry 3 "$asset_url" -o "$asset_file" \
            || fail "download failed for $asset_name"
        if [ "$SHA256_TOOL" = sha256sum ]; then
            actual_digest=$(sha256sum "$asset_file" | awk '{print $1}')
        else
            actual_digest=$(shasum -a 256 "$asset_file" | awk '{print $1}')
        fi
        [ "$actual_digest" = "$asset_digest" ] \
            || fail "digest mismatch for $asset_name"
    fi
    pass "upstream $asset_name SHA-256 $asset_digest"
done

# Resolve the exact tag commit independently of the optional sibling checkout.
# A local checkout is useful for speed, but it must match the live tag; when it
# is absent, fetch the same tag archive instead of silently skipping upstream
# compatibility tests.
upstream_repo=https://github.com/validaoxyz/hyperliquid-exporter.git
upstream_refs=$(git ls-remote --tags "$upstream_repo" \
    "refs/tags/${release_version}" "refs/tags/${release_version}^{}" 2>"$TMP_ROOT/upstream-refs.err") \
    || fail "unable to resolve upstream tag $release_version"
upstream_commit=$(printf '%s\n' "$upstream_refs" | awk -v tag="$release_version" '
    $2 == "refs/tags/" tag "^{}" { print $1; found=1; exit }
    $2 == "refs/tags/" tag { fallback=$1 }
    END { if (!found && fallback != "") print fallback }
')
printf '%s\n' "$upstream_commit" | grep -Eq '^[0-9a-fA-F]{40}$' \
    || fail "upstream tag $release_version has no peeled commit"
upstream_tree="$TMP_ROOT/upstream-$release_version"
mkdir -p "$upstream_tree"
if [ -d "$UPSTREAM_DIR/.git" ]; then
    local_upstream_commit=$(git -C "$UPSTREAM_DIR" rev-parse "${release_version}^{commit}") \
        || fail "upstream checkout has no $release_version tag"
    [ "$local_upstream_commit" = "$upstream_commit" ] \
        || fail "upstream checkout $local_upstream_commit does not match live tag $upstream_commit"
    git -C "$UPSTREAM_DIR" archive "$release_version" | tar -x -C "$upstream_tree"
    pass "using local upstream $release_version checkout ($upstream_commit)"
else
    upstream_archive="$TMP_ROOT/upstream-$release_version.tar.gz"
    curl -fsSL --retry 3 \
        "https://github.com/validaoxyz/hyperliquid-exporter/archive/refs/tags/${release_version}.tar.gz" \
        -o "$upstream_archive" \
        || fail "unable to download upstream $release_version source archive"
    tar -xzf "$upstream_archive" --strip-components=1 -C "$upstream_tree" \
        || fail "unable to unpack upstream $release_version source archive"
    pass "downloaded upstream $release_version source archive ($upstream_commit)"
fi
[ -f "$upstream_tree/go.mod" ] || fail "upstream source archive is missing go.mod"
command -v go >/dev/null 2>&1 || fail "missing command: go (required by --full upstream checks)"
upstream_log="$TMP_ROOT/upstream-tests.log"
if ! (cd "$upstream_tree" && GOTOOLCHAIN=auto go test ./... >"$upstream_log" 2>&1); then
    tail -80 "$upstream_log" >&2
    fail "upstream go test ./... ($upstream_commit)"
fi
pass "upstream $release_version go test ./... ($upstream_commit)"
if ! (cd "$upstream_tree" && GOTOOLCHAIN=auto go test -race ./... >"$TMP_ROOT/upstream-race.log" 2>&1); then
    tail -80 "$TMP_ROOT/upstream-race.log" >&2
    fail "upstream race tests"
fi
pass "upstream race tests"
if ! (cd "$upstream_tree" && GOTOOLCHAIN=auto go vet ./... >"$TMP_ROOT/upstream-vet.log" 2>&1); then
    tail -80 "$TMP_ROOT/upstream-vet.log" >&2
    fail "upstream go vet"
fi
pass "upstream go vet"
for architecture in amd64 arm64; do
    if ! (cd "$upstream_tree" && CGO_ENABLED=0 GOOS=linux GOARCH="$architecture" \
        GOTOOLCHAIN=auto go build -trimpath -ldflags='-s -w' \
        -o "$TMP_ROOT/hl_exporter_linux_$architecture" ./cmd/hl-exporter >"$TMP_ROOT/build-$architecture.log" 2>&1); then
        tail -80 "$TMP_ROOT/build-$architecture.log" >&2
        fail "upstream linux/$architecture build"
    fi
    pass "upstream linux/$architecture static build"
done

docker_available=false
if docker info >/dev/null 2>"$TMP_ROOT/docker-info.err"; then
    docker_available=true
fi
if [ "$docker_available" != true ]; then
    if [ "$REQUIRE_DOCKER" = 1 ]; then
        cat "$TMP_ROOT/docker-info.err" >&2
        fail "Docker daemon is unavailable"
    fi
    skip "Docker daemon unavailable; image/runtime smoke was not run"
else
    image_tag_base="purrmetheus-validation:$$"
    platform_name=$(uname -m | sed 's/x86_64/amd64/; s/aarch64/arm64/; s/arm64/arm64/')
    image_tag=""
    for image_platform in amd64 arm64; do
        candidate_tag="${image_tag_base}-${image_platform}"
        docker build --pull --platform "linux/$image_platform" \
            --build-arg "USER_ID=$(id -u)" --build-arg "GROUP_ID=$(id -g)" \
            --build-arg "EXPORTER_VERSION=$release_version" \
            -f "$HOST_CASE/docker/Dockerfile" -t "$candidate_tag" "$HOST_CASE" >"$TMP_ROOT/docker-build-$image_platform.log" 2>&1 \
            || { tail -100 "$TMP_ROOT/docker-build-$image_platform.log" >&2; docker image rm "$candidate_tag" >/dev/null 2>&1 || true; fail "Docker linux/$image_platform image build"; }
        reported_arch=$(docker image inspect --format '{{.Architecture}}' "$candidate_tag")
        [ "$reported_arch" = "$image_platform" ] \
            || { docker image rm "$candidate_tag" >/dev/null 2>&1 || true; fail "Docker image architecture ($reported_arch) does not match requested $image_platform"; }
        expected_elf_machine=3e00
        [ "$image_platform" = arm64 ] && expected_elf_machine=b700
        image_elf_machine=$(docker run --platform "linux/$image_platform" --rm --entrypoint /bin/sh "$candidate_tag" -c \
            'od -An -tx1 -j18 -N2 /usr/local/bin/hl_exporter | tr -d "[:space:]"')
        [ "$image_elf_machine" = "$expected_elf_machine" ] \
            || { docker image rm "$candidate_tag" >/dev/null 2>&1 || true; fail "Docker exporter ELF architecture ($image_elf_machine) does not match requested $image_platform"; }
        pass "Docker linux/$image_platform image build, architecture, and restricted context"
        if [ "$image_platform" = "$platform_name" ]; then
            image_tag=$candidate_tag
        fi
    done
    [ -n "$image_tag" ] || fail "host architecture is not amd64 or arm64"
    container_name="purrmetheus-validation-$$"
    # Let Docker choose an unused host port.  A fixed port made the required
    # runtime gate fail when an operator's exporter or another test already
    # occupied it, before the image had a chance to start.
    if ! docker run -d --name "$container_name" -p 127.0.0.1::8086 "$image_tag" \
        start --chain=mainnet --skip-version-check --skip-update-check \
        --replica-metrics --evm-metrics --contract-metrics --extended-metrics \
        --per-peer-metrics >"$TMP_ROOT/container-id"; then
        docker rm -f "$container_name" >/dev/null 2>&1 || true
        docker image rm "${image_tag_base}-amd64" "${image_tag_base}-arm64" >/dev/null 2>&1 || true
        fail "Docker exporter container start"
    fi
    [ "$(docker inspect --format '{{.Config.User}}' "$container_name")" = "$(id -u):$(id -g)" ] \
        || { docker logs "$container_name" >&2 || true; docker rm -f "$container_name" >/dev/null 2>&1 || true; docker image rm "${image_tag_base}-amd64" "${image_tag_base}-arm64" >/dev/null 2>&1 || true; fail "Docker exporter did not run as the requested non-root user"; }
    mapped_port=$(docker port "$container_name" 8086/tcp | awk -F: 'NR == 1 { print $NF }')
    [[ "$mapped_port" =~ ^[0-9]+$ ]] \
        || { docker logs "$container_name" >&2 || true; docker rm -f "$container_name" >/dev/null 2>&1 || true; docker image rm "${image_tag_base}-amd64" "${image_tag_base}-arm64" >/dev/null 2>&1 || true; fail "Docker exporter ephemeral port mapping"; }
    container_ok=false
    attempts=0
    while [ "$attempts" -lt 60 ]; do
        attempts=$((attempts + 1))
        metrics_file="$TMP_ROOT/container.metrics"
        if curl -fsS "http://127.0.0.1:${mapped_port}/livez" >/dev/null 2>&1 && \
            curl -fsS "http://127.0.0.1:${mapped_port}/readyz" >/dev/null 2>&1 && \
            curl -fsS "http://127.0.0.1:${mapped_port}/metrics" -o "$metrics_file" && \
            grep -Eq 'hl_exporter_ready' "$metrics_file" && \
            grep -Eq 'hl_exporter_source_enabled' "$metrics_file" && \
            grep -Eq '^hl_evm_' "$metrics_file" && \
            grep -Eq '^hl_replica_' "$metrics_file"; then
            container_ok=true
            break
        fi
        sleep 1
    done
    docker logs "$container_name" >"$TMP_ROOT/container.log" 2>&1 || true
    docker rm -f "$container_name" >/dev/null 2>&1 || true
    docker image rm "${image_tag_base}-amd64" "${image_tag_base}-arm64" >/dev/null 2>&1 || true
    [ "$container_ok" = true ] || { tail -100 "$TMP_ROOT/container.log" >&2; fail "Docker exporter runtime smoke"; }
    pass "Docker exporter non-root all-profile /livez, /readyz, and /metrics runtime smoke (ephemeral port)"
fi

pass "full validation complete"
printf '\n%d checks passed; %d skipped.\n' "$PASS_COUNT" "$SKIP_COUNT"
