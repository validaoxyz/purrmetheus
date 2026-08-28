```
                                ██████╗ ██╗   ██╗██████╗ ██████╗
                                ██╔══██╗██║   ██║██╔══██╗██╔══██╗
                                ██████╔╝██║   ██║██████╔╝██████╔╝
                                ██╔═══╝ ██║   ██║██╔══██╗██╔══██╗
                                ██║     ╚██████╔╝██║  ██║██║  ██║
                                ╚═╝      ╚═════╝ ╚═╝  ╚═╝╚═╝  ╚═╝

                   ███╗   ███╗███████╗████████╗██╗  ██╗███████╗██╗   ██╗███████╗
                   ████╗ ████║██╔════╝╚══██╔══╝██║  ██║██╔════╝██║   ██║██╔════╝
                   ██╔████╔██║█████╗     ██║   ███████║█████╗  ██║   ██║███████╗
                   ██║╚██╔╝██║██╔══╝     ██║   ██╔══██║██╔══╝  ██║   ██║╚════██║
                   ██║ ╚═╝ ██║███████╗   ██║   ██║  ██║███████╗╚██████╔╝███████║
                   ╚═╝     ╚═╝╚══════╝   ╚═╝   ╚═╝  ╚═╝╚══════╝ ╚═════╝ ╚══════╝

                                 ;,_            ,
                                _uP~"b          d"u,
                               dP'   "b       ,d"  "o
                              d"    , `b     d"'    "b
                             l] [    " `l,  d"       lb
                             Ol ?     "  "b`"=uoqo,_  "l
                           ,dBb "b        "b,    `"~~TObup,_
                         ,d" (db.`"         ""     "tbc,_ `~"Yuu,_
                       .d" l`T'  '=                      ~     `""Yu,
                     ,dO` gP,                           `u,   b,_  "b7
                    d?' ,d" l,                           `"b,_ `~b  "1
                  ,8i' dl   `l                 ,ggQOV",dbgq,._"  `l  lb
                 .df' (O,    "             ,ggQY"~  , @@@@@d"bd~  `b "1
                .df'   `"           -=@QgpOY""     (b  @@@@P db    `Lp"b,
               .d(                  _               "ko "=d_,Q`  ,_  "  "b,
               Ql         .         `"qo,._          "tQo,_`""bo ;tb,    `"b,
               qQ         |L           ~"QQQgggc,_.,dObc,opooO  `"~~";.   __,7,
               qp         t\io,_           `~"TOOggQV""""        _,dg,_ =PIQHib.
               `qp        `Q["tQQQo,_                          ,pl{QOP"'   7AFR`
                 `         `tb  '""tQQQg,_             p" "b   `       .;-.`Vl'
                            "Yb      `"tQOOo,__    _,edb    ` .__   /`/'|  |b;=;.__
                                          `"tQQQOOOOP""`"\QV;qQObob"`-._`\_~~-._
                                               """"    ._        /   | |oP"\_   ~\ ~\_~\
                                                       `~"\ic,qggddOOP"|  |  ~\   `\~-._
                                                         ,qP`"""|"   | `\ `;   `\   `\
                                              _        _,p"     |    |   `\`;    |    |
                                              "boo,._dP"       `\_  `\    `\|   `\   ;
                                                `"7tY~'            `\  `\    `|_   |
                                                                     `~\  |
```

One-command monitoring stack for [Hyperliquid](https://hyperliquid.xyz) nodes: Prometheus, Grafana,
and [hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter) v4.0.7, preconfigured
with a dashboard and alert rules. In host-node mode, run it on the same Linux host as your
`hl-visor`/`hl-node` process; the exporter tails local logs and walks `NODE_HOME`.

Components:

- **hyperliquid-exporter v4.0.7**: metrics source
- **Prometheus**: on-disk retention, alert evaluation, and guarded rules for liveness, sync, disk, consensus, EVM, P2P, and exporter health
- **Grafana**: auto-provisioned v4 dashboard (HyperCore, consensus/validators, visor sync, HyperEVM, node health, P2P, latency)
- **node_exporter**: host `/proc`, `/sys`, and `/` mounted for host metrics

## Requirements

- Docker Engine ≥ 24 with the Compose plugin
- `envsubst` (`apt install gettext-base` / `brew install gettext`)
- `jq` (`apt install jq` / `brew install jq`)
- A Hyperliquid node running on the same host

The exporter release assets are Linux binaries for `amd64` and `arm64`. The
host-node Compose profile uses the host PID and network namespaces so Linux
process, TCP, and default `--serve-info` monitors inspect a host-installed
node. Prometheus reaches that host-networked exporter through
`host.docker.internal` and a `host-gateway` mapping. Run this profile on Linux.
Docker Desktop requires host networking to be enabled (Docker Desktop 4.34 or
newer) and must place the node and exporter in the same Linux VM. Host mode
requires an existing `NODE_HOME` directory and executable `NODE_BINARY`; config
generation fails early when either path is unavailable.

The exporter listener uses a wildcard `:8086` bind in host-node mode. Restrict
that port with the host firewall to the Prometheus bridge or trusted monitoring
network. The Grafana mapping and sample credentials are for first-run setup;
bind or firewall the UI for your deployment and rotate `GRAFANA_ADMIN_PASSWORD`
before exposing it beyond the local host.

The Dockerized-node profile mounts the external `hyperliquid_hl-data` volume at
`/home/hluser/hl/data` and keeps the exporter on the Compose bridge network.
Root-level node files and the node container's network namespace are not part
of that reduced profile. Set `INFO_ENDPOINT_URL` to a reachable published node
endpoint before enabling `--probe-info-endpoint`, and arrange a shared host
directory for the optional critical-location projection. The external volume
must already exist; start the companion Hyperliquid node deployment first.

## Quick start

```bash
git clone https://github.com/validaoxyz/purrmetheus.git
cd purrmetheus

cp .env.sample .env
$EDITOR .env                      # set NODE_HOME, CHAIN, EXPORTER_VERSION, …

bash generate_config.sh           # renders Dockerfile, compose and prometheus.yml from templates

cd docker
docker compose up -d --build
```

Grafana is available at `http://<host>:${GRAFANA_PORT:-3000}` with admin credentials from `.env`
(rotate on first login). The dashboard is under **Dashboards → Hyperliquid**.

## Configuration

All settings live in `.env`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `USE_DOCKER` | `false` | Set to `true` if your HL node runs in Docker (mounts `hyperliquid_hl-data` at `/home/hluser/hl/data`) |
| `NODE_HOME` | `$HOME/hl` | Absolute host path to the node data directory |
| `NODE_BINARY` | `$HOME/hl-node` | Absolute host path to the `hl-node` binary; its parent directory is mounted read-only |
| `BINARY_HOME` | resolved `NODE_BINARY` directory | Optional absolute directory containing `hl-visor`; mounted at the v4 update-check path |
| `EXPORTER_UID` | invoking user's UID | Non-root UID for the exporter image; useful in CI (empty uses the invoking account) |
| `EXPORTER_GID` | invoking user's GID | Non-root GID for the exporter image; useful in CI (empty uses the invoking account) |
| `INFO_ENDPOINT_URL` | – | Optional URL for `--probe-info-endpoint`; Dockerized-node mode generally needs an explicit published node address |
| `CRIT_LOCATIONS_DIR` | `/tmp/crit_msg_latest_stats` | Host directory containing the matched `hl-visor.json` projection; mounted read-only at the exporter’s fixed path (empty disables the optional mount) |
| `CHAIN` | `mainnet` | `mainnet` or `testnet`. Tags every series as `chain=…` |
| `NODE_LABEL` | `hl-node` | Free-form label tagged onto every series as `node=…` |
| `EXPORTER_VERSION` | `v4.0.7` | Release tag of `hyperliquid-exporter` to install; `latest` allowed |
| `EXPORTER_EXTRA_FLAGS` | `--evm-metrics` | Extra flags forwarded to `hl_exporter start` |
| `SKIP_VERSION_CHECK` | `false` | Host-node toggle for the local `hl-node --version` monitor |
| `SKIP_UPDATE_CHECK` | `false` | Host-node toggle for the remote `hl-visor` update check |
| `GRAFANA_ADMIN_USER` | `admin` | Initial Grafana login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Initial Grafana password |
| `GRAFANA_PORT` | `3000` | Host port for the Grafana UI |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus TSDB retention window |

`EXPORTER_EXTRA_FLAGS` accepts whitespace-delimited `--flag` or `--flag=value`
tokens. Value-bearing flags must use `=`; positional tokens are rejected.
Stack-managed flags such as `--chain`, `--metrics-port`, and path configurations
are handled by the variables above and cannot be overridden here.

Host-node mode enables both binary checks by default. Set `SKIP_VERSION_CHECK=true`
or `SKIP_UPDATE_CHECK=true` if local policy or restricted network egress prevents
a check; the corresponding source is then reported as disabled. The update
checker needs outbound HTTPS to the Hyperliquid binary service, and validator
summaries need the configured Hyperliquid API. The exporter continues serving
metrics when either source is unavailable.

Pin `EXPORTER_VERSION` for reproducible builds. If you choose `latest`, rebuild
with `docker compose build --pull --no-cache` to check for a newer release; normal
layer caching can otherwise retain the previously downloaded asset.

`NODE_BINARY` points to the `hl-node` executable used by the version monitor. The
update monitor separately checks `BINARY_HOME/hl-visor`; when `BINARY_HOME` is
empty, the generator uses the resolved `NODE_BINARY` directory. If the paths
differ, both directories are mounted read-only and the exporter receives the
correct v4 paths. In Docker mode, the default `hyperliquid_hl-data` volume
contains only `/home/hluser/hl/data`, so the generated command disables both
binary checks and reports unavailable root-level sources through
`hl_exporter_source_*`. A whole-home bind mount can be used only with a node
deployment that explicitly shares that directory.

The generated Prometheus job is named `hyperliquid` for downstream compatibility;
its targets are labeled `node_mode=host` or `node_mode=docker`. Generic bundled
rules also accept the upstream `hyperliquid-exporter` job prefix. Process and
disk-capacity rules intentionally require `node_mode=host`, so an upstream-style
target must provide that label when it represents a host-node profile. Host-node
mode uses `host.docker.internal:8086` as its target; Dockerized-node mode uses
the `hl_exporter:8086` service name.

### Exporter flags

`hl_exporter` serves the default v4.0.7 metric set on `:8086/metrics`. Enable
additional metric families via `EXPORTER_EXTRA_FLAGS`:

| Flag | Adds |
| --- | --- |
| `--replica-metrics` | Transaction and order metrics. Requires `hl-node --replica-cmds-style actions-and-responses`. |
| `--evm-metrics` | HyperEVM block, gas, fee, transaction, receipt, and parser families |
| `--contract-metrics` | Capped recipient-address diagnostics; does not include contract identity or enrichment |
| `--extended-metrics` | RocksDB, lz4, tokio, public IP, log lines, crit locations, and related metrics |
| `--probe-info-endpoint` | Active probing of the node's `--serve-info` endpoint |
| `--per-peer-metrics` | Up to 16 current explicit child identities from fresh status |

Recommended host-node baseline with `--serve-info`:

```env
EXPORTER_EXTRA_FLAGS="--replica-metrics --evm-metrics --probe-info-endpoint --extended-metrics"
```

For a Dockerized node, explicitly enable and publish its `--serve-info`
endpoint, then set `INFO_ENDPOINT_URL` to that URL before enabling
`--probe-info-endpoint`. Do not point it at the node's EVM RPC endpoint
(typically port 3001 with path `/evm`): the exporter sends POST `meta` and
`exchangeStatus` requests to
`/info`. The node's TCP sockets remain outside the exporter's bridge namespace;
treat the socket source as unavailable unless the node deployment shares a
network namespace.

## Updating

```bash
git pull
$EDITOR .env                      # update EXPORTER_VERSION to pin a newer release
bash generate_config.sh
cd docker
docker compose up -d --build
```

## Upgrading from older exporter releases

Exporter v4.0.6 introduced breaking changes to metrics and labels, and v4.0.7
adds the `outcomeDeploy` and `trailingStop` action classifications. Purrmetheus
v3.0.0 is the first release built and tested against v4.0.7. Regenerate the
stack and verify downstream dashboards, alerts, recording rules, and remote
write consumers before switching an existing target.

Before migrating, stop the old v3 exporter and remove or disable its alert and
recording rules. Then update `EXPORTER_VERSION`, replace retired flags such as
`--evm` and `--enable-prom`, resolve `NODE_BINARY` symlinks to regular files,
regenerate the stack, and start the new target. Keep the Compose project name
and named volumes; do not use `docker compose down -v` during the migration.

Bundled dashboards and alerts use the v4 metric names. Notable migrations
include `hl_consensus_validators`,
`hl_consensus_qc_participation_percent`,
`hl_node_persisted_abci_height_gap{comparison="fast_minus_slow"}`,
`hl_p2p_tcp_socket_connections`,
`hl_p2p_traffic_endpoints_seen`, and
`hl_exporter_monitor_last_valid_observation_seconds`. The removed
`hl_evm_account_count` family has no production-safe replacement.

For the full rename table, see the [exporter v4 upgrade notes](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/UPGRADING.md).

## Alerts

Prometheus loads `prometheus/alerts.yml` at startup. Configured alert rules cover:

- Process liveness (`hl-node`, `hl-visor`, exporter), guarded by source health
- Sync health (visor accepted-data age and snapshot evidence age)
- Disk usage (warning at 20%, critical at 10%) from filesystem `statfs`; recursive
  walk health is reported separately
- Bug emission
- P2P source observations and max-peer rejections
- Persisted Core/ABCI checkpoint file gap
- Core block height stalls and slow progress
- Exporter monitor lifecycle, panics, and dropped error reports
- EVM receipt/parse diagnostics and unknown action types
- Outdated software versions

`HyperliquidSnapshotEvidenceStale` tracks the age of the latest height-driven
snapshot sentinel or exporter receipt. It enforces an evidence-age policy rather
than asserting a fixed Hyperliquid snapshot schedule; adjust or route this alert
according to the node's operating profile.

`NodeNotInSync` is retained for downstream compatibility. It triggers on stale
visor observation evidence and does not indicate an overall network partition or
failure across all node processes. Bundled rules already include
upstream-compatible alerts; avoid loading upstream alert files alongside them to
prevent duplicate notifications.

To route alerts, add an Alertmanager service to the Compose configuration and
specify `--alertmanager.url` in Prometheus.

v4-aligned alert rules include `HyperliquidCoreHeightStalled`,
`HyperliquidCoreHeightSlow`, `HyperliquidExporterMonitorExited`,
`HyperliquidExporterMonitorPanicked`,
`HyperliquidExporterErrorReportsDropped`,
and `HyperliquidExporterSourceReadOrSchemaFailed`.
The legacy monitor-stuck rule was removed because the v4 last-valid timestamp
reflects accepted-data age rather than loop execution. Process and disk-capacity
rules are suppressed for the reduced Dockerized-node profile, where host PID and
`NODE_HOME` filesystem metrics are unavailable.

## Layout

```
.
├── .env.sample                       # user settings
├── generate_config.sh                # renders templates into runnable configs
├── docker/
│   └── templates/                    # Dockerfile + compose templates (envsubst input)
├── prometheus/
│   ├── prometheus.yml.tmpl           # template
│   └── alerts.yml                    # rule file
├── grafana/
│   ├── dashboards/                   # JSON dashboards, auto-loaded
│   └── provisioning/                 # datasource + dashboard provider configs
└── docs/
    └── metrics/                      # local metric reference
```

## Docs

- [Local metrics quick-reference](docs/metrics/README.md)
- [Full exporter v4.0.7 metrics reference](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/docs/metrics.md)
- [Exporter v4 upgrade notes](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/UPGRADING.md)
- [Exporter changelog](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/CHANGELOG.md)

## Contributing

PRs and issues welcome.
