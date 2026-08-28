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
# 顺序与 build-<target>.sh 保持一致：feed 补丁必须落在 fetch_feeds 之后、
# install_feeds 之前（apply_feed_patches 打在 shared/feeds 检出上，fetch 会
# reset 掉未提交改动，所以不能在 fetch 之前打）。
fetch_feeds       "$TARGET"
apply_patches     "$TARGET"
install_feeds
load_config       "$TARGET"

msg "Worktree for '$TARGET' (fw$FW) initialized — run 'make menuconfig' in build/$TARGET to customize"
