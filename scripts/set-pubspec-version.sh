#!/usr/bin/env bash
# cog pre-bump hook: write "version: <semver>+1" into pubspec.yaml.
set -euo pipefail
VERSION="${1:?usage: set-pubspec-version.sh <semver>}"
sed -i -E "s/^version:.*/version: ${VERSION}+1/" pubspec.yaml
