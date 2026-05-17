#!/bin/bash

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source ~/.secrets/se.sh
source "$PROJECT_DIR/lib/tententen_aws_lib.sh"

output=$("$PROJECT_DIR/bmp_today_api.sh" "$@" 2>&1)
exit_code=$?

if [[ $exit_code -ne 0 ]]; then
	sns_warn "solar_trmnl: BMP generation failed (exit ${exit_code}) on $(hostname).

Output:
${output}"
	echo "$output" >&2
	exit $exit_code
fi
