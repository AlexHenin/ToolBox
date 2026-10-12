import io
import os
import subprocess
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

import pymupdf
from PIL import Image

from toolbox.office import convert_to_pdf, libreoffice_executable
from toolbox.tools.convert_files import convert_files


class OfficeConversionTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary.name)
        self.source = self.root / "worked solutions.docx"
        self.source.touch()
        self.output = self.root / "output"
        self.output.mkdir()

    def tearDown(self):
        self.temporary.cleanup()

    def export(self, arguments, **kwargs):
        folder = Path(arguments[arguments.index("--outdir") + 1])
        with pymupdf.open() as document:
            document.new_page().insert_text((72, 72), "Converted document")
            document.save(folder / f"{Path(arguments[-1]).stem}.pdf")
        self.assertTrue(any(arg.startswith("-env:UserInstallation=file:") for arg in arguments))
        self.assertIn("pdf:writer_pdf_Export", arguments)
        self.assertEqual(kwargs["timeout"], 180)
        return subprocess.CompletedProcess(arguments, 0, "", "")

    def test_docx_pdf_bypasses_shark_and_preserves_existing_outputs(self):
        existing = self.output / f"{self.source.stem}.pdf"
        existing.write_bytes(b"existing file")
        with patch("toolbox.office.libreoffice_executable", return_value=Path("/soffice")), \
             patch("toolbox.office.subprocess.run", side_effect=self.export), \
             patch("toolbox.tools.convert_files._run_shark") as shark:
            result = convert_files([self.source, self.source], "pdf", self.output)
        self.assertEqual(result, self.output.resolve())
        shark.assert_not_called()
        self.assertEqual(existing.read_bytes(), b"existing file")
        for suffix in (" (2)", " (3)"):
            with pymupdf.open(self.output / f"{self.source.stem}{suffix}.pdf") as document:
                self.assertEqual(document.page_count, 1)

    def test_mixed_batch_routes_each_input_to_its_engine(self):
        image = self.root / "image.png"
        Image.new("RGB", (20, 20), "red").save(image)
        with patch("toolbox.tools.convert_files.convert_to_pdf") as office, \
             patch("toolbox.tools.convert_files._run_shark") as shark:
            convert_files([self.source, image], "pdf", self.output)
        office.assert_called_once_with(self.source.resolve(), self.output.resolve())
        shark.assert_called_once_with([image.resolve()], "pdf", self.output.resolve())

    def test_non_pdf_word_conversion_still_uses_shark(self):
        with patch("toolbox.tools.convert_files.convert_to_pdf") as office, \
             patch("toolbox.tools.convert_files._run_shark") as shark:
            convert_files([self.source], "txt", self.output)
        office.assert_not_called()
        shark.assert_called_once()

    def test_no_output_nonzero_exit_invalid_pdf_and_timeout_are_errors(self):
        def invalid_export(arguments, **kwargs):
            folder = Path(arguments[arguments.index("--outdir") + 1])
            (folder / f"{self.source.stem}.pdf").write_bytes(b"not a pdf")
            return subprocess.CompletedProcess(arguments, 0, "", "")

        cases = [
            (subprocess.CompletedProcess([], 0, "", ""), "No PDF was produced"),
            (subprocess.CompletedProcess([], 1, "", "Export failed"), "Export failed"),
            (invalid_export, "invalid PDF"),
            (subprocess.TimeoutExpired("soffice", 180), "timed out"),
        ]
        for behavior, message in cases:
            with self.subTest(message=message), \
                 patch("toolbox.office.libreoffice_executable", return_value=Path("/soffice")), \
                 patch("toolbox.office.subprocess.run") as run:
                if callable(behavior) or isinstance(behavior, Exception):
                    run.side_effect = behavior
                else:
                    run.return_value = behavior
                with self.assertRaisesRegex(ValueError, message):
                    convert_to_pdf(self.source, self.output)
                self.assertEqual(list(self.output.iterdir()), [])

    def test_invalid_configured_executable_is_reported(self):
        with patch.dict(os.environ, {"LIBREOFFICE_CLI": str(self.root / "missing")}):
            with self.assertRaisesRegex(ValueError, "LIBREOFFICE_CLI is not executable"):
                libreoffice_executable()

    def test_missing_libreoffice_does_not_fall_back_to_lossy_conversion(self):
        with patch("toolbox.office.libreoffice_executable", side_effect=ValueError("LibreOffice is required")), \
             patch("toolbox.tools.convert_files._run_shark") as shark:
            with self.assertRaisesRegex(ValueError, "LibreOffice is required"):
                convert_files([self.source], "pdf", self.output)
        shark.assert_not_called()
        self.assertEqual(list(self.output.iterdir()), [])

    def test_real_docx_export_retains_image_page_break_and_native_math(self):
        try:
            libreoffice_executable()
        except ValueError as error:
            self.skipTest(str(error))
        # A small OOXML fixture makes the lost-images regression reproducible
        # without committing a user's homework or depending on python-docx.
        image = io.BytesIO()
        Image.new("RGB", (80, 30), "red").save(image, "PNG")
        with zipfile.ZipFile(self.source, "w") as package:
            package.writestr("[Content_Types].xml", '''<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
              <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
              <Default Extension="xml" ContentType="application/xml"/>
              <Default Extension="png" ContentType="image/png"/>
              <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
            </Types>''')
            package.writestr("_rels/.rels", '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
            </Relationships>''')
            package.writestr("word/_rels/document.xml.rels", '''<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
              <Relationship Id="image1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" Target="media/equation.png"/>
            </Relationships>''')
            package.writestr("word/media/equation.png", image.getvalue())
            package.writestr("word/document.xml", '''<w:document
              xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"
              xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"
              xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
              xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main"
              xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture"
              xmlns:m="http://schemas.openxmlformats.org/officeDocument/2006/math">
              <w:body><w:p><w:r><w:t>First page with equation image</w:t></w:r></w:p>
              <w:p><w:r><w:drawing><wp:inline>
                <wp:extent cx="1524000" cy="571500"/><wp:docPr id="1" name="Equation image"/>
                <a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>
                  <pic:nvPicPr><pic:cNvPr id="1" name="Equation"/><pic:cNvPicPr/></pic:nvPicPr>
                  <pic:blipFill><a:blip r:embed="image1"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>
                  <pic:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1524000" cy="571500"/></a:xfrm>
                  <a:prstGeom prst="rect"><a:avLst/></a:prstGeom></pic:spPr>
                </pic:pic></a:graphicData></a:graphic>
              </wp:inline></w:drawing></w:r></w:p>
              <w:p><m:oMath><m:f><m:num><m:r><m:t>1</m:t></m:r></m:num>
                <m:den><m:r><m:t>2</m:t></m:r></m:den></m:f></m:oMath></w:p>
              <w:p><w:r><w:br w:type="page"/></w:r></w:p>
              <w:p><w:r><w:t>Second page after explicit break</w:t></w:r></w:p>
              <w:sectPr><w:pgSz w:w="12240" w:h="15840"/>
              <w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440"/></w:sectPr>
              </w:body></w:document>''')
        convert_files([self.source], "pdf", self.output)
        with pymupdf.open(self.output / f"{self.source.stem}.pdf") as document:
            self.assertEqual(document.page_count, 2)
            self.assertIn("First page", document[0].get_text())
            self.assertIn("Second page", document[1].get_text())
            self.assertEqual(len(document[0].get_image_info()), 1)
            self.assertIn("1", document[0].get_text())
            self.assertIn("2", document[0].get_text())
            self.assertEqual(document[0].rect, pymupdf.Rect(0, 0, 612, 792))


if __name__ == "__main__":
    unittest.main()
