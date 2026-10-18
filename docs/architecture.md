# Architecture

## Native app

Swift Package Manager builds a dependency-free AppKit/SwiftUI executable. `scripts/build-app.sh` wraps it in an `LSUIElement` app bundle and uses a configured persistent identity, falling back to ad-hoc only when no identity is configured. Menu bar settings use UserDefaults under `local.tangerine.mac`.

`FinderMonitor` installs a CGEvent tap only when enabled, bindings differ, and Accessibility is trusted. It watches mouse down/up, compares exact modifier combinations, and performs an Accessibility hit test at the click coordinates. The owning process must be `com.apple.finder`. File URLs come from the clicked element or its ancestors; the fallback resolves an exact displayed filename relative to the containing Finder window's document URL or Desktop. After resolving the clicked file, it snapshots selected Accessibility children only when the complete selection can be resolved and includes that clicked file. It never substitutes an unrelated selection. If resolution fails, the original click passes through. Matching clicks are consumed along with their mouse-up to avoid accidental Shift selection or Option behavior.

This is event-driven; there is no background Finder scan. Event taps disabled by the OS are re-enabled. Disable removes the tap and dismisses the wheel. Finder's Accessibility representation varies between macOS versions, views, virtual/search locations and third-party extensions: unsupported or unresolved elements deliberately leave normal clicks alone. A clicked selected item can target the complete current selection; unresolved selections fall back to the clicked file. Batch review makes the target list explicit before conversion.

`WheelController` hosts rounded ring segments in a transparent nonactivating panel and clamps the panel into the current display's visible bounds. `WheelView` observes the saved accent color. Temporary outside-click and Escape monitors exist only while the wheel is open. Settings and editors use ordinary native windows.

`FileActions` performs conversions on a background queue with one active task. ImageIO, PDFKit and Vision handle native image conversion, PDF rasterization and OCR. Each PDF page is processed individually. Textutil creates text-only DOCX; ditto creates ZIP archives. Processes use explicit executable paths and argument arrays, with no shell interpolation. Editors save PNG copies. File names are checked for collisions and data writes use exclusive creation.

## Docker worker

A Python standard-library HTTPServer handles one request at a time. The app invokes macOS's curl with direct disk upload/download; the bearer token passes on stdin rather than in process arguments. Only the selected file's bytes go to localhost; paths are not sent. Native conversions don't contact the worker.

`POST /convert?format=webp|mp4|mp3|gif` requires `Authorization: Bearer <token>` and a positive `Content-Length` no larger than 128 MiB. Files stream to a private TemporaryDirectory on a named volume. FFmpeg arguments come from a fixed allowlist, include one thread and a protocol whitelist restricting it to file/pipe, and discard source metadata. Results stream back in 64 KiB chunks. Temporary files are cleaned up on normal completion and handled errors. No credentials or file contents are logged. `GET /health` is unauthenticated and returns a readiness message.

HTTP errors: 400 invalid route/format/length, 401 auth, 413 invalid size, 422 invalid/oversized media, 504 conversion deadline, 500 storage/process failure. Only local single-user operation is intended. A slow authenticated upload occupies the single server; socket operations have 30-second timeouts. A health check during a long conversion may time out, but Docker does not restart containers solely for an unhealthy status.

The container limit is a hard ceiling, not a promise that every file under the upload limit will decode within 256 MiB. Very large image dimensions, complex codecs and long media can fail. No persistent job queue, retry loop, database, or cloud service is present.

## Credentials and packaging

`deploy.sh` creates a 256-bit random hexadecimal token in a mode-600 `.env` file, then builds the app and starts Compose. The same token is embedded in the local app's Resources/worker-token with mode 600. Do not distribute this local app bundle or `.env`. Token changes require rebuilding and reopening the app and recreating the worker. Environment variables are visible to local users with Docker access, so the token is a local access guard, not a multi-user security boundary.

## Product and foundation extensions

See [product workflows](product-workflows.md) for contextual actions, sequential batch execution, format intersection, bounded hover previews and native-first video conversion. See [signing and startup](signing-and-startup.md) for the persistent local signing identity, event-driven permission refresh and SMAppService login startup. Preview work never starts a media-worker conversion.
