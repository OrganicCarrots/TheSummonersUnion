#!/bin/sh
set -e
cd "$(dirname "$0")"
repo=$(pwd)
version=${1:-$(git describe --tags --always 2>/dev/null || echo dev)}
out="dist/TheSummonersUnion-$version.zip"
tmp=$(mktemp -d)
mkdir "$tmp/TheSummonersUnion"
cp TheSummonersUnion.toc ./*.lua LICENSE CHANGELOG.md "$tmp/TheSummonersUnion/"
sed -i "s/@project-version@/$version/" "$tmp/TheSummonersUnion/TheSummonersUnion.toc"
mkdir -p dist
rm -f "$out"
(cd "$tmp" && python3 -m zipfile -c "$repo/$out" TheSummonersUnion)
rm -rf "$tmp"
echo "$out"
