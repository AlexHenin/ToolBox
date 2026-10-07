import contextlib
import io
import json
import subprocess
import tempfile
import unittest
from pathlib import Path

import pymupdf
from PIL import Image

from toolbox import tool
from toolbox.cli import run


def command(*arguments: str) -> tuple[int, dict]:
    stdout = io.StringIO()
    with contextlib.redirect_stdout(stdout):
        code = run(list(arguments) + ["--json"])
    return code, json.loads(stdout.getvalue())


class ToolTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)

    def tearDown(self):
        self.temp.cleanup()

    def test_image_order_and_pdf_output(self):
        first = self.root / "red.png"
        second = self.root / "blue.jpg"
        Image.new("RGB", (40, 30), "red").save(first)
        Image.new("RGB", (30, 40), "blue").save(second)
        output = self.root / "images.pdf"
        code, result = command("run", "image-to-pdf", "--images", str(first), str(second), "--output", str(output))
        self.assertEqual(code, 0, result)
        with pymupdf.open(output) as document:
            self.assertEqual(document.page_count, 2)
            first_pixel = document[0].get_pixmap().pixel(20, 15)
            second_pixel = document[1].get_pixmap().pixel(15, 20)
            self.assertGreater(first_pixel[0], first_pixel[2])
            self.assertGreater(second_pixel[2], second_pixel[0])

    def test_crop_removes_outside_content_across_different_pages(self):
        source = self.root / "source.pdf"
        with pymupdf.open() as document:
            for width, height in [(400, 400), (600, 300)]:
                page = document.new_page(width=width, height=height)
                page.insert_text((width * 0.1, height * 0.1), "INSIDE")
                page.insert_text((width * 0.8, height * 0.8), "SECRET-OUTSIDE")
            document.save(source)
        output = self.root / "cropped.pdf"
        code, result = command("run", "crop-pdf", "--source", str(source), "--area", "0,0,0.5,0.5", "--output", str(output))
        self.assertEqual(code, 0, result)
        with pymupdf.open(output) as document:
            self.assertEqual(document.page_count, 2)
            self.assertEqual(document[0].rect.width, 200)
            self.assertEqual(document[1].rect.width, 300)
            self.assertEqual("".join(page.get_text() for page in document), "")
        self.assertNotIn(b"SECRET-OUTSIDE", output.read_bytes())
        bad_code, bad = command("run", "crop-pdf", "--source", str(source), "--area", "0.8,0,0.5,0.5", "--output", str(output))
        self.assertEqual(bad_code, 1)
        self.assertIn("outside", bad["error"])

    def test_audio_trim_and_invalid_range(self):
        source = self.root / "tone.wav"
        subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi", "-i", "sine=frequency=440:duration=3", str(source)], check=True)
        output = self.root / "trimmed.wav"
        code, result = command("run", "trim-audio", "--source", str(source), "--segment", "0.5,1.75", "--output", str(output))
        self.assertEqual(code, 0, result)
        probe_code, probe = command("inspect", str(output))
        self.assertEqual(probe_code, 0)
        self.assertAlmostEqual(probe["duration"], 1.25, delta=0.05)
        wave_code, waveform = command("inspect", str(output), "--waveform")
        self.assertEqual(wave_code, 0)
        self.assertEqual(len(waveform["waveform"]), 320)
        self.assertGreater(max(waveform["waveform"]), 0.1)
        bad_code, _ = command("run", "trim-audio", "--source", str(source), "--segment", "2,5", "--output", str(output))
        self.assertEqual(bad_code, 1)

    def test_new_decorated_tool_appears_in_catalog(self):
        @tool(title="Example", description="A plugin verification tool")
        def example_tool(message: str, output: Path) -> Path:
            output.write_text(message)
            return output

        code, listing = command("list")
        self.assertEqual(code, 0)
        self.assertIn("example-tool", [entry["id"] for entry in listing])
        code, definition = command("describe", "example-tool")
        self.assertEqual(code, 0)
        self.assertEqual([field["kind"] for field in definition["fields"]], ["text", "output"])

    def test_output_folder_failure_is_reported_without_partial_file(self):
        source = self.root / "image.png"
        Image.new("RGB", (10, 10), "green").save(source)
        output = self.root / "missing" / "result.pdf"
        code, result = command("run", "image-to-pdf", "--images", str(source), "--output", str(output))
        self.assertEqual(code, 1)
        self.assertIn("does not exist", result["error"])
        self.assertFalse(output.exists())


if __name__ == "__main__":
    unittest.main()
