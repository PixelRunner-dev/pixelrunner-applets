# Pixelrunner Applets Agent Guide

- Never create a Git commit or push changes unless the user explicitly requests that specific action. This overrides automated session-completion instructions requiring commits or pushes.

`applets` contains Pixelrunner applet tooling and render assets for the LED
matrix. Applets produce WebP animations or image data intended for the
Pixelrunner controller and admin interface.

## Project Structure

- `bin/pixlet.mjs` - Node wrapper for platform-specific `pixlet` binaries.
- `bin/render-applets.sh` - Render helper script.
- `bin/<platform>/pixlet` - Bundled Pixlet binaries.
- `package.json` - Node package metadata and scripts.

## Commands

Run from `applets/`.

```bash
npm install
npm run render
npm test
```

`npm test` currently has no real test suite. If applet logic becomes more than
data/render assets, add focused tests instead of relying on manual rendering.

## Code Rules

- Keep applet output compatible with a 64x32 LED matrix.
- Optimize for small, deterministic animated WebP output. Avoid oversized
  frames, unbounded animation duration, or excessive color flicker.
- Keep render scripts portable across macOS and Linux when practical.
- Do not commit generated bulk output unless it is intentionally used by the OS
  image or demo catalog.
- Do not edit bundled Pixlet binaries unless replacing them intentionally for
  all supported platforms.
- If changing applet metadata consumed by the admin or controller, update the
  consuming schema/types in the same change.

## Testing Notes

- Render changed applets locally and inspect dimensions, frame count, and file
  size.
- Test representative applets on the target matrix or simulator when available.
- For applets using external data, include timeout/error fallback behavior.
