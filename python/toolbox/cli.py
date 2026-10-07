from __future__ import annotations

import argparse
import json
import sys
from dataclasses import asdict, is_dataclass
from pathlib import Path
from typing import Any

from .registry import all_tools, convert_value, get_tool


def emit(value: Any) -> None:
    print(json.dumps(value, default=lambda item: asdict(item) if is_dataclass(item) else str(item)))


def add_tool_arguments(parser: argparse.ArgumentParser, fields: list[dict[str, Any]]) -> None:
    for field in fields:
        flag = "--" + field["name"].replace("_", "-")
        kwargs: dict[str, Any] = {"required": field["required"], "help": field["label"]}
        if field["kind"] == "files":
            kwargs["nargs"] = "+"
        elif field["kind"] == "boolean":
            kwargs["choices"] = ["true", "false"]
        elif field["kind"] == "choice":
            kwargs["choices"] = field["choices"]
        if not field["required"]:
            kwargs["default"] = field["default"]
        parser.add_argument(flag, **kwargs)


def run(arguments: list[str]) -> int:
    parser = argparse.ArgumentParser(prog="toolbox", description="Local Mac utility tools")
    subparsers = parser.add_subparsers(dest="command", required=True)
    listing = subparsers.add_parser("list", help="List available tools")
    listing.add_argument("--json", action="store_true")
    describing = subparsers.add_parser("describe", help="Describe one tool")
    describing.add_argument("tool")
    describing.add_argument("--json", action="store_true")
    inspecting = subparsers.add_parser("inspect", help="Inspect an input file")
    inspecting.add_argument("path")
    inspecting.add_argument("--waveform", action="store_true", help="Include waveform display peaks for audio")
    inspecting.add_argument("--json", action="store_true")
    running = subparsers.add_parser("run", help="Run a tool")
    run_subparsers = running.add_subparsers(dest="tool", required=True)
    for entry in all_tools():
        tool_parser = run_subparsers.add_parser(entry.id, help=entry.description)
        add_tool_arguments(tool_parser, entry.fields())
        tool_parser.add_argument("--json", action="store_true")

    args = parser.parse_args(arguments)
    wants_json = getattr(args, "json", False)
    try:
        if args.command == "list":
            results = [{"id": entry.id, "title": entry.title, "description": entry.description} for entry in all_tools()]
            emit(results) if wants_json else [print(f"{item['id']}: {item['title']}") for item in results]
        elif args.command == "describe":
            result = get_tool(args.tool).describe()
            emit(result) if wants_json else print(json.dumps(result, indent=2))
        elif args.command == "inspect":
            path = Path(args.path).expanduser().resolve()
            if not path.is_file():
                raise ValueError(f"Input file does not exist: {path}")
            if path.suffix.lower() in {".mp3", ".m4a", ".wav"}:
                from .tools.trim_audio import audio_duration, audio_waveform

                duration = audio_duration(path)
                result = {"kind": "audio", "duration": duration}
                if args.waveform:
                    result["waveform"] = audio_waveform(path, duration)
            elif path.suffix.lower() == ".pdf":
                import pymupdf

                with pymupdf.open(path) as document:
                    result = {"kind": "pdf", "page_count": document.page_count}
            else:
                raise ValueError("No inspector for this file type")
            emit(result) if wants_json else print(result)
        else:
            entry = get_tool(args.tool)
            values = {
                field["name"]: convert_value(field, getattr(args, field["name"]))
                for field in entry.fields()
            }
            output = entry.function(**values)
            result = {"ok": True, "tool": entry.id, "output": str(output.resolve())}
            emit(result) if wants_json else print(result["output"])
        return 0
    except Exception as error:
        message = str(error) or error.__class__.__name__
        if wants_json:
            emit({"ok": False, "error": message})
        else:
            print(f"Error: {message}", file=sys.stderr)
        return 1


def main() -> None:
    raise SystemExit(run(sys.argv[1:]))


if __name__ == "__main__":
    main()
