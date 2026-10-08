from __future__ import annotations

import inspect
import json
from pathlib import Path
from typing import Any

import anyio
import mcp.types as types
from mcp.server import Server, ServerRequestContext
from mcp.server.stdio import stdio_server

from .registry import Tool, all_tools, convert_value, get_tool


OUTPUT_SCHEMA: dict[str, Any] = {
    "type": "object",
    "properties": {
        "ok": {"type": "boolean"},
        "tool": {"type": "string"},
        "output": {"type": "string"},
    },
    "required": ["ok", "tool", "output"],
    "additionalProperties": False,
}


def _field_schema(field: dict[str, Any]) -> dict[str, Any]:
    kind = field["kind"]
    label = field["label"]
    if kind in {"file", "output"}:
        role = "output" if kind == "output" else "input"
        return {"type": "string", "description": f"Local {role} file path for {label.lower()}."}
    if kind == "files":
        return {
            "type": "array",
            "items": {"type": "string"},
            "minItems": 1,
            "description": f"Ordered local file paths for {label.lower()}.",
        }
    if kind == "rectangle":
        coordinate = {"type": "number", "minimum": 0, "maximum": 1}
        return {
            "type": "object",
            "description": "Relative crop rectangle; all values are between 0 and 1.",
            "properties": {key: coordinate for key in ("x", "y", "width", "height")},
            "required": ["x", "y", "width", "height"],
            "additionalProperties": False,
        }
    if kind == "time_range":
        return {
            "type": "object",
            "description": "Start and end times in seconds.",
            "properties": {
                "start": {"type": "number", "minimum": 0},
                "end": {"type": "number", "minimum": 0},
            },
            "required": ["start", "end"],
            "additionalProperties": False,
        }
    if kind == "integer":
        return {"type": "integer", "description": label}
    if kind == "number":
        return {"type": "number", "description": label}
    if kind == "boolean":
        return {"type": "boolean", "description": label}
    if kind == "choice":
        return {"type": "string", "enum": field["choices"], "description": label}
    return {"type": "string", "description": label}


def _input_schema(entry: Tool) -> dict[str, Any]:
    fields = entry.fields()
    properties: dict[str, Any] = {}
    required: list[str] = []
    for field in fields:
        schema = _field_schema(field)
        if not field["required"]:
            schema["default"] = field["default"]
        else:
            required.append(field["name"])
        properties[field["name"]] = schema
    return {
        "type": "object",
        "properties": properties,
        "required": required,
        "additionalProperties": False,
    }


def _mcp_tool(entry: Tool) -> types.Tool:
    return types.Tool(
        name=entry.id,
        title=entry.title,
        description=entry.description,
        input_schema=_input_schema(entry),
        output_schema=OUTPUT_SCHEMA,
    )


def _arguments_for(entry: Tool, supplied: dict[str, Any]) -> dict[str, Any]:
    fields = entry.fields()
    known = {field["name"] for field in fields}
    unexpected = sorted(set(supplied) - known)
    if unexpected:
        raise ValueError(f"Unexpected argument(s): {', '.join(unexpected)}")

    arguments: dict[str, Any] = {}
    signature = inspect.signature(entry.function)
    for field in fields:
        name = field["name"]
        if name in supplied:
            arguments[name] = convert_value(field, supplied[name])
        elif field["required"]:
            raise ValueError(f"Missing required argument: {name}")
        else:
            arguments[name] = signature.parameters[name].default
    return arguments


async def _list_tools(
    context: ServerRequestContext,
    params: types.PaginatedRequestParams | None,
) -> types.ListToolsResult:
    del context, params
    return types.ListToolsResult(tools=[_mcp_tool(entry) for entry in all_tools()])


async def _call_tool(
    context: ServerRequestContext,
    params: types.CallToolRequestParams,
) -> types.CallToolResult:
    del context
    try:
        entry = get_tool(params.name)
        arguments = _arguments_for(entry, params.arguments or {})
        output = await anyio.to_thread.run_sync(lambda: entry.function(**arguments))
        if not isinstance(output, Path):
            raise TypeError(f"{entry.id} returned an unsupported result")
        result = {"ok": True, "tool": entry.id, "output": str(output.resolve())}
        return types.CallToolResult(
            content=[types.TextContent(type="text", text=json.dumps(result))],
            structured_content=result,
            is_error=False,
        )
    except Exception as error:
        message = str(error) or error.__class__.__name__
        return types.CallToolResult(
            content=[types.TextContent(type="text", text=message)],
            is_error=True,
        )


server = Server(
    "toolbox",
    version="0.1.0",
    title="Toolbox",
    description="Local file conversion, cropping, and media trimming tools.",
    instructions="All input and output paths refer to files on this Mac.",
    on_list_tools=_list_tools,
    on_call_tool=_call_tool,
)


async def _serve() -> None:
    async with stdio_server() as (read_stream, write_stream):
        await server.run(read_stream, write_stream, server.create_initialization_options())


def main() -> None:
    anyio.run(_serve)


if __name__ == "__main__":
    main()
