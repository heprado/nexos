#!/usr/bin/env bash
set -euo pipefail

exec systemctl --user list-timers --all --no-pager
