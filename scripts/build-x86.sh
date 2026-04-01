#!/usr/bin/env bash
set -euo pipefail

TARGET=x86
source "$(dirname "$0")/lib.sh"

update_source
prepare_worktree  "$TARGET"
apply_patches     "$TARGET"
update_feeds      "$TARGET"
load_config       "$TARGET"
download_sources
build_firmware
collect_output  "$TARGET"

msg "x86 build done"