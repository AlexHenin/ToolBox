from __future__ import annotations

import os
import tempfile
from contextlib import contextmanager
from pathlib import Path
from typing import Iterator


@contextmanager
def atomic_output(output: Path) -> Iterator[Path]:
    output = output.expanduser().resolve()
    if not output.parent.is_dir():
        raise ValueError(f"Output folder does not exist: {output.parent}")
    fd, name = tempfile.mkstemp(prefix=f".{output.stem}-", suffix=output.suffix, dir=output.parent)
    os.close(fd)
    temporary = Path(name)
    try:
        yield temporary
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)


def check_source(source: Path, extensions: set[str]) -> Path:
    source = source.expanduser().resolve()
    if not source.is_file():
        raise ValueError(f"Input file does not exist: {source}")
    if source.suffix.lower() not in extensions:
        raise ValueError(f"Unsupported input type: {source.suffix}")
    return source


def check_output(output: Path, source_paths: list[Path], extensions: set[str]) -> Path:
    output = output.expanduser().resolve()
    if output.suffix.lower() not in extensions:
        raise ValueError(f"Output must end in {', '.join(sorted(extensions))}")
    if output in [source.resolve() for source in source_paths]:
        raise ValueError("Output must differ from the input file")
    return output
