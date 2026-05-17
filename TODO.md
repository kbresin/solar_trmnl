# TODO

## Alerting

- ~~**BMP generation failure alert**~~ — done: `run.sh` wraps any script with SNS warning on failure
- ~~**System health alert**~~ — done: `api/check4faults.sh` checks site alerts and inverter fault modes; runs daily via `run.sh`, with a weekly deep dive via `--full-check` on Fridays

## Analysis

- **Panel-level outlier detection** — extend `UNUSED/api/check_panel_health.sh` to pull per-panel production data and apply stddev analysis across the inverter set to flag statistically anomalous panels. Goal is to catch degrading panels that fall below the threshold for a formal fault but are meaningfully underperforming relative to their peers. The weekly inverter telemetry log (`~/.cache/solar_trmnl/inverter_weekly.log`) will provide baseline data to inform thresholds.
