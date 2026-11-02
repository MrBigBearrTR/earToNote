#!/bin/sh
# Xcode Cloud runs this right after cloning. The Xcode project is generated from project.yml and is
# not committed, so it has to be created before Xcode Cloud looks for it.
set -e

brew install xcodegen
cd "$CI_PRIMARY_REPOSITORY_PATH"
xcodegen generate
