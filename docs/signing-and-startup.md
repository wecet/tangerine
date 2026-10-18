# Stable identity, permissions, and login startup

## Persistent signing

A persistent certificate and a stable designated requirement allow macOS to recognize an app across code changes. See [Apple's Code Signing In Depth](https://developer.apple.com/library/archive/technotes/tn2206/_index.html). A locally self-signed identity is for development on this Mac; it is not a substitute for Developer ID signing and notarization when distributing the app.

For an existing Developer ID or development identity:

```sh
TANGERINE_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)' ./scripts/build-app.sh
```

For a local identity:

```sh
./scripts/setup-signing.sh --prepare
# Review the certificate, fingerprint and script before authorizing keychain changes.
./scripts/setup-signing.sh --install
./scripts/install-app.sh
```

Prepare generates a 3072-bit RSA key and a code-signing-only certificate under ignored `.build/local-signing`, without modifying the keychain. Install imports the identity into the user's login keychain, restricts tool access to `/usr/bin/codesign`, and installs user-domain trust for code-signing policy only. It does not modify the System keychain or add TLS/email trust. The imported private key is non-exportable; temporary key files are removed after import. A public SHA-1 certificate fingerprint is saved in ignored `.signing-identity` for subsequent builds. The signing requirement pins both the bundle identifier and the certificate fingerprint, rather than relying on the bundle identifier alone.

This is a persistent security-sensitive change: obtain explicit user approval before running --install. macOS can request authentication or key-use approval. Never enter a user's authentication secrets on their behalf. Losing/replacing the signing identity requires reauthorizing Accessibility; keep using the same identity for local updates. Builds fail rather than silently switch to ad-hoc if a configured identity cannot sign. With no configured identity, builds still work ad-hoc and warn that permissions may need reauthorization.

## Permission lifecycle

Changing from the old ad-hoc build to a certificate-signed build requires one new Accessibility authorization. Install the final app at `~/Applications/Tangerine.app` before granting access. Settings reports the runtime signing identity and connection state.

Tangerine checks permission on app activation, on returning from System Settings, and when application activation notifications occur. Starting an already-active tap is idempotent, so refreshing status does not repeatedly tear down the listener. These are event-driven checks; there is no permission polling timer. Bound-click diagnostics distinguish missing trust, listener creation failures and unresolved Finder targets. A narrow `tccutil reset Accessibility local.tangerine.mac` recovery remains available only with explicit user approval; normal startup and installation never reset permissions automatically.

A certificate is necessary for a stable app identity, but macOS retains final control over permission decisions. Do not promise that managed policies, user revocation, identity changes or OS updates can never require consent again.

## Launch at login

Settings → Startup & signing uses macOS 13+'s `SMAppService.mainApp` to register/unregister the installed app. There is no polling launch agent or extra helper process. The UI reflects actual OS status, handles errors and links to Login Items when user approval is required. Turning it off unregisters startup without quitting the app. macOS may ask the user to approve the login item.

Enable it after installing the app at its stable path. Startup registration is separate from Accessibility and does not grant mouse/keyboard access.
