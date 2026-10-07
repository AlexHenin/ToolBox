from pathlib import Path

import pymupdf

from toolbox import Rectangle, tool
from toolbox.files import atomic_output, check_output, check_source


@tool(
    title="Crop PDF",
    description="Keep the same relative area on every page and remove the rest by rendering new pages.",
    extensions={"source": ["pdf"], "output": ["pdf"]},
)
def crop_pdf(source: Path, area: Rectangle, output: Path, dpi: int = 200) -> Path:
    source = check_source(source, {".pdf"})
    output = check_output(output, [source], {".pdf"})
    if not (0 <= area.x < 1 and 0 <= area.y < 1 and 0 < area.width <= 1 and 0 < area.height <= 1):
        raise ValueError("Crop coordinates must be within the page")
    if area.x + area.width > 1.000001 or area.y + area.height > 1.000001:
        raise ValueError("Crop rectangle extends outside the page")
    if not 72 <= dpi <= 600:
        raise ValueError("DPI must be between 72 and 600")
    with pymupdf.open(source) as original, pymupdf.open() as result:
        if original.page_count == 0:
            raise ValueError("PDF has no pages")
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
    return output
