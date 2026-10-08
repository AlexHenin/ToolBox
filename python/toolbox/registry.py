from __future__ import annotations

import importlib
import inspect
import pkgutil
from dataclasses import asdict, dataclass
from pathlib import Path
from typing import Any, Callable, Literal, get_args, get_origin, get_type_hints


@dataclass(frozen=True)
class Rectangle:
    """Relative page coordinates, each between zero and one."""

    x: float
    y: float
    width: float
    height: float


@dataclass(frozen=True)
class TimeRange:
    start: float
    end: float


class FileList(list[Path]):
    """An ordered list of input files."""


@dataclass
class Tool:
    id: str
    title: str
    description: str
    function: Callable[..., Any]
    extensions: dict[str, list[str]]

    def fields(self) -> list[dict[str, Any]]:
        hints = get_type_hints(self.function)
        fields: list[dict[str, Any]] = []
        for name, param in inspect.signature(self.function).parameters.items():
            annotation = hints[name]
            origin = get_origin(annotation)
            choices = list(get_args(annotation)) if origin is Literal else []
            if annotation is Path:
                kind = "output" if name == "output" else "file"
            elif annotation is FileList:
                kind = "files"
            elif annotation is Rectangle:
                kind = "rectangle"
            elif annotation is TimeRange:
                kind = "time_range"
            elif annotation is bool:
                kind = "boolean"
            elif annotation is int:
                kind = "integer"
            elif annotation is float:
                kind = "number"
            elif annotation is str:
                kind = "text"
            elif choices and all(isinstance(x, str) for x in choices):
                kind = "choice"
            else:
                raise TypeError(f"Unsupported field {name}: {annotation}")
            field: dict[str, Any] = {
                "name": name,
                "label": name.replace("_", " ").title(),
                "kind": kind,
                "required": param.default is inspect.Parameter.empty,
                "extensions": self.extensions.get(name, []),
            }
            if choices:
                field["choices"] = choices
            if param.default is not inspect.Parameter.empty:
                field["default"] = param.default
            fields.append(field)
        return fields

    def describe(self) -> dict[str, Any]:
        return {
            "id": self.id,
            "title": self.title,
            "description": self.description,
            "fields": self.fields(),
        }


_TOOLS: dict[str, Tool] = {}
_LOADED = False


def tool(*, title: str, description: str, extensions: dict[str, list[str]] | None = None):
    """Register a typed function as both a CLI command and a generated app form."""

    def decorate(function: Callable[..., Any]) -> Callable[..., Any]:
        identifier = function.__name__.replace("_", "-")
        if identifier in _TOOLS:
            raise ValueError(f"Duplicate tool id: {identifier}")
        entry = Tool(identifier, title, description, function, extensions or {})
        entry.fields()  # Reject unsupported annotations at registration time.
        _TOOLS[identifier] = entry
        return function

    return decorate


def all_tools() -> list[Tool]:
    global _LOADED
    if not _LOADED:
        from . import tools

        for module in pkgutil.iter_modules(tools.__path__, tools.__name__ + "."):
            importlib.import_module(module.name)
        _LOADED = True
    return list(_TOOLS.values())


def get_tool(identifier: str) -> Tool:
    for entry in all_tools():
        if entry.id == identifier:
            return entry
    raise ValueError(f"Unknown tool: {identifier}")


def convert_value(field: dict[str, Any], raw: Any) -> Any:
    kind = field["kind"]
    if kind in ("file", "output"):
        value = Path(raw).expanduser()
    elif kind == "files":
        value = FileList(Path(item).expanduser() for item in raw)
    elif kind == "rectangle":
        if isinstance(raw, dict):
            parts = [raw.get(key) for key in ("x", "y", "width", "height")]
        else:
            parts = raw if isinstance(raw, (list, tuple)) else str(raw).split(",")
        if len(parts) != 4:
            raise ValueError("Rectangle needs x,y,width,height")
        value = Rectangle(*(float(part) for part in parts))
    elif kind == "time_range":
        if isinstance(raw, dict):
            parts = [raw.get(key) for key in ("start", "end")]
        else:
            parts = raw if isinstance(raw, (list, tuple)) else str(raw).split(",")
        if len(parts) != 2:
            raise ValueError("Time range needs start,end in seconds")
        value = TimeRange(*(float(part) for part in parts))
    elif kind == "integer":
        value = int(raw)
    elif kind == "number":
        value = float(raw)
    elif kind == "boolean":
        value = raw if isinstance(raw, bool) else str(raw).lower() in ("1", "true", "yes")
    else:
        value = str(raw)
    if kind == "choice" and value not in field["choices"]:
        raise ValueError(f"{field['name']} must be one of {field['choices']}")
    return value
