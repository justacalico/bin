#!/usr/bin/env bash
# Regenerate altstore/apps.json from the just-synced GitLab release and push
# it back to main with ci.skip. Runs inside github-release-sync, after
# sync-from-github.sh has downloaded the release assets.
set -euo pipefail

RELEASE_TAG="${RELEASE_TAG:-}"

# Only stable version tags feed the AltStore source (versions must be semver).
if ! echo "$RELEASE_TAG" | grep -qE '^v[0-9]+\.[0-9]+\.[0-9]+$'; then
  echo "update-altstore: skipping non-release tag '${RELEASE_TAG:-}'"
  exit 0
fi

IPA="release-assets/bin-ios-arm64-unsigned.ipa"
if [ ! -f "$IPA" ]; then
  echo "update-altstore: no ipa in release assets, skipping"
  exit 0
fi

VERSION="${RELEASE_TAG#v}"
SIZE=$(stat -c%s "$IPA")
DATE=$(date -u +%Y-%m-%dT%H:%M:%S%z)
DOWNLOAD="https://gitlab.com/${CI_PROJECT_PATH}/-/releases/${RELEASE_TAG}/downloads/bin-ios-arm64-unsigned.ipa"
ICON="https://${CI_PROJECT_NAMESPACE}.gitlab.io/${CI_PROJECT_NAME}/altstore/icon.png"
SOURCE="https://${CI_PROJECT_NAMESPACE}.gitlab.io/${CI_PROJECT_NAME}/altstore/apps.json"

mkdir -p altstore
jq -n \
  --arg version "$VERSION" \
  --arg date "$DATE" \
  --arg download "$DOWNLOAD" \
  --arg icon "$ICON" \
  --arg source "$SOURCE" \
  --argjson size "$SIZE" \
  '{
    name: "bin",
    identifier: "com.httpanimations.bin.altstore",
    sourceURL: $source,
    apps: [{
      name: "bin",
      bundleIdentifier: "com.httpanimations.bin",
      developerName: "HttpAnimations",
      subtitle: "Roblox avatars in 3D",
      localizedDescription: "Enter a Roblox username and view the player avatar rendered in 3D.",
      iconURL: $icon,
      tintedIconURL: $icon,
      category: "utilities",
      versions: [{
        version: $version,
        date: $date,
        downloadURL: $download,
        size: $size,
        minOSVersion: "14.0"
      }],
      version: $version,
      versionDate: $date,
      versionDescription: ("Release " + $version),
      downloadURL: $download,
      size: $size,
      appPermissions: {entitlements: [], privacy: {}},
      screenshots: []
    }],
    news: [{
      title: ("bin " + $version),
      identifier: ("release-" + $version),
      caption: "Latest release",
      date: $date,
      notify: true,
      url: $download
    }]
  }' > altstore/apps.json
cat altstore/apps.json

git config user.name "GitLab CI"
git config user.email "ci@gitlab.com"
git remote add gitlab-ssh "git@gitlab.com:${CI_PROJECT_PATH}.git" 2>/dev/null || true
git fetch gitlab-ssh main
git checkout -B main gitlab-ssh/main 2>/dev/null || git checkout main
git add altstore/apps.json
if git diff --cached --quiet; then
  echo "update-altstore: apps.json already up to date"
  exit 0
fi
git commit -m "chore: 更新 AltStore 源"
git push -o ci.skip gitlab-ssh HEAD:main
echo "update-altstore: pushed apps.json"
