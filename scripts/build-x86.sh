#!/usr/bin/env bash
set -euo pipefail

TARGET=x86
source "$(dirname "$0")/lib.sh"

# 用法: build-x86.sh [-fw 3|4] [--update-only]
parse_common_args "$@"
resolve_fw "$TARGET"

UPDATE_ONLY=false
[[ "${REST_ARGS[0]:-}" == "--update-only" ]] && UPDATE_ONLY=true

update_source
prepare_worktree  "$TARGET"
fetch_feeds       "$TARGET"

if $UPDATE_ONLY; then
    msg "x86 update done (fw$FW)"
    exit 0
fi

confirm_continue_build "$TARGET" || exit 0

apply_patches     "$TARGET"
install_feeds
load_config       "$TARGET"
download_sources
build_firmware
collect_output    "$TARGET"

msg "x86 build done (fw$FW)"
