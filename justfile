# AInnotator tasks.

set shell := ["bash", "-euo", "pipefail", "-c"]

# The maker's local tasks, where they exist; they are not part of this repository.
import? 'tools/private/tasks.just'

default:
    @just --list

# Compile everything (debug)
build:
    swift build

# All tests
test:
    swift test

# Tests of one module, e.g. `just t Core`
t module:
    swift test --filter AI{{module}}Tests

# App bundle in build/AInnotator.app, signed with $AI_SIGN_IDENTITY, a Developer ID in the keychain, or ad hoc
app:
    swift build -c release --product AInnotator
    tools/build-app-bundle.sh "$(swift build -c release --show-bin-path)/AInnotator" build

# Build and start; the new instance replaces a running one
run: app
    open -n build/AInnotator.app

# Main path on an invented example screen, offscreen: payload, card and overlay image in build/selftest
selftest:
    mkdir -p build
    swiftc -O -o build/example-screen tools/readme-images/screen.swift
    build/example-screen build/example-screen.png
    swift build --product AInnotator
    "$(swift build --show-bin-path)/AInnotator" --selftest build/example-screen.png build/selftest

# Real hot path against the speed budgets. Run it on an otherwise idle machine; other builds distort the numbers
perf: app
    build/AInnotator.app/Contents/MacOS/AInnotator --perf
