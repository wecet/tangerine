"""One request at a time, bounded disk streaming, no framework or background jobs."""
import hmac
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
from urllib.parse import parse_qs, urlsplit

MAX_INPUT = 128 * 1024 * 1024
MAX_OUTPUT = 192 * 1024 * 1024
TOKEN = os.environ.get("TANGERINE_TOKEN", "")


def command(source, destination, fmt):
    common = ["ffmpeg", "-hide_banner", "-loglevel", "error", "-nostdin", "-y",
              "-max_alloc", "67108864", "-protocol_whitelist", "file,pipe",
              "-threads", "1", "-filter_threads", "1", "-i", str(source),
              "-map_metadata", "-1", "-threads", "1", "-fs", str(MAX_OUTPUT)]
    options = {
        "webp": ["-frames:v", "1", "-vf", "scale='min(2400,iw)':-2", "-c:v", "libwebp", "-quality", "85"],
        "mp4": ["-map", "0:v:0", "-map", "0:a:0?", "-vf", "scale='min(1280,iw)':-2,pad=ceil(iw/2)*2:ceil(ih/2)*2", "-c:v", "libx264", "-preset", "ultrafast", "-crf", "24", "-pix_fmt", "yuv420p", "-c:a", "aac", "-movflags", "+faststart"],
        "mp3": ["-vn", "-c:a", "libmp3lame", "-b:a", "192k"],
        "gif": ["-an", "-t", "30", "-vf", "fps=12,scale='min(640,iw)':-2"],
    }
    return common + options[fmt] + [str(destination)]


class Handler(http.server.BaseHTTPRequestHandler):
    server_version = "Tangerine"
    sys_version = ""
    timeout = 30

    def setup(self):
        super().setup()
        self.connection.settimeout(30)

    def log_message(self, *_):
        pass  # Do not log tokens, paths, or file contents.

    def reply(self, status, message):
        body = json.dumps({"message": message}).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(body)
        self.close_connection = True

    def do_GET(self):
        if self.path == "/health":
            self.reply(200, "ready")
        else:
            self.reply(404, "not found")

    def do_POST(self):
        if not TOKEN or not hmac.compare_digest(self.headers.get("Authorization", "").encode(), ("Bearer " + TOKEN).encode()):
            self.reply(401, "unauthorized")
            return
        parsed = urlsplit(self.path)
        fmt = parse_qs(parsed.query).get("format", [""])[0]
        if parsed.path != "/convert" or fmt not in {"webp", "mp4", "mp3", "gif"}:
            self.reply(400, "unsupported conversion")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            self.reply(400, "invalid content length")
            return
        if self.headers.get("Transfer-Encoding") or not 0 < length <= MAX_INPUT:
            self.reply(413, "send a Content-Length from 1 byte to 128 MiB")
            return
        try:
            with tempfile.TemporaryDirectory(prefix="tangerine-") as tmp:
                source = Path(tmp) / "input"
                destination = Path(tmp) / ("output." + fmt)
                with source.open("wb") as stream:
                    remaining = length
                    while remaining:
                        chunk = self.rfile.read(min(65536, remaining))
                        if not chunk:
                            self.reply(400, "incomplete upload")
                            return
                        stream.write(chunk)
                        remaining -= len(chunk)
                result = subprocess.run(command(source, destination, fmt), stdin=subprocess.DEVNULL,
                                        stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=300)
                if result.returncode or not destination.exists() or not 0 < destination.stat().st_size < MAX_OUTPUT:
                    self.reply(422, "unsupported, oversized, or invalid media")
                    return
                self.send_response(200)
                self.send_header("Content-Type", {"webp": "image/webp", "mp4": "video/mp4", "mp3": "audio/mpeg", "gif": "image/gif"}[fmt])
                self.send_header("Content-Length", str(destination.stat().st_size))
                self.send_header("Connection", "close")
                self.end_headers()
                with destination.open("rb") as stream:
                    shutil.copyfileobj(stream, self.wfile, length=65536)
                self.close_connection = True
        except subprocess.TimeoutExpired:
            self.reply(504, "conversion timed out")
        except (BrokenPipeError, ConnectionResetError, TimeoutError):
            self.close_connection = True
        except OSError:
            self.reply(500, "worker storage or process error")


def main():
    if len(TOKEN) < 32:
        raise SystemExit("Set TANGERINE_TOKEN to at least 32 characters")
    http.server.HTTPServer(("0.0.0.0", 8765), Handler).serve_forever(poll_interval=5)


if __name__ == "__main__":
    main()
