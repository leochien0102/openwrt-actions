#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/lib.sh"

# 用法: init-worktree.sh [-fw 3|4] <target>   (e.g. rockchip, x86)
parse_common_args "$@"

TARGET="${REST_ARGS[0]:-}"
if [[ -z "$TARGET" ]]; then
    err "Usage: init-worktree.sh [-fw 3|4] <target>  (e.g. rockchip, x86)"
    exit 1
fi

resolve_fw "$TARGET"

update_source
prepare_worktree  "$TARGET"
apply_patches     "$TARGET"
update_feeds      "$TARGET"
load_config       "$TARGET"

msg "Worktree for '$TARGET' (fw$FW) initialized — run 'make menuconfig' in build/$TARGET to customize"
