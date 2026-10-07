#!/bin/sh
set -eu
cd "$(dirname "$0")"
if [ ! -x .venv/bin/toolbox ]; then
  printf '%s\n' 'Python tools are missing. Run ./setup.sh first.' >&2
  exit 1
fi
./build-app.sh
destination="/Applications/Local Utilities"
mkdir -p "$destination"
ditto Toolbox.app "$destination/Toolbox.app"
ditto .venv "$destination/.venv"
ditto python "$destination/python"
xattr -cr "$destination/Toolbox.app"
codesign --force --deep --sign - --identifier local.toolbox.app "$destination/Toolbox.app"
codesign --verify --deep --strict "$destination/Toolbox.app"
printf '%s\n' "Installed $destination/Toolbox.app"
