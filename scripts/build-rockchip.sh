#!/usr/bin/env bash
set -euo pipefail

TARGET=rockchip
source "$(dirname "$0")/lib.sh"

update_source
prepare_worktree  "$TARGET"
apply_patches     "$TARGET"
update_feeds      "$TARGET"
load_config       "$TARGET"
download_sources
build_firmware
collect_output  "$TARGET"

msg "Rockchip build done"
