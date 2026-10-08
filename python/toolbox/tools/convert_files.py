from __future__ import annotations

import os
import shutil
import subprocess
import tempfile
from pathlib import Path

from PIL import Image, ImageOps, ImageSequence, UnidentifiedImageError

from toolbox import FileList, tool
from toolbox.files import atomic_output, check_output


IMAGE_EXTENSIONS = {
    ".arw", ".avif", ".bmp", ".cr2", ".cr3", ".dds", ".dng", ".exr", ".gif",
    ".hdr", ".heic", ".heif", ".icns", ".ico", ".j2k", ".jpe", ".jpeg", ".jpg",
    ".jp2", ".jxl", ".nef", ".orf", ".pbm", ".pcx", ".pef", ".pgm", ".png",
    ".pnm", ".ppm", ".psd", ".raf", ".ras", ".rw2", ".sgi", ".sr2", ".svg",
    ".tga", ".tif", ".tiff", ".webp", ".xbm", ".xpm",
}

AUDIO_EXTENSIONS = {
    ".aa", ".aac", ".aax", ".ac3", ".aif", ".aifc", ".aiff", ".alac", ".amr",
    ".ape", ".au", ".caf", ".dts", ".eac3", ".flac", ".gsm", ".m4a", ".m4b",
    ".mka", ".mp2", ".mp3", ".mpc", ".oga", ".ogg", ".opus", ".ra", ".shn",
    ".spx", ".tta", ".voc", ".wav", ".wave", ".wma", ".wv",
}

VIDEO_EXTENSIONS = {
    ".3g2", ".3gp", ".amv", ".asf", ".avi", ".divx", ".dv", ".f4v", ".flv",
    ".gxf", ".m2ts", ".m2v", ".m4v", ".mkv", ".mov", ".mp4", ".mpeg", ".mpg",
    ".mts", ".mxf", ".nut", ".ogv", ".qt", ".rm", ".rmvb", ".roq", ".swf",
    ".ts", ".vob", ".webm", ".wmv", ".y4m",
}

DOCUMENT_EXTENSIONS = {
    ".csv", ".doc", ".docx", ".epub", ".htm", ".html", ".log", ".markdown",
    ".md", ".odt", ".pdf", ".rtf", ".rtfd", ".tex", ".text", ".tsv", ".txt",
    ".webarchive", ".xhtml", ".xml", ".yaml", ".yml",
}

AUDIO_TARGETS = ["mp3", "m4a", "aac", "wav", "flac", "alac", "ogg", "opus", "wma", "aiff", "ac3", "amr", "caf", "mka", "mp2"]
VIDEO_TARGETS = ["mp4", "mkv", "mov", "webm", "avi", "m4v", "flv", "wmv", "mpg", "mpeg", "ts", "ogv", "3gp", "prores", "gif"]
IMAGE_TARGETS = ["jpg", "png", "heic", "webp", "tiff", "gif", "bmp", "avif", "jp2", "ico", "tga", "ppm", "pdf"]
DOCUMENT_TARGETS = ["pdf", "docx", "rtf", "html", "txt", "md", "png", "jpg"]


@tool(
    title="Convert",
    description="Convert images, documents, audio, and video locally with Shark.",
)
def convert_files(files: FileList, target: str, output: Path) -> Path:
    sources = [_source(path) for path in files]
    if not sources:
        raise ValueError("Choose at least one file")
    target = target.strip().lower().removeprefix(".")
    if not target:
        raise ValueError("Choose an output format")

    if target == "pdf" and all(path.suffix.lower() in IMAGE_EXTENSIONS for path in sources):
        destination = check_output(output, sources, {".pdf"})
        _combine_as_pdf(sources, destination)
        return destination

    destination = output.expanduser().resolve()
    if not destination.is_dir():
        raise ValueError(f"Output folder does not exist: {destination}")
    _run_shark(sources, target, destination)
    return destination


