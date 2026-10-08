# Toolbox

A local Mac utility app. Each tool is a typed Python function; the SwiftUI app builds its form from the tool's description and invokes the same CLI that scripts can call.

## Installation

### Requirements

- macOS 14 or newer
- Python 3.11 or newer
- Apple Command Line Tools (`xcode-select --install`)
- [Homebrew](https://brew.sh/) for the media dependencies

Install the external tools used by Convert and Trim:

```sh
brew tap shineexxx/tap
brew install --cask shark
brew install ffmpeg
```

Clone Toolbox, prepare its Python environment, and install the app:

```sh
git clone https://github.com/AlexHenin/Toolbox.git
cd Toolbox
./setup.sh
./install-app.sh
open '/Applications/Local Utilities/Toolbox.app'
```

The installer builds and locally signs the SwiftUI app, then copies the app, Python environment, and tool files to `/Applications/Local Utilities`. It may ask for permission to write to the Applications folder. To update an existing installation, pull the latest changes and run the setup and install scripts again:

```sh
git pull
./setup.sh
./install-app.sh
```

You can verify the command-line tools separately with:

```sh
./.venv/bin/toolbox list
```

The app looks for the installed `.venv/bin/toolbox` beside the application. `TOOLBOX_CLI` can override that path for development. macOS can show a generic icon for an app opened directly from a synced Documents folder; the installed app uses the bundled hammer icon.

Convert uses the local MIT-licensed [`Shark`](https://github.com/shineexxx/shark) CLI. Trim uses FFmpeg and FFprobe. Conversion and editing happen locally.

## Conversion engine

Toolbox uses [Shark](https://github.com/shineexxx/shark) as the conversion engine behind the Convert tool. Shark is installed separately and is not bundled with Toolbox. It is available under the MIT License; see [Third-party notices](THIRD_PARTY_NOTICES.md) and [Shark's license](https://github.com/shineexxx/shark/blob/main/LICENSE).

The setup installs the Python package in the project environment and creates a CLI launcher that loads `python/` directly. A new tool file becomes available to the project CLI without rerunning setup. Run `./install-app.sh` and reopen the installed app to make the new tool available there.

## CLI examples

```sh
./.venv/bin/toolbox list --json
./.venv/bin/toolbox describe crop --json
./.venv/bin/toolbox run convert-files --files first.png second.jpg --target pdf --output result.pdf --json
./.venv/bin/toolbox run crop --source input.png --area 0.1,0.1,0.8,0.8 --output cropped.png --json
./.venv/bin/toolbox run trim --source input.mp4 --segment 5,12.5 --output clip.mp4 --json
```

The crop coordinates are relative to the source: `x,y,width,height`, from 0 to 1. The tool accepts PDFs and Pillow-supported image formats. PDF pages are rendered as images at 200 DPI by default, so removed content does not remain embedded. Output text is therefore not selectable. `--dpi` accepts 72–600.

Convert shows the Shark output formats shared by all selected files. Images converted to PDF are merged into one document in their drag order. Other multi-file conversions are processed separately into one output folder.

In the app, Trim supports audio and video formats. Audio uses the waveform editor; video adds an embedded player and correlated frame strip above its compact waveform timeline. The CLI can provide the same timeline data with `toolbox inspect input.mp4 --waveform --json`.

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
