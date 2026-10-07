#!/bin/sh
set -eu
cd "$(dirname "$0")"
python3 -m venv .venv
.venv/bin/python -m pip install --upgrade pip
.venv/bin/python -m pip install ./python
cat > .venv/bin/toolbox <<'SH'
#!/bin/sh
set -eu
project="$(cd "$(dirname "$0")/../.." && pwd)"
unset PYTHONHOME
PYTHONPATH="$project/python" exec "$project/.venv/bin/python" -m toolbox "$@"
SH
chmod +x .venv/bin/toolbox
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  printf '%s\n' 'FFmpeg is needed for Trim Audio. Install with: brew install ffmpeg'
fi
printf '%s\n' "Ready: $(pwd)/.venv/bin/toolbox list"
