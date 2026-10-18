import contextlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import unittest
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("worker", ROOT / "worker/server.py")
worker = importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)


class WorkerTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        worker.TOKEN = "a" * 64
        cls.server = worker.http.server.HTTPServer(("127.0.0.1", 0), worker.Handler)
        cls.url = "http://127.0.0.1:" + str(cls.server.server_port)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.thread.join()

    def request(self, path, data=None, token=True, headers=None):
        request = urllib.request.Request(self.url + path, data=data, headers=headers or {})
        if token:
            request.add_header("Authorization", "Bearer " + worker.TOKEN)
        try:
            with urllib.request.urlopen(request, timeout=30) as response:
                return response.status, response.read()
        except urllib.error.HTTPError as error:
            with error:
                return error.code, error.read()

    def test_health(self):
        self.assertEqual(self.request("/health", token=False)[0], 200)

    def test_auth_required(self):
        self.assertEqual(self.request("/convert?format=webp", b"x", token=False)[0], 401)

    def test_format_allowlist(self):
        for fmt in ["../../etc/passwd", "png", "webp%3Btouch%20/tmp/bad"]:
            self.assertEqual(self.request("/convert?format=" + fmt, b"x")[0], 400)

    def test_reject_empty_upload(self):
        self.assertEqual(self.request("/convert?format=webp", b"")[0], 413)

    def test_reject_oversize_before_reading_body(self):
        self.assertEqual(self.request("/convert?format=webp", b"x", headers={"Content-Length": str(worker.MAX_INPUT + 1)})[0], 413)

    def test_reject_corrupt_media(self):
        self.assertEqual(self.request("/convert?format=webp", b"not an image")[0], 422)

    def test_real_conversions(self):
        with tempfile.TemporaryDirectory() as tmp:
            source = Path(tmp) / "source.mp4"
            subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=128x96:d=0.5", "-f", "lavfi", "-i", "sine=frequency=440:duration=0.5", "-c:v", "libx264", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(source)], check=True)
            for fmt, signature in [("webp", b"RIFF"), ("mp4", b"ftyp"), ("mp3", b"ID3"), ("gif", b"GIF")]:
                with self.subTest(fmt=fmt):
                    status, data = self.request("/convert?format=" + fmt, source.read_bytes())
                    self.assertEqual(status, 200, data)
                    self.assertIn(signature, data[:16])
                    result = Path(tmp) / ("result." + fmt)
                    result.write_bytes(data)
                    subprocess.run(["ffprobe", "-v", "error", str(result)], check=True)

    def test_network_protocols_disabled(self):
        # A playlist must never make ffmpeg fetch a remote URL.
        playlist = b"#EXTM3U\n#EXT-X-TARGETDURATION:10\n#EXTINF:10,\nhttp://127.0.0.1:1/private.ts\n#EXT-X-ENDLIST\n"
        self.assertEqual(self.request("/convert?format=mp4", playlist)[0], 422)


if __name__ == "__main__":
    unittest.main()
