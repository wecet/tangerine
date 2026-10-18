# Operations

## Deploy and upgrade

Run `./scripts/deploy.sh` from the project. It builds and signs the native app, builds the Alpine worker image, and waits for worker readiness. Open `build/Tangerine.app`. Quit a running older app before reopening a rebuilt version. The app stays in the build directory; copying it to Applications is optional and must be followed by granting Accessibility to that stable location.

When upgrading, retain `.env`, run deployment again, and reopen the app. No account or database migration is required. For repeatable supply-chain builds, pin the Alpine image digest and APK repository snapshot after validating a release; the current Dockerfile uses the maintained Alpine 3.22 tag and latest available package patches in that release.

## Diagnose

- **No wheel:** check enable toggle, bindings, Accessibility permission, then Retry permissions. Click the file icon or filename, not blank space. Check a standard local Finder folder in icon/list view before trying virtual locations. macOS may require quitting and reopening after permission changes.
- **Normal click happens:** the hit element wasn't a resolvable Finder file; the app intentionally passes the click through.
- **Media conversion fails:** run `docker compose ps`, check `curl http://127.0.0.1:8765/health`, and check file size, media streams, timeout and memory constraints. Native image conversion still works.
- **Missing worker credentials:** run deployment again and reopen the rebuilt app.
- **Port occupied:** stop the application already using port 8765 or adjust the port in Compose and `FileActions.swift`, then rebuild.
- **Registry pull hangs in Docker's credential helper:** resolve the Docker Desktop/keychain prompt. A public image does not require registry login. Do not delete or print your existing Docker credentials.
- **HEIC cannot encode:** the native encoder reports an error when the Mac does not support this output. Use PNG/JPG instead.
- **Output cannot be saved:** check write access to the input's containing folder and available disk space. Outputs are created beside the input.

## Shutdown and removal

`docker compose stop worker` stops its resource consumption; native tools continue to work. `docker compose down` removes project containers and networks and retains scratch storage. Quit Tangerine from its menu. Remove its Accessibility entry manually when uninstalling. App preferences are under `local.tangerine.mac`; the app bundle and `.env` are local build/deployment artifacts.

The scratch volume can retain bytes after a crash or forced kill. Remove the project's scratch volume only after stopping the worker and confirming that any retained temporary data can be discarded. No automated startup cleanup of arbitrary temporary directories is performed.

## Permission and distribution

Accessibility is needed for Finder hit testing and consuming bound clicks. The app does not request Screen Recording, Full Disk Access, or Finder Apple Events automation. It does not automatically click permission prompts. macOS can separately ask for access to protected folders when files are read/written; grant only the folders you intend to use.

Ad-hoc signatures support local development. Use a consistent Developer ID identity and notarization for a distributable release. Rebuild on Intel to obtain an Intel binary, or produce and verify a universal binary before distributing to both architectures. Current build scripts compile for the current host architecture.
