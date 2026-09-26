# bin

Enter a Roblox username and view the player's avatar rendered in 3D.

bin resolves the username through the official Roblox APIs, assembles the
avatar from the player's own assets (body parts, clothing textures, face,
accessories), and renders it with a pure-Dart software 3D renderer. No
webviews, no native plugins, works on every platform Flutter supports.

## Features

- Username to 3D avatar in one step
- R6 and R15 avatars, body colors, scale sliders, shirts, pants, t-shirts,
  face decals, hats and accessories
- Enter a local `.glb` path instead of a username to view any model file
- Orbit camera: drag to rotate, scroll or pinch to zoom, double tap to reset
- Auto-rotate while idle
- Honors `http_proxy`/`https_proxy` environment variables
- Flat-shaded textured rendering with painter's algorithm depth sorting

## How it works

1. `users.roblox.com` resolves the username to a Roblox user ID
2. `avatar.roblox.com` returns the avatar spec: rig type, scales, body
   colors, and worn assets
3. `assetdelivery.roblox.com` serves the actual files: RBXM models (binary
   and XML), `.mesh` geometry, and PNG textures
4. bin parses the Roblox formats, places accessories by attachment point,
  and draws the result with `Canvas.drawVertices`

## Install

Binaries for every platform are attached to each
[release](https://gitlab.com/HttpAnimations/bin/-/releases):

| Platform | Files |
|---|---|
| Linux | `.tar.gz`, `.zip`, `.deb`, `.rpm`, `.AppImage` (x86_64 + arm64) |
| Windows | `.zip` (x86_64 + arm64) |
| macOS | `.dmg`, `.zip` (arm64) |
| Android | `.apk`, `.aab` |
| iOS | unsigned `.ipa` (see AltStore below) |
| Web | `bin-web.tar.gz`, or just use the [hosted version](https://HttpAnimations.gitlab.io/bin/) |

> Note: the web build cannot resolve usernames because Roblox does not send
> CORS headers on the users/avatar lookup endpoints (asset downloads are
> open). Username lookup and `.glb` paths are desktop and mobile only; the
> hosted version currently serves as a demo shell.

### AltStore (iOS)

Add this source in AltStore:

```
https://HttpAnimations.gitlab.io/bin/altstore/apps.json
```

Then install `bin` from the source. AltStore signs the unsigned `.ipa`
locally on your device.

## Development

```bash
flutter pub get
flutter test --coverage   # 100% coverage gate
flutter run
```

## License

AGPL-3.0. See [LICENSE](LICENSE).
