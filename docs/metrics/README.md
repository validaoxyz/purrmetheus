# Metrics

Purrmetheus packages the metrics exposed by `hyperliquid-exporter` v4.0.7.
The upstream [metrics reference](https://github.com/validaoxyz/hyperliquid-exporter/blob/v4.0.7/docs/metrics.md)
is the authoritative inventory and interpretation guide. Optional metric
families are absent unless their exporter flag is enabled.

The `hyperliquid` scrape target receives static `chain`, `node`, and `node_mode`
labels (`host` or `docker`). Prometheus also configures `chain` and `node` as
external labels for outbound systems; external labels are not local labels on
every queried series, and the `node_exporter` target does not receive
`node_mode`.
The exporter also publishes source-state and monitor-lifecycle families. Use
those families to qualify a value before treating it as a health signal.

## Namespaces

| Prefix | What it covers |
| --- | --- |
| `hl_core_*` | HyperCore height, block timing, and validated replica block records |
| `hl_replica_*` | Validated signed actions, operations, orders, responses, and parser outcomes (`--replica-metrics`) |
| `hl_mempool_*` | Mempool and split-client mempool records, sizes, actions, and parser outcomes; workers start always, but source data may be absent |
| `hl_metal_*` | Block-apply timing histograms; dual fast/slow streams carry `state_type` |
| `hl_consensus_*` | Validator summaries, stake, jail status, proposer/QC/heartbeat data, and consensus observations |
| `hl_evm_*` | HyperEVM block, gas, fee, transaction, receipt, and parser data (`--evm-metrics`) |
| `hl_visor_*` | Visor height, observation age, reference lag, drift, and freeze-state evidence |
| `hl_node_*` | Process, disk, snapshot, persisted-state, critical-message, and subsystem data |
| `hl_p2p_*` | TCP sockets, traffic observations, gossip events, and bounded child snapshots |
| `hl_software_*` | Local binary version and update status when those checks are enabled |
| `hl_exporter_*` | Build identity, monitor lifecycle, source health, and bounded error counters |

## Useful expressions

```promql
# Core height progress. hl_core_block_height is a gauge.
deriv(hl_core_block_height[5m])

# p95 block-apply latency, retaining the fast/slow source label.
histogram_quantile(
  0.95,
  sum(rate(hl_metal_apply_duration_milliseconds_bucket[1h])) by (le, state_type)
)

# Top validators by stake, converted from raw 1e-8 HYPE units.
topk(10, hl_consensus_validator_stake / 1e8)

# Jailed stake percentage. Stake values are raw units, so the ratio is unitless.
(hl_consensus_jailed_stake / hl_consensus_total_stake) * 100

# Disk-free fraction. Qualify with statfs success and a non-zero capacity.
(hl_node_disk_free_bytes / hl_node_disk_total_bytes) and (hl_node_disk_statfs_up == 1)

# Age carried by the latest valid visor sample (content freshness).
hl_visor_last_observation_age_seconds

# Current qualified traffic observations, not a peer or connectivity count.
hl_p2p_traffic_endpoints_seen{window="24h"}

# Seconds since each monitor's latest accepted observation.
time() - hl_exporter_monitor_last_valid_observation_seconds
```

The following type rules matter when writing dashboards or alerts:

- `hl_core_block_height` and `hl_node_crits` are gauges. Do not apply
  `rate()` or `increase()` to them.
- `hl_node_subsystem_work_fraction` preserves the raw upstream
  `work_fraction`; it is not guaranteed to be between 0 and 1.
- Validator-summary stake is reported in raw 1e-8 HYPE units.
- `hl_node_persisted_abci_height_gap{comparison="fast_minus_slow"}` compares
  persisted Core/ABCI files in the stated direction. It is not current HyperEVM
  execution lag.
- `hl_p2p_tcp_socket_connections{service_port,service_side,state}` describes
  kernel socket rows. `hl_p2p_traffic_endpoints_seen{window}` describes a
  process-local traffic observation.
- `hl_visor_last_observation_age_seconds` is sample-content age and is the
  preferred sync signal. `hl_exporter_source_last_valid_age_seconds` measures
  exporter receipt age; the bundled sync alert takes the larger of the two so a
  stalled worker cannot hide behind a fresh file. `hl_exporter_monitor_last_valid_observation_seconds`
  is monitor-level accepted-data age.
  The deprecated `hl_exporter_monitor_last_tick_seconds` alias is not used by
  the bundled dashboard or alerts.
- Disk-capacity values come from the filesystem `statfs` read. The recursive
  `NODE_HOME` walk has separate `hl_node_disk_walk_up` and source-health state;
  a walk failure must not hide a valid low-capacity `statfs` signal.
- `HyperliquidSnapshotEvidenceStale` measures the age of the latest
  height-driven snapshot sentinel or exporter receipt. It does not infer a
  fixed snapshot cadence; review its 15-minute policy against the node's
  operating profile before paging.
- `hl_evm_account_count` has no production-safe replacement and is not shown.

The persisted checkpoint-gap family is always-on and does not require
`--evm-metrics`; the dashboard labels that panel explicitly. In Dockerized-node
mode, the default data-only volume excludes root-level node state, so that
family and other root-level sources can remain unavailable. Process and
filesystem-capacity alerts are suppressed for `node_mode="docker"` because its
bridge/PID namespaces cannot prove host-node liveness or `NODE_HOME` capacity.

## Optional profiles

The default `.env.sample` enables `--evm-metrics`. Enable
`--replica-metrics` only when the node is configured with the
`actions-and-responses` replica command style. Also enable `--extended-metrics`, `--probe-info-endpoint`, or
`--per-peer-metrics` only when the corresponding source and its interpretation
are useful for your node. The bundled alert file guards optional sources with
`hl_exporter_source_enabled`, read, and schema state.

## Alerts

The bundled rules are in [`prometheus/alerts.yml`](../../prometheus/alerts.yml).
They use the v4 source-health and lifecycle families, current replica/EVM
names, `deriv()` for Core height, and explicit guards for optional monitors.
Review thresholds and `for` durations before routing alerts to an incident
system.

The bundled file already contains the upstream-compatible rules. Mounting
upstream alert files alongside it will create duplicate alerts.
