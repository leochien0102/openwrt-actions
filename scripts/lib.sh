#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC_DIR="$ROOT_DIR/lede-src"
BUILD_DIR="$ROOT_DIR/build"
CONFIG_DIR="$ROOT_DIR/configs"
PATCH_DIR="$ROOT_DIR/patches"
SHARED_DIR="$ROOT_DIR/shared"
OUTPUT_DIR="$ROOT_DIR/output"

msg() {
    echo -e "\n\033[1;32m==> $*\033[0m"
}

#################################
# common args: -fw 3|4
#################################
# 解析通用参数。-fw / --fw 取出 firewall 世代，其余参数原样留在 REST_ARGS。
parse_common_args() {
    REST_ARGS=()
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -fw|--fw)      FW="${2:-}"; shift 2 ;;
            -fw=*|--fw=*)  FW="${1#*=}"; shift ;;
            *)             REST_ARGS+=("$1"); shift ;;
        esac
    done
}

# 未显式指定 -fw 时，按 target 取默认世代，并校验取值。
resolve_fw() {
    local target="$1"

    if [[ -z "${FW:-}" ]]; then
        # 已验证可用 fw4 的 target 逐个列出，新 target 先落到 fw3（lede 基线），
        # 验证过再加进来——避免新 target 默默继承一个没测过的世代。
        case "$target" in
            rockchip|x86) FW=4 ;;
            *)            FW=3 ;;
        esac
        msg "No -fw given, defaulting to fw$FW for target '$target'"
    fi

    case "$FW" in
        3|4) ;;
        *) err "Invalid -fw value: '$FW' (expected 3 or 4)"; exit 1 ;;
    esac
}

err() {
    echo -e "\n\033[1;31m[ERROR] $*\033[0m" >&2
}

#################################
# update upstream
#################################
update_source() {
    msg "Updating upstream"
    cd "$SRC_DIR"
    git pull --rebase
}

#################################
# prepare worktree (detached)
#################################
prepare_worktree() {
    local target="$1"
    WORKTREE="$BUILD_DIR/$target"

    # Resolve upstream HEAD commit in the main repo
    local upstream_branch
    upstream_branch=$(git -C "$SRC_DIR" branch --show-current)
    local upstream_commit
    upstream_commit=$(git -C "$SRC_DIR" rev-parse "origin/${upstream_branch}")

    # Create worktree only once; symlinks are created here and never touched again
    if ! git -C "$SRC_DIR" worktree list | grep -qF "$WORKTREE"; then
        msg "Creating detached worktree: $target"
        git -C "$SRC_DIR" worktree add --detach "$WORKTREE" "$upstream_commit"
        cd "$WORKTREE"
        ln -snf "$SHARED_DIR/dl"     dl
        ln -snf "$SHARED_DIR/feeds"  feeds
        ln -snf "$SHARED_DIR/ccache" .ccache
    else
        msg "Reusing existing worktree: $target"
        cd "$WORKTREE"
    fi

    # Sync tracked files to upstream HEAD.
    # --hard resets only tracked files; build_dir/staging_dir are
    # untracked so they are preserved for incremental rebuilds.
    msg "Resetting worktree to upstream HEAD"
    git checkout --detach "$upstream_commit"
    git reset --hard "$upstream_commit"

    # Remove untracked files that could confuse make, but preserve
    # build artifacts and shared symlinks (NO -x flag).
    git clean -df \
        --exclude=build_dir \
        --exclude=staging_dir \
        --exclude=dl \
        --exclude=feeds \
        --exclude=.ccache

    # Clear stale ccache lock that may be left by interrupted builds
    rm -rf .ccache/lock
}

#################################
# patches
#################################
apply_patch_dir_single() {
    local p="$1"
    local name
    name=$(basename "$p")
    echo "Applying $name"
    if ! patch -p1 --forward < "$p" >/tmp/patch_out 2>&1; then
        if grep -q "Reversed (or previously applied)" /tmp/patch_out; then
            echo "  (already applied, skipping)"
        else
            err "Failed to apply $name"
            cat /tmp/patch_out >&2
            return 1
        fi
    fi
}

