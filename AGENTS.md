# Toolbox project guide

- This folder is the editable source project. The installed app is at `/Applications/Local Utilities/Toolbox.app`; edit here, then run `./install-app.sh` to update it.
- SwiftUI GUI code is in `mac/Sources/ToolboxApp/`. The icon source is `mac/Assets/AppIcon.svg`; `build-app.sh` generates the `.icns` file.
- Python CLI, registry, and tool implementations are in `python/toolbox/`. Add a tool as a new file in `python/toolbox/tools/` using the `@tool` decorator. The GUI reads tool definitions from the CLI, so ordinary new tools need no Swift changes.
- The local CLI is `./.venv/bin/toolbox`. If `.venv` is missing, run `./setup.sh`. Audio tools also need FFmpeg.
- Check Python changes with `PYTHONPATH=python .venv/bin/python -m unittest discover -s tests`. Use `./install-app.sh` after changes that should appear in the installed app.
- `.venv`, Swift build output, and `Toolbox.app` are generated and ignored by Git. Keep source changes in this project folder.
