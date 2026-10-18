# Operations

## Deploy and upgrade

Run `./scripts/deploy.sh` from the project. It builds and signs the native app, builds the Alpine worker image, and waits for worker readiness. Run `./scripts/install-app.sh`, then open `~/Applications/Tangerine.app`. Quit a running older app before reopening a rebuilt version. The app stays in the build directory; copying it to Applications is optional and must be followed by granting Accessibility to that stable location.

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

## Permission enabled but wheels still inactive

Check the **Connection** section in Tangerine Settings. It distinguishes missing Accessibility trust from a failure to create the mouse listener, and reports the last matching click without storing a log of filenames or paths.

If System Settings shows Tangerine enabled but Connection says the running app lacks access, quit and reopen the unchanged installed app. If the mismatch persists, reset only this app's permission with `tccutil reset Accessibility local.tangerine.mac`, then launch the app, request Accessibility again, and enable the fresh entry for `~/Applications/Tangerine.app`. This reset revokes the existing grant; it never grants access automatically. Do it only with the user's explicit approval. Do not reset permissions for every application.

Ad-hoc signatures identify a build by its code hash. Rebuilding/reinstalling can therefore invalidate a previous Accessibility grant even when the bundle name and path stay the same. Complete a build before authorizing it, avoid rebuilding while checking permissions, and use a persistent signing identity for distributed releases.

When Connection says Ready, test with a physical Option-click or Shift-click. Per-window automation events may bypass global event taps and are not sufficient to validate mouse interception. A matching physical click should update the second diagnostic line. Another-app clicks pass through, and unresolved Finder filenames produce a specific diagnostic instead of consuming the click.
