#!/bin/sh
set -e
cd "$(dirname "$0")"
if command -v lua5.1 >/dev/null 2>&1; then
    exec lua5.1 tests/run.lua
fi
if command -v luajit >/dev/null 2>&1; then
    exec luajit tests/run.lua
fi
exec docker run --rm -v "$PWD":/w -w /w alpine:latest \
    sh -c 'apk add --no-cache lua5.1 >/dev/null && lua5.1 tests/run.lua'
