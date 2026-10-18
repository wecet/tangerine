# Tangerine

A native macOS menu bar app with contextual citrus-segment wheels, neutral translucent surfaces, and a configurable accent. Inspired by the supplied [demo](https://x.com/th2049/status/2111477585461039241/video/1); this is an independent implementation.

- **Option + click** a file in Finder or on the Desktop: conversion wheel.
- **Shift + click** a file: utilities wheel.
- Menu bar → **Settings & accent color…**: change bindings, accent, or enable/disable wheels.
- **Convert files…** in the menu bar opens batch review with per-file results and live sample previews.
- Hover over a format to preview its output. Existing Finder selections become batches when the clicked item belongs to the complete captured selection.
- Escape or click outside dismisses the wheel. Unsupported actions are dimmed.

## Start

Requires macOS 13+, Apple's Command Line Tools (`xcode-select --install`), and Docker Desktop with Compose for media conversions. No full Xcode installation or Swift dependencies are needed.

```sh
./scripts/deploy.sh
./scripts/install-app.sh
open ~/Applications/Tangerine.app
```

On first launch, use **Accessibility permission…**, then enable Tangerine in **System Settings → Privacy & Security → Accessibility**. Return to Tangerine to refresh permission status, or select **Retry permissions**. Reopening the app also brings its settings window forward. macOS requires you to grant this permission; the app does not grant it automatically. Keep the app at a stable path. Rebuilding an ad-hoc signed app may require removing and re-adding its Accessibility entry.

The menu bar and Finder integration run natively. Docker Desktop runs Linux containers, which cannot provide a macOS menu bar or intercept Finder clicks. Docker deploys the optional media conversion worker. This split also avoids keeping an Electron/browser runtime open.

To use only native features:

```sh
./scripts/build-app.sh
./scripts/install-app.sh
open ~/Applications/Tangerine.app
```

Disable Docker media conversions in settings if the worker is stopped.

## Actions

| Input | Conversion outputs |
| --- | --- |
| Image, including PNG, JPEG, HEIC | PNG, JPG, HEIC, TIFF, PDF, TXT, DOCX; WebP natively when supported, otherwise Docker |
| PDF | PNG, JPG, HEIC, TIFF, TXT, DOCX |
| Video | MP4 natively with Docker fallback; MP3/GIF through Docker |
| Audio | MP3 through Docker |

PDF-to-image exports **each page** into a separate image. Rasterized PDF pages fit within 2400 × 2400 pixels. Text extraction reads a PDF's text layer and uses on-device Vision OCR for scanned pages or images. DOCX is a text document; original document layout is not reconstructed. JPEG uses a white background for transparent pixels. Image conversion exports the first frame of animated/multipage image formats.

Utilities adapt to the file type and include PDF split/merge, **Crop**, **Add BG** (solid/gradient background, padding, corners, shadow), **Compress** (ZIP archive), **Metadata**, **Preview** (opens Apple's Preview for editing/annotation), **Copy path**, **Duplicate**, and **Rename**. Cropping and background styling apply to images. Background exports cap the image area at 2000 px per side, with up to 200 px padding. Originals are preserved by conversions and editors; rename changes the original filename. New outputs use numbered names rather than overwriting existing files.

This version uses click-to-open and click-to-select. Drag-to-select, custom annotation/redaction tools, and AVIF/BMP output from the reference are not implemented. Batch conversion and native login startup are included. Preview supplies its own editing tools.

## Low resource Docker deployment

The worker processes one request at a time, starts FFmpeg only for a conversion, streams uploads/downloads in 64 KiB chunks, and uses no web framework or database.

- Hard cap: **0.5 CPU**, **256 MiB RAM**, no additional swap; one FFmpeg thread.
- Input limit 128 MiB; output under 192 MiB; five-minute conversion deadline.
- MP4 scales to at most 1280 px wide; GIF to 640 px wide, 12 fps, first 30 seconds; WebP to 2400 px wide.
- Health check every two minutes. No directory polling or indexing.
- Only `127.0.0.1:8765` is published; token-authenticated conversions.
- Runs as a non-root user, with a read-only root filesystem and no host-folder mounts.
- Scratch files use a disk-backed Docker volume and are removed at the end of each request. An abrupt kill can leave scratch files in that volume.

Docker Desktop's VM has its own baseline RAM cost, separate from the worker's 256 MiB limit. For the lowest total resource use, stop the worker when media conversion is unnecessary:

```sh
docker compose stop worker
docker compose start worker
docker compose ps
docker stats --no-stream tangerine-worker-1
```

The app's enable toggle disables click handling; it does not stop Docker or the worker. The media toggle controls availability of worker actions. Both preferences persist.

## Development and documentation

```sh
./scripts/check.sh  # Python/FFmpeg HTTP integration tests + native conversions/OCR
./scripts/build-app.sh
```

Tests require `python3`, `ffmpeg`, and `ffprobe` on the host. The app itself only needs the native tools provided with macOS; FFmpeg runs in Docker at runtime.

See [context, batches and previews](docs/product-workflows.md), [stable signing and login startup](docs/signing-and-startup.md), [architecture](docs/architecture.md), [operations](docs/operations.md), and [validation](docs/validation.md). Generated binaries, local tokens, previews and compiler caches are excluded from Git. The build supports a persistent local signing identity or your Developer ID; with neither configured it uses ad-hoc signing. Distribution requires Developer ID signing and notarization.
