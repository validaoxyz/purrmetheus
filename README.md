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
and [hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter) v4.0.7, wired together
with a provisioned dashboard and alert rules. In host-node mode, run it on the same Linux host as
your `hl-visor`/`hl-node` process; the exporter tails local logs and walks `NODE_HOME`.

Components:

- **hyperliquid-exporter v4.0.7** — the metrics source
- **Prometheus** — on-disk retention, alert evaluation, and guarded rules for liveness, sync, disk, consensus, EVM, P2P, and exporter health
- **Grafana** — auto-provisioned v4 dashboard (HyperCore, consensus/validators, visor sync, HyperEVM, node health, P2P, latency)
- **node_exporter** — host `/proc`, `/sys` and `/` mounted for host metrics

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

The Dockerized-node profile mounts the external `hyperliquid_hl-data` volume at
`/home/hluser/hl/data` and keeps the exporter on the Compose bridge network.
Root-level node files and the node container's network namespace are not part
of that reduced profile. Set `INFO_ENDPOINT_URL` to a reachable published node
endpoint before enabling `--probe-info-endpoint`, and arrange a shared host
directory for the optional critical-location projection.

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

Grafana: `http://<host>:${GRAFANA_PORT:-3000}`, admin credentials from `.env` (rotate on first login).
The dashboard is under **Dashboards → Hyperliquid**.

## Configuration

All settings live in `.env`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `USE_DOCKER` | `false` | `true` if your HL node runs in Docker (mounts `hyperliquid_hl-data` at `/home/hluser/hl/data`) |
| `NODE_HOME` | `$HOME/hl` | Absolute host path to the node's data directory |
| `NODE_BINARY` | `$HOME/hl-node` | Absolute host path to the `hl-node` binary; its directory is mounted read-only |
| `BINARY_HOME` | resolved `NODE_BINARY` directory | Optional absolute directory containing `hl-visor`; mounted at the v4 update-check path |
| `INFO_ENDPOINT_URL` | – | Optional URL for `--probe-info-endpoint`; Dockerized-node mode usually needs a published node address |
| `CRIT_LOCATIONS_DIR` | `/tmp/crit_msg_latest_stats` | Host directory containing the matched `hl-visor.json` projection; mounted read-only at the exporter’s fixed path (empty disables the optional mount) |
| `CHAIN` | `mainnet` | `mainnet` or `testnet`. Tags every series as `chain=…` |
| `NODE_LABEL` | `hl-node` | Free-form label tagged onto every series as `node=…` |
| `EXPORTER_VERSION` | `v4.0.7` | Release tag of `hyperliquid-exporter` to install; `latest` allowed |
| `EXPORTER_EXTRA_FLAGS` | `--evm-metrics` | Extra flags forwarded to `hl_exporter start` |
| `GRAFANA_ADMIN_USER` | `admin` | Initial Grafana login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Initial Grafana password |
| `GRAFANA_PORT` | `3000` | Host port for the Grafana UI |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus TSDB retention window |

`EXPORTER_EXTRA_FLAGS` accepts whitespace-delimited `--flag` or
`--flag=value` tokens. Value-bearing flags must use `=`, and positional tokens
are rejected. Stack-owned flags such as `--chain`, `--metrics-port`, and the
node/binary paths are configured by the variables above and cannot be
overridden in this field.

Pin `EXPORTER_VERSION` for repeatable builds. If you choose `latest`, rebuild
with `docker compose build --pull --no-cache` when checking for a newer release;
normal layer caching can otherwise retain the previously downloaded asset.

`NODE_BINARY` is the `hl-node` executable used by the version monitor. The
update monitor separately checks `BINARY_HOME/hl-visor`; when `BINARY_HOME` is
empty, the generator uses the resolved `NODE_BINARY` directory. If the paths
differ, both directories are mounted read-only and the exporter receives the
correct v4 paths. In Docker mode
the default `hyperliquid_hl-data` volume contains only `/home/hluser/hl/data`,
so the generated command disables both binary checks and reports unavailable
root-level sources through `hl_exporter_source_*`. A whole-home bind mount can
be used only with a node deployment that explicitly shares that directory.

The generated Prometheus job name remains `hyperliquid` for existing consumers;
its target is labeled `node_mode=host` or `node_mode=docker`.
The bundled rules also accept the upstream `hyperliquid-exporter` job prefix.
Host-node mode
uses `host.docker.internal:8086` as its target; Dockerized-node mode uses the
`hl_exporter:8086` service name.