def common_targets(files: list[Path]) -> list[str]:
    sources = [_source(path) for path in files]
    if not sources:
        return []
    shared = _targets_for(sources[0])
    for source in sources[1:]:
        available = set(_targets_for(source))
        shared = [target for target in shared if target in available]
    return shared


def _source(path: Path) -> Path:
    source = path.expanduser().resolve()
    if not source.is_file():
        raise ValueError(f"Input file does not exist: {source}")
    return source


def _targets_for(source: Path) -> list[str]:
    extension = source.suffix.lower()
    if extension in AUDIO_EXTENSIONS:
        return [*AUDIO_TARGETS, "mp4", "mkv", "mov"]
    if extension in VIDEO_EXTENSIONS:
        return [*VIDEO_TARGETS, *AUDIO_TARGETS]
    if extension in IMAGE_EXTENSIONS:
        return IMAGE_TARGETS.copy()
    if extension in DOCUMENT_EXTENSIONS:
        return DOCUMENT_TARGETS.copy()
    return list(dict.fromkeys([*AUDIO_TARGETS, *VIDEO_TARGETS, *IMAGE_TARGETS, *DOCUMENT_TARGETS]))


def _shark_executable() -> Path:
    configured = os.environ.get("SHARK_CLI")
    if configured:
        candidate = Path(configured).expanduser()
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate.resolve()
        raise ValueError(f"SHARK_CLI is not executable: {candidate}")
    discovered = shutil.which("shark")
    if discovered:
        return Path(discovered).resolve()
    for candidate in (
        Path("/opt/homebrew/bin/shark"),
        Path("/usr/local/bin/shark"),
        Path("/Applications/Shark.app/Contents/Helpers/shark"),
    ):
        if candidate.is_file() and os.access(candidate, os.X_OK):
            return candidate
    raise ValueError("Shark is not installed. Install it with Homebrew, then reopen Toolbox.")


def _run_shark(sources: list[Path], target: str, output_folder: Path) -> list[Path]:
    process = subprocess.run(
        [
            str(_shark_executable()), "convert",
            *(str(source) for source in sources),
            "--to", target,
            "--out", str(output_folder),
        ],
        capture_output=True,
        text=True,
        check=False,
    )
    if process.returncode != 0:
        message = process.stderr.strip() or process.stdout.strip() or "Shark could not complete the conversion"
        raise ValueError(message)
    outputs = [Path(line.strip()).resolve() for line in process.stdout.splitlines() if line.strip()]
    if not outputs:
        raise ValueError("Shark completed without reporting any output files")
    return outputs


def _combine_as_pdf(sources: list[Path], output: Path) -> None:
    with tempfile.TemporaryDirectory(prefix="toolbox-convert-", dir=output.parent) as temporary_name:
        temporary_folder = Path(temporary_name)
        pages: list[Image.Image] = []
        try:
            for source in sources:
                inputs = [source]
                try:
                    with Image.open(source) as image:
                        image.verify()
                except (UnidentifiedImageError, OSError):
                    inputs = _run_shark([source], "png", temporary_folder)
                for image_file in inputs:
                    with Image.open(image_file) as image:
                        for frame in ImageSequence.Iterator(image):
                            pages.append(_pdf_page(ImageOps.exif_transpose(frame.copy())))
            if not pages:
                raise ValueError("The selected images produced an empty document")
            with atomic_output(output) as temporary:
                pages[0].save(temporary, "PDF", save_all=True, append_images=pages[1:], resolution=72.0)
        finally:
            for page in pages:
                page.close()


def _pdf_page(image: Image.Image) -> Image.Image:
    if image.mode in {"RGBA", "LA"} or (image.mode == "P" and "transparency" in image.info):
        rgba = image.convert("RGBA")
        background = Image.new("RGBA", rgba.size, "white")
        background.alpha_composite(rgba)
        return background.convert("RGB")
    return image.convert("RGB")
