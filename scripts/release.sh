#!/usr/bin/env bash
# Cut a release: bump the TOC version, turn CHANGELOG's [Unreleased] section into the new version,
# commit and tag vX.Y.Z. Pushing the tag (git push origin main --follow-tags) triggers the GitHub
# Action that builds the zip and publishes the GitHub release.
#
# Usage: scripts/release.sh patch|minor|major|X.Y.Z [--push]
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"
TOC=MoneyTalksForever/MoneyTalksForever.toc
CHANGELOG=CHANGELOG.md

die() { echo "release: $*" >&2; exit 1; }

[[ $# -ge 1 ]] || die "usage: scripts/release.sh patch|minor|major|X.Y.Z [--push]"
bump=$1
push=${2:-}

[[ -z "$(git status --porcelain)" ]] || die "working tree is not clean"
[[ "$(git branch --show-current)" == "main" ]] || die "not on main"

current=$(sed -n 's/^## Version: *//p' "$TOC" | tr -d '\r')
[[ "$current" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || die "can't parse version '$current' in $TOC"
major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}

case "$bump" in
  patch) next="$major.$minor.$((patch + 1))" ;;
  minor) next="$major.$((minor + 1)).0" ;;
  major) next="$((major + 1)).0.0" ;;
  *)
    [[ "$bump" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "bad version '$bump'"
    next=$bump ;;
esac
tag="v$next"
git rev-parse -q --verify "refs/tags/$tag" >/dev/null && die "tag $tag already exists"

# The [Unreleased] section must have content, otherwise there is nothing to release.
notes=$(awk '/^## \[Unreleased\]/{f=1; next} /^## \[/{f=0} f' "$CHANGELOG" | sed '/^[[:space:]]*$/d')
[[ -n "$notes" ]] || die "CHANGELOG.md has no entries under [Unreleased]"

echo "Running tests..."
lua tests/run.lua
scripts/check-globals.sh

today=$(date +%Y-%m-%d)
sed -i "s/^## Version: .*/## Version: $next/" "$TOC"
sed -i "s/^## \[Unreleased\]$/## [Unreleased]\n\n## [$next] - $today/" "$CHANGELOG"

git add "$TOC" "$CHANGELOG"
git commit -q -m "Release $tag"
git tag -a "$tag" -m "Money Talks Forever $tag"
echo "Tagged $tag ($current -> $next)."

if [[ "$push" == "--push" ]]; then
  # Separate pushes: the tag push must arrive after the commit it points to is on GitHub.
  git push origin main
  git push origin "$tag"
  echo "Pushed. The GitHub Action will publish the release."
else
  echo "Publish with: git push origin main && git push origin $tag"
fi
