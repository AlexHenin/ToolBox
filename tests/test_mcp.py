import tempfile
import unittest
from pathlib import Path

from mcp import Client
from PIL import Image

from toolbox.mcp_server import server


class MCPTests(unittest.IsolatedAsyncioTestCase):
    async def test_lists_registered_tools_with_structured_schemas(self):
        async with Client(server) as client:
            result = await client.list_tools()

        tools = {tool.name: tool for tool in result.tools}
        self.assertTrue({"convert-files", "crop", "trim"}.issubset(tools))
        self.assertEqual(tools["crop"].input_schema["properties"]["area"]["type"], "object")
        self.assertEqual(tools["trim"].input_schema["properties"]["segment"]["type"], "object")

    async def test_calls_crop_and_returns_structured_output(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            source = root / "source.png"
            output = root / "cropped.png"
            Image.new("RGB", (40, 30), "red").save(source)

            async with Client(server) as client:
                result = await client.call_tool(
                    "crop",
                    {
                        "source": str(source),
                        "area": {"x": 0, "y": 0, "width": 0.5, "height": 0.5},
                        "output": str(output),
                    },
                )

            self.assertFalse(result.is_error)
            self.assertEqual(result.structured_content["tool"], "crop")
            self.assertEqual(Path(result.structured_content["output"]), output.resolve())
            with Image.open(output) as cropped:
                self.assertEqual(cropped.size, (20, 15))

    async def test_returns_tool_errors_to_the_client(self):
        async with Client(server) as client:
            result = await client.call_tool("crop", {"source": "/missing.png"})

        self.assertTrue(result.is_error)
        self.assertIn("Missing required argument", result.content[0].text)


if __name__ == "__main__":
    unittest.main()
