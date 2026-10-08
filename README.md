# ToolBox

A local Mac utility app that also doubles as an MCP tool server for AI clients. Each utility is defined once as a typed Python function and automatically becomes:

- A native SwiftUI workflow
- A command-line command
- An MCP tool an AI model can discover and call

ToolBox currently provides Convert, Crop, and Trim. The app and tool server operate on local files, so the same utilities are available for direct use and automated workflows without uploading files to a hosted conversion service.

## Installation

ToolBox is currently installed from its source code. You do not need to know how to program, but you will copy a few commands into Terminal. Run each numbered step in order and wait for it to finish before moving to the next one.

You need:

- A Mac running macOS 14 Sonoma or newer
- An administrator account on the Mac
- An internet connection
- Several gigabytes of free space for Apple's developer tools and the media engines

### 1. Open Terminal

Press **Command–Space**, type **Terminal**, and press **Return**. Paste commands into the Terminal window without including the `$` prompt shown by some websites.

### 2. Install Apple's Command Line Tools

Paste this command and press **Return**:

```sh
xcode-select --install
```

If a window appears, click **Install** and wait for it to finish. If Terminal says the tools are already installed, continue to the next step.

### 3. Install Homebrew

[Homebrew](https://brew.sh/) installs the supporting software ToolBox needs. Paste its official installer command:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
```

The installer may ask for your Mac login password. Terminal does not show dots or other characters while you type a password; type it normally and press **Return**.

At the end, Homebrew may print **Next steps** with one or two commands for adding `brew` to your shell. Copy and run those commands exactly. Then confirm Homebrew is ready:

```sh
brew --version
```

### 4. Install Python, Shark, and FFmpeg

Paste this entire block:

```sh
brew install python ffmpeg
brew tap shineexxx/tap
brew install --cask shark
```

Python runs ToolBox's local tools. [Shark](https://github.com/shineexxx/shark) powers Convert, while FFmpeg and FFprobe power Trim.

### 5. Download ToolBox

This places the project in a folder named `ToolBox` inside your home folder:

```sh
cd ~
git clone https://github.com/AlexHenin/ToolBox.git
cd ToolBox
```

If Terminal says the `ToolBox` folder already exists, you may already have a copy. Run `cd ~/ToolBox` instead of cloning it again.

### 6. Set up and install ToolBox

From inside the `ToolBox` folder, run:

```sh
./setup.sh
./install-app.sh
```

The first command creates ToolBox's private Python environment. The second builds the Mac app and installs it at `/Applications/Local Utilities/Toolbox.app`.

### 7. Open ToolBox

```sh
open '/Applications/Local Utilities/Toolbox.app'
```

You can open it normally from that location afterward. Keep the `~/ToolBox` source folder if you want easy updates later.

### 8. Approve Shark the first time you use Convert

Shark is currently signed ad hoc rather than notarized with a paid Apple Developer ID, so macOS blocks it once. This approval is for Shark, not ToolBox:

1. Try converting a file in ToolBox.
2. In the “Shark Not Opened” dialog, click **Done**.
3. Open **System Settings → Privacy & Security**.
4. Scroll down to **Security**.
5. Find the message saying Shark was blocked and click **Open Anyway**.
6. Authenticate with your Mac password or Touch ID, then confirm **Open**.
7. Return to ToolBox and try Convert again.

Only approve Shark if you installed it using the documented [`shineexxx/tap`](https://github.com/shineexxx/homebrew-tap) command above and trust that software. This approval is normally required only once for each Shark installation.

### Update ToolBox

Open Terminal and run:

```sh
cd ~/ToolBox
git pull
./setup.sh
./install-app.sh
open '/Applications/Local Utilities/Toolbox.app'
```

### Check that the command-line tools work

This optional command should list Convert, Crop, and Trim:

```sh
cd ~/ToolBox
./.venv/bin/toolbox list
```

### Troubleshooting

**Terminal says `brew: command not found`**

Close and reopen Terminal. If that does not help, rerun the **Next steps** commands printed by the Homebrew installer, then run `brew --version` again.

**Terminal says `Python tools are missing`**

Run these commands from the project folder:

```sh
cd ~/ToolBox
brew install python
./setup.sh
./install-app.sh
```

**Convert says Shark is missing**

```sh
brew tap shineexxx/tap
brew install --cask shark
```

If Shark is installed but macOS blocks it, follow the approval instructions in step 8.

**Trim says FFmpeg is missing**

```sh
brew install ffmpeg
```

**The installed app does not show your latest update**

Quit ToolBox completely, run the commands under **Update ToolBox**, and reopen the installed copy from `/Applications/Local Utilities`.

The app uses the copied Python environment beside the installed application. `TOOLBOX_CLI` can override its location for development. Convert, Crop, and Trim process files locally; ToolBox does not upload them to a hosted conversion service.

## External engines

ToolBox uses [Shark](https://github.com/shineexxx/shark) as the conversion engine behind the Convert tool. Shark is installed separately and is not bundled with ToolBox. It is available under the MIT License; see [Third-party notices](THIRD_PARTY_NOTICES.md) and [Shark's license](https://github.com/shineexxx/shark/blob/main/LICENSE).

ToolBox uses [FFmpeg](https://ffmpeg.org/) and FFprobe as the media engine behind the Trim tool. They are installed separately and are not bundled with ToolBox. FFmpeg is primarily licensed under the LGPL 2.1 or later; builds containing optional GPL components are covered by the GPL 2 or later. See [Third-party notices](THIRD_PARTY_NOTICES.md) and [FFmpeg's official licensing information](https://ffmpeg.org/legal.html).

## MCP tool server

`toolbox-mcp` exposes every registered Toolbox utility over the Model Context Protocol using the official Python SDK. It uses the local `stdio` transport: an MCP host launches the command as a child process and communicates with it through standard input and output. It does not open a network port.

After running `./setup.sh`, add Toolbox to any MCP client using the absolute path to the launcher:

```json
{
  "mcpServers": {
    "toolbox": {
      "command": "/absolute/path/to/Toolbox/.venv/bin/toolbox-mcp"
    }
  }
}
```

For the installed copy, the command is:

```text
/Applications/Local Utilities/.venv/bin/toolbox-mcp
```

Restart the MCP client after changing its configuration. It can then discover and call:

- `convert-files` with ordered `files`, a `target` format, and an `output` file or folder
- `crop` with a `source`, relative `area` object, and `output` path
- `trim` with a `source`, `segment` object in seconds, and `output` path

Calls return both human-readable content and a structured result containing the tool name and resolved output path. Failures are returned as MCP tool errors so the calling model can correct its arguments. Input and output paths refer to files on the local Mac; only connect trusted MCP clients because tools can create or replace files at the requested output paths.

The server can also be launched directly for development:

```sh
./.venv/bin/toolbox-mcp
```

No terminal output is expected while it waits for an MCP client. Adding another function with the `@tool` decorator automatically publishes it through the GUI, CLI, and MCP server.

The setup installs the Python package in the project environment and creates CLI and MCP launchers that load `python/` directly. A new tool file becomes available to both launchers without rerunning setup. Run `./install-app.sh` and reopen the installed app to make the new tool available there.

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

The example is intentionally minimal; production tools should validate inputs and use `atomic_output` from `toolbox.files` so a failed run does not leave a partial result. Supported annotations are `Path`, `FileList`, `Rectangle`, `TimeRange`, `str`, `int`, `float`, `bool`, and string `Literal` choices. The `output` parameter is treated as a save destination. Each new tool is available through the CLI, generated app form, and MCP server after restarting the relevant client.

## Layout

- `python/`: plugin registry, CLI, and tools
- `python/toolbox/mcp_server.py`: MCP schemas, dispatch, and stdio server
- `mac/`: SwiftUI app
- `mac/Assets/AppIcon.svg`: white-background hammer icon used by `build-app.sh`
- `tests/`: CLI and tool checks

This is a personal local build. The installed app is signed locally and uses its adjacent Python environment. ToolBox has no updater or HTTP server.
