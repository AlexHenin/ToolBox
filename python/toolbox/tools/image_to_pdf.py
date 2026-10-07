from pathlib import Path

from PIL import Image, ImageOps

from toolbox import FileList, tool
from toolbox.files import atomic_output, check_output, check_source


@tool(
    title="Image to PDF",
    description="Turn ordered PNG or JPEG images into a PDF, one image per page.",
    extensions={"images": ["png", "jpg", "jpeg"], "output": ["pdf"]},
)
def image_to_pdf(images: FileList, output: Path) -> Path:
    if not images:
        raise ValueError("Choose at least one image")
    sources = [check_source(path, {".png", ".jpg", ".jpeg"}) for path in images]
    output = check_output(output, sources, {".pdf"})
    pages: list[Image.Image] = []
    try:
        for source in sources:
            with Image.open(source) as image:
                if image.format not in {"PNG", "JPEG"}:
                    raise ValueError(f"Unsupported image content: {source}")
                upright = ImageOps.exif_transpose(image)
                if upright.mode == "RGBA" or "transparency" in upright.info:
                    background = Image.new("RGB", upright.size, "white")
                    background.paste(upright.convert("RGBA"), mask=upright.convert("RGBA").getchannel("A"))
                    pages.append(background)
                else:
                    pages.append(upright.convert("RGB"))
        with atomic_output(output) as temporary:
            pages[0].save(temporary, "PDF", save_all=True, append_images=pages[1:], resolution=72.0)
    finally:
        for page in pages:
            page.close()
    return output
