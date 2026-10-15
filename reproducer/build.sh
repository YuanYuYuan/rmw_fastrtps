#!/usr/bin/env bash
# build.sh <name> <pins file or -> [colcon args]
# Downloads the tarballs listed in the pins file, applies the PATCH lines, and builds the probe plus
# those packages. A pins line is "<ros2-gbp repo> <version> : <packages>" (a release tarball),
# "SOURCE <url> <package>" (a source archive of a git commit; the package is its subdirectory), or "PATCH <package> <file>". into an overlay at /opt/<name> on top of /opt/ros/rolling.
set -euo pipefail
name=$1; pins=$2; shift 2
src=/ws/$name/src; mkdir -p "$src"
if [ "$pins" != - ]; then
  while read -r repo ver sep pkgs; do
    case "$repo" in ''|\#*) continue;; esac
    if [ "$repo" = SOURCE ]; then
      f=$(mktemp); curl -fsSL --retry 3 -o "$f" "$ver"; echo "sha256 $(sha256sum "$f" | cut -d' ' -f1) $sep $ver"
      mkdir -p "$src/$sep"; tar -xzf "$f" -C "$src/$sep" --strip-components=2 --wildcards "*/$sep/"; rm -f "$f"; continue
    fi
    if [ "$repo" = PATCH ]; then patch -p1 -d "$src/$ver" < "$sep"; continue; fi
    for pkg in $pkgs; do
      f=$(mktemp)
      curl -fsSL --retry 3 -o "$f" "https://github.com/ros2-gbp/$repo/archive/release/rolling/$pkg/$ver.tar.gz"
      echo "sha256 $(sha256sum "$f" | cut -d' ' -f1) $pkg $ver"
      mkdir -p "$src/$pkg"; tar -xzf "$f" -C "$src/$pkg" --strip-components=1; rm -f "$f"
    done
  done < "$pins"
fi
cp -r probe "$src/buffer_probe"
set +u; . /opt/ros/rolling/setup.bash; set -u
cd "/ws/$name"
CMAKE_GENERATOR=Ninja colcon build --merge-install --install-base "/opt/$name" --parallel-workers 4 \
  --cmake-args -DBUILD_TESTING=OFF -DCMAKE_BUILD_TYPE=Release "$@"
