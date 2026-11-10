# TODO

## Alerting

- ~~**BMP generation failure alert**~~ — done: `run.sh` wraps any script with SNS warning on failure
- ~~**System health alert**~~ — done: `api/check4faults.sh` checks site alerts and inverter fault modes; runs daily via `run.sh`, with a weekly deep dive via `--full-check` on Fridays

## Analysis

- ~~**Inverter-level outlier detection**~~ — done: `api/inverter_balance.py`, weekly via `--full-check`. Catches a failing string or several panels.
- ~~**Dead optimizer detection**~~ — done: optimizer roster check in `check4faults.sh`, daily.
- **Panel-level outlier detection** — still open. The V2 API lists all 110 optimizers but no per-optimizer production was found (see `api/solaredge_api.txt`). Revisit if SolarEdge documents a per-optimizer telemetry endpoint. A single underperforming panel is ~3–4 points of its inverter's share, below the weekly noise of the inverter-level check.
