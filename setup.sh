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
cat > .venv/bin/toolbox-mcp <<'SH'
#!/bin/sh
set -eu
project="$(cd "$(dirname "$0")/../.." && pwd)"
unset PYTHONHOME
PYTHONPATH="$project/python" exec "$project/.venv/bin/python" -m toolbox.mcp_server "$@"
SH
chmod +x .venv/bin/toolbox-mcp
if ! command -v ffmpeg >/dev/null 2>&1 || ! command -v ffprobe >/dev/null 2>&1; then
  printf '%s\n' 'FFmpeg is needed for Trim. Install with: brew install ffmpeg'
fi
if ! command -v shark >/dev/null 2>&1; then
  printf '%s\n' 'Shark is needed for Convert. Install with: brew tap shineexxx/tap && brew install --cask shark'
fi
if ! command -v soffice >/dev/null 2>&1 && [ ! -x /Applications/LibreOffice.app/Contents/MacOS/soffice ]; then
  printf '%s\n' 'LibreOffice is needed for Word-to-PDF conversion. Install with: brew install --cask libreoffice'
fi
printf '%s\n' "Ready: $(pwd)/.venv/bin/toolbox list"
