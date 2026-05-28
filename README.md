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

A one-command monitoring stack for **Hyperliquid** nodes, built on Prometheus, Grafana and
[validaoxyz/hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter).

## What you get

- **hyperliquid-exporter v3** in a hardened, multi-arch (`amd64`/`arm64`) container.
- **Prometheus** with sensible defaults, on-disk retention, alert evaluation, and a curated
  rule set covering process liveness, sync, disk, crits, peers, EVM checkpoint lag and
  exporter health.
- **Grafana** with an auto-provisioned dashboard covering the v3 metric families:
  HyperCore block production, consensus / validators, validator-only panels, visor sync,
  HyperEVM, node health (process, disk, crits, snapshots), P2P traffic and subsystem
  latency.
- **node_exporter** with host `/proc`, `/sys` and `/` properly mounted for accurate host
  metrics.

## Requirements

- Docker Engine ≥ 24 with the Compose plugin
- `envsubst` (`apt install gettext-base` / `brew install gettext`)
- `jq` (`apt install jq` / `brew install jq`)
- A running Hyperliquid node on the same host (the exporter scrapes its log files)

This stack is meant to run on the **same machine** as your `hl-visor`/`hl-node` process —
hyperliquid-exporter relies on tailing local logs and walking `NODE_HOME`.

## Quick start

```bash
git clone https://github.com/validaoxyz/purrmetheus.git
cd purrmetheus

cp .env.sample .env
$EDITOR .env                      # set NODE_HOME, CHAIN, EXPORTER_VERSION, …

bash generate_config.sh           # renders docker/Dockerfile, docker-compose.yaml,
                                  # prometheus/prometheus.yml from templates

cd docker
docker compose up -d --build
```

Grafana is then reachable on `http://<host>:${GRAFANA_PORT:-3000}` (login with the
admin credentials from your `.env`; you'll be prompted to rotate on first login).
The Hyperliquid dashboard is auto-provisioned — look for it under **Dashboards →
Hyperliquid**.

## Configuration

All knobs live in `.env`.

| Variable | Default | Purpose |
| --- | --- | --- |
| `USE_DOCKER` | `false` | `true` if your HL node runs in Docker (mounts `hyperliquid_hl-data` external volume) |
| `NODE_HOME` | `$HOME/hl` | Host path to the node's data directory |
| `NODE_BINARY` | `$HOME/hl-visor` | Host path to the `hl-visor` binary |
| `IS_VALIDATOR` | `false` | Toggles validator-only panels |
| `VALIDATOR_ADDRESS` | – | Your validator address |
| `CHAIN` | `mainnet` | `mainnet` or `testnet`. Tags every series as `chain=…` |
| `NODE_LABEL` | `hl-node` | Free-form label tagged onto every series as `node=…` |
| `EXPORTER_VERSION` | `v3.0.0` | Release tag of `hyperliquid-exporter` to install; `latest` is allowed |
| `EXPORTER_EXTRA_FLAGS` | `--replica-metrics --evm-metrics` | Extra flags forwarded to `hl_exporter start` |
| `GRAFANA_ADMIN_USER` | `admin` | Initial Grafana login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Initial Grafana password |
| `GRAFANA_PORT` | `3000` | Host port for the Grafana UI |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus TSDB retention window |

### Exporter flags worth knowing

`hl_exporter` exposes the v3 default metric set on `:8086/metrics` out of the box. The
flags below unlock extra families; set them via `EXPORTER_EXTRA_FLAGS`:

| Flag | Adds |
| --- | --- |
| `--replica-metrics` | Tx/order metrics. Requires `hl-node --replica-cmds-style actions-and-responses`. |
| `--evm-metrics` | HyperEVM gas/tx/account family |
| `--contract-metrics` | Per-contract tx tracking (cardinality-bounded) |
| `--extended-metrics` | RocksDB, lz4, tokio, public IP, log lines, crit locations, … |
| `--probe-info-endpoint` | Active probe of the node's `--serve-info` endpoint |
| `--per-peer-metrics` | Emits per-IP `hl_p2p_peer_{first,last}_seen_seconds` (LRU-bounded) |

A useful baseline for a validator running with `--serve-info`:

```env
EXPORTER_EXTRA_FLAGS="--replica-metrics --evm-metrics --probe-info-endpoint --extended-metrics"
```

## Updating

```bash
git pull
$EDITOR .env                      # bump EXPORTER_VERSION if you want to pin newer
bash generate_config.sh
cd docker
docker compose up -d --build
```

## Upgrading from v1.x

v1.x of this repo wrapped `hyperliquid-exporter` v1.x, whose metrics were a flat
`hl_*` namespace. Starting with v2.0 of the exporter (Aug 2025), every metric got a
category prefix (`hl_core_*`, `hl_consensus_*`, `hl_metal_*`, `hl_evm_*`). v3 of the
exporter (May 2026) added ~80 more metrics without breaking the v2 surface. **The v1
dashboard shipped with purrmetheus v1.0.0 will render blank against the current
exporter** — that's why this v2 release ships a from-scratch dashboard.

If you have customizations on top of the v1 dashboard, see
[hyperliquid-exporter's CHANGELOG](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/CHANGELOG.md)
for the full rename table.

## Alerts

The `prometheus/alerts.yml` rule file is loaded by Prometheus on start. Rules cover:

- Process liveness (`hl-node`, `hl-visor`, the exporter itself)
- Sync health (visor observation age, consensus-vs-wall drift, snapshot pipeline)
- Disk usage (warn at 20%, critical at 10%)
- Bug/crit emission
- P2P health (max-peers, peer fanout, gossip-port liveness)
- EVM tier divergence
- Block height stall
- Exporter monitor stuck / panicking
- Software outdated

To route them to Slack/PagerDuty/etc., add an Alertmanager service to your compose
file and point Prometheus at it via `--alertmanager.url`.

## Layout

```
.
├── .env.sample                       # all user-tweakable settings
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
    └── metrics/                      # local metric reference (links to upstream)
```

## Troubleshooting

**Grafana panels show "No data"** — confirm `hl_exporter` is reachable from Prometheus:
```bash
docker compose -f docker/docker-compose.yaml exec prometheus \
    wget -qO- http://hl_exporter:8086/metrics | head
```

**`hl_node_process_up` is 0** — the exporter looks at `/proc` to find `hl-node`/`hl-visor`.
This only works on Linux hosts and requires that the exporter container can see the
right PIDs. On macOS Docker Desktop these metrics will be absent — that's expected.

**Binary version check fails on build** — the exporter binary is downloaded from
GitHub at build time. If you're behind a corporate proxy / rate-limited, pin
`EXPORTER_VERSION` to a specific tag and re-build.

**Permission errors on `prometheus_data` or `grafana_data`** — the containers run as
your host UID/GID (set automatically by `generate_config.sh`). If you ran an older
version of this stack first, remove the named volumes once and let them be recreated.

## Docs

- [Local metrics quick-reference](docs/metrics/README.md)
- [Full exporter metrics reference (upstream)](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/docs/metrics.md)
- [Exporter v2→v3 upgrade notes](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/UPGRADING.md)
- [Exporter changelog](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/CHANGELOG.md)

## Contributing

PRs and issues welcome.
