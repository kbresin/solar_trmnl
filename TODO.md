# TODO

## Alerting

- **BMP generation failure alert** — wrap `bmp_today_api.sh` with a monitoring layer that catches failures and emails an admin via AWS SES if the daily BMP generation/upload does not complete successfully.

- **System health alert** — wire up `UNUSED/api/check_health.sh`, parse its output, and send an alert via AWS SES to a separate admin address if anything looks amiss (e.g. open alerts, inverter faults, abnormal DC voltage).

## Analysis

- **Panel-level outlier detection** — extend `UNUSED/api/check_panel_health.sh` to pull per-panel production data and apply stddev analysis across the inverter set to flag statistically anomalous panels. Goal is to catch degrading panels that fall below the threshold for a formal fault but are meaningfully underperforming relative to their peers.
