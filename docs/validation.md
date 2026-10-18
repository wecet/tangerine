# Validation

Validated locally on 18 October 2026, Apple Silicon macOS, Swift 6.1.2, Docker Engine 24.0.2 and Compose 2.19.1.

## Passed

- Release Swift build and ad-hoc app bundle signing.
- App launch and native settings inspection: accent picker, enabled toggle, Option-click and Shift-click defaults, media toggle and permission controls.
- Native PNG, JPEG, HEIC, TIFF and PDF encoding and re-opening.
- Two-page PDF exported to separate PNG, JPEG and HEIC images, validating every output.
- Collision-safe output naming and exact modifier matching.
- On-device OCR of a generated text image.
- Native rendering and visual inspection of rounded citrus wheel segments, neutral glass surfaces and configurable accent. Generated preview: `build/wheel-preview.png`.
- Eight HTTP integration tests: readiness, auth, allowlisted formats, empty/oversized/corrupt uploads, real WebP/MP4/MP3/GIF conversions, and blocked network protocols.
- Actual deployed Docker conversions using generated 1280 × 720 media; every output validated using ffprobe.
- Docker limits inspected: 268435456-byte RAM and total RAM/swap ceiling, 500000000 NanoCPUs, read-only root filesystem.
- Idle worker sample after conversions: **0.00% CPU**, **11.16 MiB / 256 MiB**, two processes. This is a single idle sample, not a peak or a guarantee; Docker Desktop's VM overhead is additional.

## Manual checks still required

macOS Accessibility consent is user-controlled. Finder event interception has not been verified end to end in this session because that consent has not been granted. After granting it and reopening Tangerine:

1. In a standard local Finder icon view, Option-click a PNG and choose JPG. Verify the new image beside the original.
2. Repeat in list, column, gallery view and on a Desktop icon. Click icons and names. Unresolvable items must keep normal Finder behavior.
3. Shift-click an image; test Crop, Add BG, metadata, copy path, duplicate, rename and ZIP creation using disposable fixtures. Verify original pixels remain unchanged after editor exports.
4. Click Finder blank space and another app: no wheel should appear or consume the click.
5. Test Escape, outside click, screen edges, multiple displays, Spaces and dark/light appearance.
6. Change both bindings and accent, disable/re-enable, quit/reopen and verify preferences persist. Conflicting bindings must pause interception.
7. Stop Docker: native actions should still work and media actions should give a useful error. Disable media in settings to dim those actions.

Do not treat successful builds or conversion checks as proof that every Finder Accessibility layout works. Unsupported virtual locations deliberately fail closed. HEIC has been validated on this Apple Silicon host; other hardware may lack an encoder.

## Reproduce

```sh
./scripts/check.sh
./scripts/deploy.sh
python3 scripts/smoke-worker.py
docker stats --no-stream tangerine-worker-1
```

`check.sh` uses generated temporary fixtures; it does not change user files or request Accessibility. The smoke script requires the local `.env`, running worker, and host FFmpeg/ffprobe. Tokens and test artifacts are not committed.

## Finder follow-up

The user confirmed that a physical Option-click opens the conversion wheel after the Tangerine-only Accessibility reset and reauthorization. The initial overlaid-segment pointer bug was then replaced with one wheel-level position hit test. Sector checks cover every segment at three radial distances for 3-, 4-, 6- and 8-action wheels, and reject the hub/outside area. The display canvas is reduced from 360 to 290 points. Conversion, OCR and worker checks still pass. The user subsequently confirmed that the smaller wheel highlights and selects different formats correctly. Automated Finder clicks bypassed the global event tap in this session.

## Glass styling

The wheel now uses an active behind-window NSVisualEffectView for desktop blur, transparent gradient segments, reflective outlines and a clear center. Reduce Transparency falls back to an opaque system background. The glass backdrop does not receive pointer events. Existing sector, conversion and HTTP checks pass after the styling change. Offscreen rendering verifies the geometry and highlights; live desktop blur depends on the window compositor.
