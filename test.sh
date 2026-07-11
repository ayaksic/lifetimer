#!/bin/sh
set -eu

swift test
TZ=America/New_York node Tests/WebParity/web-parity.test.cjs
