#!/usr/bin/env bash
set -euo pipefail

TARGET=rockchip
source "$(dirname "$0")/lib.sh"

# 用法: build-rockchip.sh [-fw 3|4] [--update-only]
parse_common_args "$@"
resolve_fw "$TARGET"

UPDATE_ONLY=false
[[ "${REST_ARGS[0]:-}" == "--update-only" ]] && UPDATE_ONLY=true

update_source
prepare_worktree  "$TARGET"
fetch_feeds       "$TARGET"

if $UPDATE_ONLY; then
    msg "Rockchip update done (fw$FW)"
    exit 0
fi

confirm_continue_build "$TARGET" || exit 0

apply_patches     "$TARGET"
install_feeds
load_config       "$TARGET"
download_sources
build_firmware
collect_output    "$TARGET"

msg "Rockchip build done (fw$FW)"
