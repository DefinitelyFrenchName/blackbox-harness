#!/bin/sh
# g_skip_indent.sh — an indented SKIP marker is still a marker (`^ *SKIP`).
# ROM-free, ~0 s.
set -eu
echo "  SKIP: indented skip marker"
exit 0
