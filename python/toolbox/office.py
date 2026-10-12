from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

import pymupdf

from toolbox.files import atomic_output


def libreoffice_executable() -> Path:
    configured = os.environ.get("LIBREOFFICE_CLI")
    if configured:
        candidate = Path(configured).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
        raise ValueError(f"LIBREOFFICE_CLI is not executable: {candidate}")
    discovered = shutil.which("soffice") or shutil.which("libreoffice")
    candidates = [
        Path(discovered) if discovered else None,
        Path("/Applications/LibreOffice.app/Contents/MacOS/soffice"),
        Path.home() / "Applications/LibreOffice.app/Contents/MacOS/soffice",
        Path("/opt/homebrew/bin/soffice"),
        Path("/usr/local/bin/soffice"),
    ]
    for candidate in candidates:
        if candidate and candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
    raise ValueError(
        "LibreOffice is required for Word-to-PDF conversion to preserve images and layout. "
        "Install it with: brew install --cask libreoffice"
    )


def convert_to_pdf(source: Path, output_folder: Path) -> Path:
    executable = libreoffice_executable()
    # A separate profile prevents requests from being handed to an open GUI session.
    # A private output folder also avoids confusing a stale PDF with a successful export.
    with tempfile.TemporaryDirectory(prefix="toolbox-office-") as name:
        workspace = Path(name)
        profile = workspace / "profile"
        exports = workspace / "exports"
        exports.mkdir()
        try:
            process = subprocess.run(
                [
                    str(executable), f"-env:UserInstallation={profile.as_uri()}",
                    "--headless", "--nologo", "--nodefault", "--norestore",
                    "--convert-to", "pdf:writer_pdf_Export",
                    "--outdir", str(exports), str(source),
                ],
                capture_output=True, text=True, check=False, timeout=180,
            )
        except subprocess.TimeoutExpired as error:
            raise ValueError(f"LibreOffice timed out converting {source.name}") from error
        exported = exports / f"{source.stem}.pdf"
        if process.returncode != 0 or not exported.is_file():
            detail = process.stderr.strip() or process.stdout.strip() or "No PDF was produced"
            raise ValueError(f"LibreOffice could not convert {source.name}: {detail}")
        try:
            with pymupdf.open(exported) as document:
                if not document.is_pdf or document.page_count == 0:
                    raise ValueError("The exported PDF has no pages")
        except (RuntimeError, ValueError) as error:
            raise ValueError(f"LibreOffice produced an invalid PDF for {source.name}") from error

        destination = output_folder / f"{source.stem}.pdf"
        number = 2
        while destination.exists():
            destination = output_folder / f"{source.stem} ({number}).pdf"
            number += 1
        with atomic_output(destination) as temporary:
            shutil.copyfile(exported, temporary)
        return destination
