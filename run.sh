#!/bin/bash

PATH=/usr/local/bin:$PATH
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

source ~/.secrets/se.sh
source "$PROJECT_DIR/lib/tententen_aws_lib.sh"

if [[ $# -eq 0 ]]; then
	echo "Usage: run.sh <script> [args...]" >&2
	exit 1
fi

script="$1"
shift

if [[ "$script" != /* && -x "$PROJECT_DIR/$script" ]]; then
	script="$PROJECT_DIR/$script"
fi

output=$("$script" "$@" 2>&1)
exit_code=$?

echo "$output"

if [[ $exit_code -ne 0 ]]; then
	sns_warn "solar_trmnl: $(basename "$script") failed (exit ${exit_code}) on $(hostname).

Output:
${output}"
	exit $exit_code
fi
