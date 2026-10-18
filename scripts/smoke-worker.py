#!/usr/bin/env python3
"""Exercise the deployed worker with generated media; never print credentials."""
from pathlib import Path
import subprocess
import tempfile
import urllib.request

root = Path(__file__).resolve().parents[1]
token = next(line.split("=", 1)[1] for line in (root / ".env").read_text().splitlines() if line.startswith("TANGERINE_TOKEN="))
with tempfile.TemporaryDirectory(prefix="tangerine-smoke-") as tmp:
    source = Path(tmp) / "input.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-f", "lavfi", "-i", "color=c=blue:s=1280x720:d=2", "-f", "lavfi", "-i", "sine=frequency=440:duration=2", "-c:v", "libx264", "-threads", "1", "-pix_fmt", "yuv420p", "-c:a", "aac", "-shortest", str(source)], check=True)
    for fmt in ["webp", "mp4", "mp3", "gif"]:
        request = urllib.request.Request("http://127.0.0.1:8765/convert?format=" + fmt, data=source.read_bytes(), headers={"Authorization": "Bearer " + token, "Content-Type": "application/octet-stream"})
        with urllib.request.urlopen(request, timeout=330) as response:
            assert response.status == 200
            data = response.read()
        destination = Path(tmp) / ("output." + fmt)
        destination.write_bytes(data)
        subprocess.run(["ffprobe", "-v", "error", str(destination)], check=True)
        print(fmt.upper() + ": valid output (" + str(len(data)) + " bytes)")
print("Deployed worker smoke checks passed")