### Exporter flags

`hl_exporter` serves the v4.0.7 default metric set on `:8086/metrics`. Add families via `EXPORTER_EXTRA_FLAGS`:

| Flag | Adds |
| --- | --- |
| `--replica-metrics` | Tx/order metrics. Requires `hl-node --replica-cmds-style actions-and-responses`. |
| `--evm-metrics` | HyperEVM block, gas, fee, transaction, receipt, and parser families |
| `--contract-metrics` | Capped recipient-address diagnostics; no contract identity or enrichment |
| `--extended-metrics` | RocksDB, lz4, tokio, public IP, log lines, crit locations, … |
| `--probe-info-endpoint` | Active probe of the node's `--serve-info` endpoint |
| `--per-peer-metrics` | Up to 16 current explicit child identities from fresh status |

Host-node baseline with `--serve-info`:

```env
EXPORTER_EXTRA_FLAGS="--replica-metrics --evm-metrics --probe-info-endpoint --extended-metrics"
```

For a Dockerized node, explicitly enable and publish its `--serve-info`
endpoint, then set `INFO_ENDPOINT_URL` to that URL before adding the probe
flag. Do not point it at the node's EVM RPC endpoint (often port 3001 with an
`/evm` path): the exporter sends POST `meta` and `exchangeStatus` requests to
`/info`. The node's TCP sockets remain outside the exporter bridge namespace;
treat the socket source as unavailable unless the node deployment shares a
network namespace.

## Updating

```bash
git pull
$EDITOR .env                      # bump EXPORTER_VERSION to pin a newer release
bash generate_config.sh
cd docker
docker compose up -d --build
```

## Upgrading from older exporter releases

Exporter v4.0.6 introduced breaking metric and label changes, and v4.0.7
adds the `outcomeDeploy` and `trailingStop` action classifications. Purrmetheus
v3.0.0 is the first release built and tested against v4.0.7. Regenerate the
stack and review downstream dashboards, alerts, recording rules, and remote
write consumers before switching an existing target.

The bundled consumers already use the current v4 names. Notable migrations
include `hl_consensus_validators`,
`hl_consensus_qc_participation_percent`,
`hl_node_persisted_abci_height_gap{comparison="fast_minus_slow"}`,
`hl_p2p_tcp_socket_connections`,
`hl_p2p_traffic_endpoints_seen`, and
`hl_exporter_monitor_last_valid_observation_seconds`. The removed
`hl_evm_account_count` family has no production-safe replacement.

For the full rename table, see the
[exporter v4 upgrade notes](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/UPGRADING.md).

## Alerts

Prometheus loads `prometheus/alerts.yml` on start. Rules cover:

- Process liveness (`hl-node`, `hl-visor`, exporter), guarded by source health
- Sync health (visor accepted-data age and snapshot evidence age)
- Disk usage (warn 20%, critical 10%) from a successful filesystem-statfs read;
  recursive walk health is reported separately
- Bug emission
- P2P source observations and max-peer rejections
- Persisted Core/ABCI checkpoint-file gap
- Core block-height stall and slow progress
- Exporter monitor lifecycle, panics, and dropped reports
- EVM receipt/parse diagnostics and unknown action types
- Software outdated

`HyperliquidSnapshotEvidenceStale` measures the age of the latest height-driven
snapshot sentinel or exporter receipt. It is an evidence-age policy, not a
claim that Hyperliquid snapshots arrive on a fixed schedule; tune or route it
for the node's operating profile.

`NodeNotInSync` is retained as a downstream-compatible alert name. Its signal
is stale visor observation evidence; it does not prove that the network or
every node process is out of sync. The bundled rules already include the
upstream-compatible rules; do not load the upstream alert files again for the
same target unless duplicate notifications are intentional.

To route them, add an Alertmanager service to the compose file and point Prometheus at it via
`--alertmanager.url`.

The v4-aligned alert names include `HyperliquidCoreHeightStalled`,
`HyperliquidCoreHeightSlow`, `HyperliquidExporterMonitorExited`,
`HyperliquidExporterMonitorPanicked`,
`HyperliquidExporterErrorReportsDropped`,
and `HyperliquidExporterSourceReadOrSchemaFailed`.
The old monitor-stuck rule was removed because the v4 last-valid timestamp is
accepted-data age, not loop activity. Process and disk-capacity rules are
suppressed for the reduced Dockerized-node profile, where the exporter cannot
prove host PID or `NODE_HOME` filesystem state.

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