apply_patch_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0

    local patches=( "$dir"/*.patch )
    [[ -f "${patches[0]}" ]] || return 0  # glob found nothing

    for p in "${patches[@]}"; do
        apply_patch_dir_single "$p"
    done
}

apply_patches() {
    local target="$1"

    msg "Applying patches"
    apply_patch_dir "$PATCH_DIR/common"

    # Apply base-files patches, skipping any that are overridden by a same-named
    # patch in the target directory
    local dir="$PATCH_DIR/base-files"
    if [[ -d "$dir" ]]; then
        local patches=( "$dir"/*.patch )
        [[ -f "${patches[0]}" ]] || patches=()
        for p in "${patches[@]}"; do
            local name
            name=$(basename "$p")
            if [[ -f "$PATCH_DIR/$target/$name" ]]; then
                msg "Skipping base-files/$name (overridden by $target/$name)"
            else
                apply_patch_dir_single "$p"
            fi
        done
    fi

    apply_patch_dir "$PATCH_DIR/$target"
}

#################################
# feeds
#################################
# 注意：shared/feeds 是所有 target 共用的单一检出，feeds.conf 决定其分支
# （fw3/fw4 两份只差 helloworld 的 dev-fw3 / dev-fw4）。两个 target 跑不同世代
# 时，每次切换都会把 helloworld 重新检出到另一分支——这也是把 x86 一并切到
# fw4 的理由之一。
load_feeds_conf() {
    local target="$1"

    # 优先级：target+fw > fw > target > 通用。fw 世代通常只影响个别 feed 的分支。
    local candidates=(
        "$target.feeds.fw$FW.conf"
        "feeds.fw$FW.conf"
        "$target.feeds.conf"
        "feeds.conf"
    )

    local c
    for c in "${candidates[@]}"; do
        if [[ -f "$CONFIG_DIR/$c" ]]; then
            cp "$CONFIG_DIR/$c" feeds.conf
            msg "Using feeds.conf: $c"
            return 0
        fi
    done

    err "No feeds.conf found in configs/ — using upstream feeds.conf.default"
}

fetch_feeds() {
    local target="$1"
    load_feeds_conf "$target"
    msg "Updating feeds"
    if ! ./scripts/feeds update -a; then
        msg "Feed update failed (force-pushed upstream?), resetting diverged feeds and retrying"
        for d in feeds/*/; do
            [[ -d "$d/.git" ]] || continue
            git -C "$d" fetch --all --prune 2>/dev/null
            git -C "$d" reset --hard "@{upstream}" 2>/dev/null || true
        done
        ./scripts/feeds update -a
    fi
}

install_feeds() {
    msg "Installing feeds"
    ./scripts/feeds install -a
}

update_feeds() {
    local target="$1"
    fetch_feeds "$target"
    install_feeds
}

confirm_continue_build() {
    local name="$1"
    local timeout="${BUILD_CONFIRM_TIMEOUT:-30}"

    if [[ -n "${CI:-}" || ! -t 0 ]]; then
        msg "$name update done - continuing build"
        return 0
    fi

    local reply
    printf "\n\033[1;33m==> %s update done. Continue build? [Y/n] (auto-continue in %ss): \033[0m" "$name" "$timeout"
    if read -r -t "$timeout" reply; then
        case "$reply" in
            [Nn]|[Nn][Oo])
                msg "$name build cancelled"
                return 1
                ;;
        esac
    else
        printf "\n"
        msg "No response within ${timeout}s - continuing build"
    fi

    return 0
}

#################################
# config
#################################
load_config() {
    local target="$1"

    msg "Loading config: $target.config (fw$FW)"
    cp "$CONFIG_DIR/$target.config" .config

    # <target>.config 保持 fw 世代中立，差异以叠加文件的形式追加。
    # kconfig 后出现的赋值覆盖先出现的，所以 target 级叠加放在通用叠加之后。
    local overlay
    for overlay in "fw$FW.config" "$target.fw$FW.config"; do
        if [[ -f "$CONFIG_DIR/$overlay" ]]; then
            msg "Applying overlay: $overlay"
            printf '\n' >> .config
            cat "$CONFIG_DIR/$overlay" >> .config
        fi
    done

    make defconfig
}

#################################
# download
#################################
download_sources() {
    msg "Downloading sources"
    make download -j8
}

#################################
# build
#################################
build_firmware() {
    msg "Building"
    make -j"$(nproc)" V=s
}

#################################
# collect output
# - firmware files -> output/<target>/firmware/<ts>-<n>  (accumulated)
# - packages       -> output/<target>/packages/             (replaced)
#################################
collect_output() {
    local target="$1"
    local out_dir="$OUTPUT_DIR/$target"
    local firmware_dir="$out_dir/firmware"
    local packages_dir="$out_dir/packages"

    local ts
    ts=$(TZ=Asia/Shanghai date +%y%m%d%H%M)

    mkdir -p "$firmware_dir" "$packages_dir"

    msg "Collecting firmware (timestamp: $ts)"
    local count=0
    while IFS= read -r -d '' f; do
        local base
        base=$(basename "$f")
        mv "$f" "$firmware_dir/${ts}-${base}"
        echo "  ${ts}-${base}"
        (( count++ )) || true
    done < <(find bin/targets -maxdepth 4 -type f \
        \( -name "*.img*" -o -name "*.bin" -o -name "*.manifest" -o -name "*.qcow2" \) \
        ! -name "Packages.manifest" \
        -print0)
    msg "Collected $count firmware file(s)"

    msg "Collecting packages"
    local target_pkgs
    target_pkgs=$(find bin/targets -maxdepth 5 -type d -name packages | head -n1)
    if [[ -n "$target_pkgs" ]]; then
        rm -rf "$packages_dir/target"
        mv "$target_pkgs" "$packages_dir/target"
    fi
    if [[ -d bin/packages ]]; then
        rm -rf "$packages_dir/feeds"
        mv bin/packages "$packages_dir/feeds"
    fi
    msg "Packages collected to $packages_dir"
}


