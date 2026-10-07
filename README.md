# Toolbox

A local Mac utility app. Each tool is a typed Python function; the SwiftUI app builds its form from the tool's description and invokes the same CLI that scripts can call.

## Setup

Run from this folder:

```sh
./setup.sh
./.venv/bin/toolbox list
./install-app.sh
open '/Applications/Local Utilities/Toolbox.app'
```

The install command copies the app, Python environment, and editable tool files to `/Applications/Local Utilities`. Run it again after changing the Swift app or Python tools. macOS can show a generic icon for an app opened directly from a synced Documents folder; the installed app uses the white hammer icon.

The Python setup requires Python 3.11 or newer. Trim Audio also requires FFmpeg (`brew install ffmpeg`). Building the app requires Apple's Swift compiler and macOS SDK. The app looks for this project's `.venv/bin/toolbox` beside the `.app` folder; `TOOLBOX_CLI` can override that path.

The setup installs the Python package in the project environment and creates a CLI launcher that loads `python/` directly. A new tool file becomes available to the project CLI without rerunning setup. Run `./install-app.sh` and reopen the installed app to make the new tool available there.

## CLI examples

```sh
./.venv/bin/toolbox list --json
./.venv/bin/toolbox describe crop-pdf --json
./.venv/bin/toolbox run image-to-pdf --images first.png second.jpg --output result.pdf --json
./.venv/bin/toolbox run crop-pdf --source input.pdf --area 0.1,0.1,0.8,0.8 --output cropped.pdf --json
./.venv/bin/toolbox run trim-audio --source input.mp3 --segment 5,12.5 --output clip.mp3 --json
```

The crop coordinates are relative to each page: `x,y,width,height`, from 0 to 1. Cropped pages are rendered as images at 200 DPI by default, so removed content does not remain embedded. Output text is therefore not selectable. `--dpi` accepts 72–600.

In the app, Trim Audio shows a waveform with draggable yellow start and end handles, a blue playback cursor, selection playback, a full-clip overview, and precise time fields. The CLI can provide the same display data with `toolbox inspect input.wav --waveform --json`.

## Add a tool

Add one Python file under `python/toolbox/tools/`. The package discovers it automatically:

```python
from pathlib import Path
from toolbox import tool

@tool(title="Copy file", description="Make a copy", extensions={"source": ["txt"], "output": ["txt"]})
def copy_file(source: Path, output: Path) -> Path:
    output.write_bytes(source.read_bytes())
    return output
```

The example is intentionally minimal; production tools should validate inputs and use `atomic_output` from `toolbox.files` so a failed run does not leave a partial result. Supported annotations are `Path`, `FileList`, `Rectangle`, `TimeRange`, `str`, `int`, `float`, `bool`, and string `Literal` choices. The `output` parameter is treated as a save destination. Each new tool is available through both the CLI and the generated form after restarting the app.

## Layout

- `python/`: plugin registry, CLI, and tools
- `mac/`: SwiftUI app
- `mac/Assets/AppIcon.svg`: white-background hammer icon used by `build-app.sh`
- `tests/`: CLI and tool checks

This is a personal local build. The installed app is signed locally and uses the adjacent project-local Python environment. It has no updater or HTTP server.
