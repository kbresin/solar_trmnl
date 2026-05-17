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

if ! command -v aws &>/dev/null; then
	echo "Error: aws CLI not found — install it from https://aws.amazon.com/cli/" >&2
	exit 1
fi

SETUP_DONE=0

if [[ ! -d "$PROJECT_DIR/.venv" ]]; then
	echo "Creating venv..."
	$PYTHON -m venv "$PROJECT_DIR/.venv"
	echo "Installing requirements..."
	"$PROJECT_DIR/.venv/bin/pip" install -q -r "$PROJECT_DIR/requirements.txt"
	SETUP_DONE=1
fi

FONT_DIR="${HOME}/.local/share/fonts"
FONT_PATH="${FONT_DIR}/Gidole-Regular.ttf"
if [[ ! -f "$FONT_PATH" ]]; then
	echo "Downloading Gidole-Regular.ttf to ${FONT_DIR}..."
	mkdir -p "$FONT_DIR"
	curl -sL "https://raw.githubusercontent.com/larsenwork/Gidole/master/Resources/GidoleFont/Gidole-Regular.ttf" \
		-o "$FONT_PATH"
	SETUP_DONE=1
fi

if [[ $SETUP_DONE -eq 1 ]]; then
	echo "Done. Activate with: source .venv/bin/activate"
else
	echo "Already up to date."
fi
