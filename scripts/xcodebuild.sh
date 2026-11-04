#!/bin/bash
# Runs xcodebuild for the Makefile's builds, with the arguments it's given, and
# cuts each line it prints to 500 characters. Even with -quiet, a file that
# fails to compile prints the whole swift-frontend command, on one line of about
# 10,000 characters, into every session that reads the build's output. The
# errors themselves, `<file>:<line>:<column>: error:`, are short, and stay whole.
# The exit status stays xcodebuild's, so a failed build still fails make, and
# CI. This wrapper is our own.

set -o pipefail

xcodebuild "$@" 2>&1 | LC_ALL=C cut -c 1-500
