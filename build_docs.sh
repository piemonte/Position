#!/bin/bash

# Docs by jazzy
# https://github.com/realm/jazzy
# ------------------------------

jazzy \
    --clean \
    --author 'Patrick Piemonte' \
    --author_url 'https://patrickpiemonte.com' \
    --github_url 'https://github.com/piemonte/Position' \
    --sdk iphonesimulator \
    --xcodebuild-arguments -scheme,Position \
    --module 'Position' \
    --framework-root . \
    --readme README.md \
    --output docs/
