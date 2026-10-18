# Tangerine identity

`tangerine-icon.png` is the transparent master artwork, generated with the built-in image generation tool. It uses rounded citrus segments, graphite/pearl glass, and a muted lavender accent. The menu bar mark is a monochrome template drawn in `Sources/Tangerine/Brand.swift`, allowing macOS to adapt it to light and dark menu bars. The wheel accent remains configurable independently of the fixed application artwork.

`scripts/build-icon.sh` creates the standard 16–1024 px macOS icon representations and packages `build/Tangerine.icns`. `scripts/build-app.sh` includes that icon and declares it in Info.plist. Generated iconsets and bundles stay outside Git.

Generation prompt:

> Use case: logo-brand. Asset type: production macOS application icon for Tangerine, a radial Finder conversion utility. Create one polished square 1024x1024 app icon, no presentation sheet. An abstract citrus cross-section made of six generously rounded radial segments around a small circular center, like the app's radial wheel. A subtle offset of one segment suggests transformation. Sculpted frosted graphite and pearl glass, restrained soft bevels and precise negative space, one muted periwinkle/lavender accent segment. Neutral charcoal rounded-square macOS icon tile with generous transparent padding outside the tile. Symmetric balanced front-on composition, bold simple silhouette legible at 32px. Soft studio light from upper left. Premium understated native macOS utility feel. No orange, yellow, green, fruit leaves, literal fruit texture, letters, text, watermark, extra icons, or background scene. Transparent background beyond the rounded square.
