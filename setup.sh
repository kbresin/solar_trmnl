#!/bin/bash
set -e
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if command -v python3 &>/dev/null; then
  PYTHON=python3
elif command -v python &>/dev/null; then
  PYTHON=python
else
  echo "Error: no python installation found" >&2
  exit 1
fi

if [[ ! -d "$PROJECT_DIR/.venv" ]]; then
  echo "Creating venv..."
  $PYTHON -m venv "$PROJECT_DIR/.venv"
fi

echo "Installing requirements..."
"$PROJECT_DIR/.venv/bin/pip" install -q -r "$PROJECT_DIR/requirements.txt"

echo "Done. Activate with: source .venv/bin/activate"
