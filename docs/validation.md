# Validation

Validated locally on 18 October 2026 using Apple Silicon macOS 15.7.4, Swift 6.1.2, Docker Engine 24.0.2 and Compose 2.19.1. macOS 13 is the deployment target; older macOS/hardware combinations have not been exercised here.

## Automated checks passed

`./scripts/check.sh` covers:

- Native PNG, JPG, HEIC, TIFF and PDF encoding and reopening.
- Every page of a two-page PDF exported to PNG/JPG/HEIC.
- Exclusive/collision-safe output naming, original byte preservation and exact click modifiers.
- On-device OCR of a generated text image.
- Every wheel segment at three radial distances, for 3-, 4-, 6- and 8-action wheels, with hub/outside rejection.
- File context, mixed image/PDF format intersection, audio-only output rules and rejecting an unrelated Finder selection.
- Sequential batches continuing after a corrupt file, stopping between inputs and exporting multipage inputs.
- PDF merge/split page counts.
- Encoded JPEG sample preview, transparency messaging, first-page PDF metadata and the 768px preview decoding bound.
- Native MP4 export with the media worker disabled.
- Eight HTTP worker tests: readiness, authentication, allowlisted formats, empty/oversized/corrupt uploads, real WebP/MP4/MP3/GIF output and blocked network protocols.

The deployed Docker worker also converted generated 1280×720 media to all four supported formats, with every result validated by ffprobe. Its limits were inspected: 256 MiB RAM and total RAM/swap ceiling, 0.5 CPU, read-only root filesystem. An idle sample after conversions was 0.00% CPU, 11.16 MiB and two processes; this is not a peak guarantee and excludes Docker Desktop's VM overhead.

## Signing, installation and startup passed

- Release builds and strict signature verification.
- User-approved persistent local signing identity installed in the login keychain, with code-signing-only user-domain trust. Temporary private-key files were removed.
- A deliberately changed bundle had a different code hash while both original and update satisfied the same certificate-pinned designated requirement (`scripts/check-signing.sh`).
- Final app installed at `~/Applications/Tangerine.app`.
- Accessibility migrated with explicit user approval, with the installed signed app enabled in System Settings.
- Login Items shows one Tangerine entry. Background Task Management reports type `app`, disposition `[enabled, allowed, visible, notified]`, and the installed Applications URL. A duplicate entry was removed.

## UI validation

The user physically confirmed the smaller wheel opens and different segments highlight/select correctly before this feature extension. The glass treatment, wheel geometry, icons and settings have been visually checked in earlier builds. The user confirmed the current installed Settings window shows Convert files and Startup & signing.

Native UI inspection currently returns a pipe error for the extended Tangerine window while System Settings and Finder remain inspectable. Automated builds and engine checks must not be treated as proof of complete UI behavior. The user confirmed that batch conversion and previews work using the supplied two-PNG review flow, including the Finder wheel side-preview check. Finder multi-selection capture across all views remains a separate acceptance check. The generated disposable files in `build/ReviewFixtures` can be used without touching user files.

## Remaining acceptance checks

2. Select both fixtures in Finder, Option-click an already-selected item: verify the center says two files and the review list contains both. Try icon, list, column and gallery views. Unsupported snapshots must fall back to the clicked file rather than an unrelated/partial selection.
3. Check preview placement at screen edges and JPEG white transparency handling; normal batch/hover preview behavior is user-confirmed.
4. Test mixed formats, failure rows, file removal/reordering, stopping between inputs and reopening an in-progress batch.
5. Test PDF merge/split on disposable files and compare page order/content.
6. Log out/in to verify startup after a real login; the OS registration is verified, but this disruptive test has not been performed.

Reproduce engine and deployment checks:

```sh
./scripts/check.sh
./scripts/build-app.sh
./scripts/check-signing.sh  # requires the configured local identity
python3 scripts/smoke-worker.py
```

Host checks require Python, FFmpeg and ffprobe. Tests generate temporary inputs and preserve user files. Tokens, private signing material, binaries, compiler caches and UI fixtures are not committed.
