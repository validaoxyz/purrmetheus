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
and [hyperliquid-exporter](https://github.com/validaoxyz/hyperliquid-exporter) v3, wired together
with a provisioned dashboard and alert rules. Run it on the same host as your `hl-visor`/`hl-node`
process — the exporter tails local logs and walks `NODE_HOME`.

Components:

- **hyperliquid-exporter v3** — the metrics source
- **Prometheus** — on-disk retention, alert evaluation, rules for liveness, sync, disk, crits, peers, EVM lag and exporter health
- **Grafana** — auto-provisioned v3 dashboard (HyperCore, consensus/validators, visor sync, HyperEVM, node health, P2P, latency)
- **node_exporter** — host `/proc`, `/sys` and `/` mounted for host metrics

## Requirements

- Docker Engine ≥ 24 with the Compose plugin
- `envsubst` (`apt install gettext-base` / `brew install gettext`)
- `jq` (`apt install jq` / `brew install jq`)
- A Hyperliquid node running on the same host

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
| `USE_DOCKER` | `false` | `true` if your HL node runs in Docker (mounts `hyperliquid_hl-data` external volume) |
| `NODE_HOME` | `$HOME/hl` | Host path to the node's data directory |
| `NODE_BINARY` | `$HOME/hl-visor` | Host path to the `hl-visor` binary |
| `IS_VALIDATOR` | `false` | Toggles validator-only panels |
| `VALIDATOR_ADDRESS` | – | Your validator address |
| `CHAIN` | `mainnet` | `mainnet` or `testnet`. Tags every series as `chain=…` |
| `NODE_LABEL` | `hl-node` | Free-form label tagged onto every series as `node=…` |
| `EXPORTER_VERSION` | `v3.0.0` | Release tag of `hyperliquid-exporter` to install; `latest` allowed |
| `EXPORTER_EXTRA_FLAGS` | `--replica-metrics --evm-metrics` | Extra flags forwarded to `hl_exporter start` |
| `GRAFANA_ADMIN_USER` | `admin` | Initial Grafana login |
| `GRAFANA_ADMIN_PASSWORD` | `admin` | Initial Grafana password |
| `GRAFANA_PORT` | `3000` | Host port for the Grafana UI |
| `PROMETHEUS_RETENTION` | `30d` | Prometheus TSDB retention window |

### Exporter flags

`hl_exporter` serves the v3 default metric set on `:8086/metrics`. Add families via `EXPORTER_EXTRA_FLAGS`:

| Flag | Adds |
| --- | --- |
| `--replica-metrics` | Tx/order metrics. Requires `hl-node --replica-cmds-style actions-and-responses`. |
| `--evm-metrics` | HyperEVM gas/tx/account family |
| `--contract-metrics` | Per-contract tx tracking (cardinality-bounded) |
| `--extended-metrics` | RocksDB, lz4, tokio, public IP, log lines, crit locations, … |
| `--probe-info-endpoint` | Active probe of the node's `--serve-info` endpoint |
| `--per-peer-metrics` | Per-IP `hl_p2p_peer_{first,last}_seen_seconds` (LRU-bounded) |

Validator baseline with `--serve-info`:

```env
EXPORTER_EXTRA_FLAGS="--replica-metrics --evm-metrics --probe-info-endpoint --extended-metrics"
```

## Updating

```bash
git pull
$EDITOR .env                      # bump EXPORTER_VERSION to pin a newer release
bash generate_config.sh
cd docker
docker compose up -d --build
```

## Upgrading from v1.x

purrmetheus v1.x wrapped exporter v1.x, which used a flat `hl_*` namespace. Exporter v2.0 (Aug 2025)
added category prefixes (`hl_core_*`, `hl_consensus_*`, `hl_metal_*`, `hl_evm_*`); v3 (May 2026) added
~80 metrics on top without breaking v2. The v1 dashboard renders blank against the current exporter,
so v2 ships a new one.

For the full rename table, see the
[exporter CHANGELOG](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/CHANGELOG.md).

## Alerts

Prometheus loads `prometheus/alerts.yml` on start. Rules cover:

- Process liveness (`hl-node`, `hl-visor`, exporter)
- Sync health (visor observation age, consensus-vs-wall drift, snapshot pipeline)
- Disk usage (warn 20%, critical 10%)
- Bug/crit emission
- P2P health (max-peers, peer fanout, gossip-port liveness)
- EVM tier divergence
- Block height stall
- Exporter monitor stuck / panicking
- Software outdated

To route them, add an Alertmanager service to the compose file and point Prometheus at it via
`--alertmanager.url`.

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
- [Full exporter metrics reference](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/docs/metrics.md)
- [Exporter v2→v3 upgrade notes](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/UPGRADING.md)
- [Exporter changelog](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/CHANGELOG.md)

## Contributing

PRs and issues welcome.
