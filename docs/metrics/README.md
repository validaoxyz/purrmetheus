# Metrics

Purrmetheus ships everything `hyperliquid-exporter` exposes — see the upstream
[metrics reference](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/docs/metrics.md)
for the authoritative, always-current list.

Below is a short orientation. All metrics are tagged with the external labels
`chain` (`mainnet`/`testnet`) and `node` (whatever you set as `NODE_LABEL`).

## Namespaces

| Prefix | What it covers |
| --- | --- |
| `hl_core_*` | HyperCore: block height, latest block time, block-time histograms, txs (`--replica-metrics`) |
| `hl_metal_*` | Block-apply timings (the v1 `hl_apply_duration_seconds` lives here as `hl_metal_apply_duration_milliseconds`) |
| `hl_consensus_*` | Validator set, stake, jailed status, proposer counts, QC/TC, heartbeats, latency |
| `hl_evm_*` | HyperEVM: block height, gas, base/priority fees, tx types, account count (`--evm-metrics`) |
| `hl_visor_*` | Sync state: height, blocks applied, consensus drift, reference lag, observation age, freeze height |
| `hl_node_*` | Node-level signals: process health, disk usage, snapshot status, crit/bug counts, subsystem latency |
| `hl_p2p_*` | TCP connections, peer counts, peer traffic, gossip events |
| `hl_software_*` | Local binary version + up-to-date status |
| `hl_exporter_*` | Self-observability: monitor liveness, panic counters, build info |

## Worth-having dashboard expressions

```promql
# Block production rate (blocks/s)
rate(hl_core_block_height[5m])

# p95 block-apply over the last hour
histogram_quantile(0.95, sum(rate(hl_metal_apply_duration_milliseconds_bucket[1h])) by (le))

# Top-10 validators by stake
topk(10, hl_consensus_validator_stake)

# Jailed-stake percentage of total
(hl_consensus_jailed_stake / hl_consensus_total_stake) * 100

# Disk-free fraction on NODE_HOME's filesystem
hl_node_disk_free_bytes / hl_node_disk_total_bytes

# Visor "is this node behind" — non-zero == lag
hl_visor_last_observation_age_seconds

# Bugs / crits emitted per source
sum by (source) (rate(hl_node_bugs[5m]))
sum by (source) (rate(hl_node_crits[5m]))

# EVM tier divergence
hl_evm_db_checkpoint_lag_blocks

# Distinct peers observed in the last 24h
hl_p2p_unique_peers_seen{window="24h"}

# Exporter monitors that haven't ticked in 10 min
time() - hl_exporter_monitor_last_tick_seconds > 600
```

## Where the alerts live

See `prometheus/alerts.yml` at the repo root for the bundled rule file. It covers
process liveness, sync, disk, crits, peers, EVM checkpoint lag and exporter health.
The rule expressions are drawn from the upstream operator-alert recipes in
[hyperliquid-exporter's CHANGELOG](https://github.com/validaoxyz/hyperliquid-exporter/blob/main/CHANGELOG.md).
