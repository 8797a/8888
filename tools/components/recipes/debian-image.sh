#!/usr/bin/env bash
set -euo pipefail
. tools/linuxfs/debian-image.env
# The image release is published by the upstream project; a fork has none of its own,
# so the upstream repository is searched before falling back to a registry pull.
upstream=${DEBIAN_IMAGE_UPSTREAM_REPO:-Droid-Deck/DroidDeck}
registry_images=(public.ecr.aws/docker/library/debian:bullseye docker.io/library/debian:bullseye)

fetch_release() {
  gh release download "$DEBIAN_IMAGE_TAG" -R "$1" -p "$DEBIAN_IMAGE_ASSET" -O /tmp/debian-image.tar.zst 2>/dev/null \
    && { [ -z "$DEBIAN_IMAGE_SHA256" ] \
         || echo "$DEBIAN_IMAGE_SHA256  /tmp/debian-image.tar.zst" | sha256sum -c - >/dev/null; }
}

if fetch_release "$GITHUB_REPOSITORY" || fetch_release "$upstream"; then
  zstd -dc /tmp/debian-image.tar.zst | docker load
  rm -f /tmp/debian-image.tar.zst
else
  echo "::warning::the hosted Debian image could not be fetched; pulling from a registry instead"
  pulled=
  for candidate in "${registry_images[@]}"; do
    for attempt in 1 2 3; do
      docker pull "$candidate" && { pulled=$candidate; break; }
      [ "$attempt" -lt 3 ] || break
      echo "pull of $candidate failed (registry busy?); retrying in $((attempt * 30)) s"
      sleep $((attempt * 30))
    done
    [ -n "$pulled" ] && break
  done
  [ -n "$pulled" ] || { echo "::error::no Debian image could be fetched or pulled"; exit 1; }
fi
docker image ls
