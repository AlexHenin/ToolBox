from pathlib import Path

import pymupdf
from PIL import Image, ImageOps, ImageSequence

from toolbox import Rectangle, tool
from toolbox.files import atomic_output, check_output, check_source


Image.init()
_REGISTERED_EXTENSIONS = Image.registered_extensions()
_IMAGE_INPUT_EXTENSIONS = sorted(
    extension.removeprefix(".")
    for extension, image_format in _REGISTERED_EXTENSIONS.items()
    if image_format in Image.OPEN
)
_IMAGE_OUTPUT_EXTENSIONS = sorted(
    extension.removeprefix(".")
    for extension, image_format in _REGISTERED_EXTENSIONS.items()
    if image_format in Image.SAVE and extension != ".pdf"
)
_SOURCE_EXTENSIONS = ["pdf", *_IMAGE_INPUT_EXTENSIONS]
_OUTPUT_EXTENSIONS = ["pdf", *_IMAGE_OUTPUT_EXTENSIONS]


@tool(
    title="Crop",
    description="Keep a selected relative area and remove everything outside it.",
    extensions={"source": _SOURCE_EXTENSIONS, "output": _OUTPUT_EXTENSIONS},
)
def crop(source: Path, area: Rectangle, output: Path, dpi: int = 200) -> Path:
    source = check_source(source, {f".{extension}" for extension in _SOURCE_EXTENSIONS})
    output = check_output(output, [source], {f".{extension}" for extension in _OUTPUT_EXTENSIONS})
    _validate_area(area)
    if not 72 <= dpi <= 600:
        raise ValueError("DPI must be between 72 and 600")

    if source.suffix.lower() == ".pdf":
        if output.suffix.lower() != ".pdf":
            raise ValueError("A multi-page document must be saved as a document")
        _crop_document(source, area, output, dpi)
    else:
        _crop_image(source, area, output)
    return output


def _validate_area(area: Rectangle) -> None:
    if not (0 <= area.x < 1 and 0 <= area.y < 1 and 0 < area.width <= 1 and 0 < area.height <= 1):
        raise ValueError("Crop coordinates must be within the source")
    if area.x + area.width > 1.000001 or area.y + area.height > 1.000001:
        raise ValueError("Crop rectangle extends outside the source")


def _crop_document(source: Path, area: Rectangle, output: Path, dpi: int) -> None:
    with pymupdf.open(source) as original, pymupdf.open() as result:
        if original.page_count == 0:
            raise ValueError("Document has no pages")
        for page in original:
            bounds = page.rect
            clip = pymupdf.Rect(
                bounds.x0 + bounds.width * area.x,
                bounds.y0 + bounds.height * area.y,
                bounds.x0 + bounds.width * (area.x + area.width),
                bounds.y0 + bounds.height * (area.y + area.height),
            )
            pixmap = page.get_pixmap(clip=clip, dpi=dpi, alpha=False)
            target = result.new_page(width=clip.width, height=clip.height)
            target.insert_image(target.rect, pixmap=pixmap)
        with atomic_output(output) as temporary:
            result.save(temporary, garbage=4, deflate=True)


def _crop_image(source: Path, area: Rectangle, output: Path) -> None:
    output_format = _REGISTERED_EXTENSIONS.get(output.suffix.lower())
    if output_format not in Image.SAVE:
        raise ValueError(f"Unsupported output type: {output.suffix}")

    with Image.open(source) as original:
        frames = []
        durations = []
        for frame in ImageSequence.Iterator(original):
            oriented = ImageOps.exif_transpose(frame.copy())
            left = round(oriented.width * area.x)
            top = round(oriented.height * area.y)
            right = round(oriented.width * (area.x + area.width))
            bottom = round(oriented.height * (area.y + area.height))
            frames.append(oriented.crop((left, top, max(left + 1, right), max(top + 1, bottom))))
            durations.append(frame.info.get("duration", original.info.get("duration", 0)))

        if not frames:
            raise ValueError("Image has no frames")

        if output_format in {"JPEG", "PDF"}:
            frames = [_flatten_alpha(frame) for frame in frames]

        save_options = {}
        if len(frames) > 1 and output_format in Image.SAVE_ALL:
            save_options.update(save_all=True, append_images=frames[1:], duration=durations, loop=original.info.get("loop", 0))
        if "icc_profile" in original.info:
            save_options["icc_profile"] = original.info["icc_profile"]

        with atomic_output(output) as temporary:
            frames[0].save(temporary, format=output_format, **save_options)


def _flatten_alpha(image: Image.Image) -> Image.Image:
    if image.mode in {"RGBA", "LA"} or (image.mode == "P" and "transparency" in image.info):
        rgba = image.convert("RGBA")
        background = Image.new("RGBA", rgba.size, "white")
        background.alpha_composite(rgba)
        return background.convert("RGB")
    return image.convert("RGB")
