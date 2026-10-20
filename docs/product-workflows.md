# Context, batches, and output previews

## Contextual wheels

Option-click a file to see formats supported by its type. Shift-click offers utilities suited to the selection:

- Images: crop, background styling, Preview, Float, ZIP, copy path, AirDrop, rename.
- PDFs: split into individual-page PDFs, Preview, Float and common file utilities.
- Multiple images/PDFs: combine pages into one PDF, in selection order.
- Video: MP4, MP3 and GIF; audio offers MP3 only.
- Folders/other files: common file utilities; unsupported conversion selections offer Choose files.

For a mixed selection, conversion formats are the intersection supported by every file. An image plus a PDF can be converted to PNG/JPG/HEIC/TIFF/TXT/DOCX; an audio plus a video can be converted to MP3. Files with no shared format remain visible in the review window, with an explanation and controls to remove/add files.

AirDrop uses the native macOS sharing service and opens its recipient dialog with the complete selection. Float adds the selection to one reusable floating shelf, deduplicating file URLs. The shelf stays above ordinary windows across Spaces, supports moving by its background, expands on hover (or a click on the stack), and accepts additional file/folder drops. Drag its stack to export everything or an expanded item to export one file. A successful copy drag removes exported references; cancellation leaves them available. Clicking an expanded item reveals it in Finder. Closing the shelf clears references without touching the originals. The shelf is temporary and is not restored after quitting.

## Batch conversion

Select files in Finder first, then Option-click an item already in that selection. Tangerine snapshots the current selection only if every selected Accessibility item can be resolved and the clicked item belongs to it. The captured selection is shown in the wheel center. Choosing a format opens the review window, where conversion starts only when you press Convert.

The Accessibility snapshot is capped at 256 items and depends on Finder's current view. It deliberately falls back to the clicked file if a complete selection cannot be resolved. For any unsupported Finder view, larger selections, or explicit control, choose **Convert files…** from the menu bar or Settings. The file picker supports multiple files without Finder automation permission.

In review you can add/remove files, change their order, choose a shared format, and select a representative file for its preview. Jobs run sequentially, saving results beside each original with collision-safe names. Each input has a success/error result; one failed input does not stop later files. A multi-page PDF produces one image per page. Stop after current file cancels between inputs, rather than interrupting a partially written video. Closing the review window allows the current job to continue; Convert files reopens its window. Reveal outputs selects all completed results.

## Live previews

Hover over a format in the wheel for a compact side panel, or inspect the selected file in batch review. Native image previews encode and decode a bounded sample, showing the output appearance, dimensions, JPEG transparency behavior and a clearly labelled sample-based size estimate. Actual file size may differ significantly from the estimate. PDF previews represent the first page; exported files still include every page.

TXT/DOCX previews show a text-layer excerpt or bounded on-device OCR sample. DOCX output is text-only and does not reconstruct page layout. Video/audio previews show source information and a source thumbnail where available. Worker-only WebP previews are explicitly source thumbnails. No FFmpeg job or Docker upload is started on hover.

Preview generation is debounced by 160 ms, uses a serial background queue, discards stale results, bounds raster decoding to 768 px, and caps the in-memory sample cache at 24 MiB/12 entries. It is demand-driven and stops publishing results when the wheel closes.

## Native-first engine

Image/PDF/text tasks use ImageIO, PDFKit and Vision. MP4 uses AVFoundation's native 1280×720 export preset first and can fall back to the local worker if enabled. WebP uses the native encoder only when this Mac advertises one; otherwise it uses Docker. MP3/GIF still require FFmpeg in Docker. The worker retains its single-request, 0.5 CPU and 256 MiB limits; batches do not increase worker concurrency.
