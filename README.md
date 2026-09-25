# bin

Enter a Roblox username and view the player's avatar rendered in 3D.

bin resolves the username through the renderbux service (the same pipeline as
the native rbxava app), downloads the baked GLB model, and renders it with a
pure-Dart software 3D renderer. No webviews, no native plugins, works on every
platform Flutter supports.

## Features

- Username to 3D avatar in one step
- Orbit camera: drag to rotate, scroll or pinch to zoom, double tap to reset
- Auto-rotate while idle
- Dynamic server-action discovery so renderbux redeploys do not break the app
- Flat-shaded textured rendering with painter's algorithm depth sorting

## How it works

1. `lookupUserIdByName` resolves the username to a Roblox user ID
2. `getUserAvatarIfBaked` returns a presigned GLB URL if the avatar is cached
3. `getUserAvatar` bakes it on demand (rate limited for anonymous use)
4. The GLB is downloaded, parsed, and drawn with `Canvas.drawVertices`

## Install

Binaries for Linux, Windows, macOS, Android, iOS (AltStore) and web are
attached to every [release](https://gitlab.com/HttpAnimations/bin/-/releases).

## License

AGPL-3.0. See [LICENSE](LICENSE).
