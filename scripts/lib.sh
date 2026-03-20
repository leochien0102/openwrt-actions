#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

SRC_DIR="$ROOT_DIR/lede-src"
BUILD_DIR="$ROOT_DIR/build"
CONFIG_DIR="$ROOT_DIR/configs"
PATCH_DIR="$ROOT_DIR/patches"
SHARED_DIR="$ROOT_DIR/shared"
OUTPUT_DIR="$ROOT_DIR/output"
PACKIT_DIR="$ROOT_DIR/packit"

msg() {
    echo -e "\n\033[1;32m==> $*\033[0m"
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
}

#################################
# patches
#################################
apply_patch_dir() {
    local dir="$1"
    [[ -d "$dir" ]] || return 0

    local patches=( "$dir"/*.patch )
    [[ -f "${patches[0]}" ]] || return 0  # glob found nothing

    for p in "${patches[@]}"; do
        local name
        name=$(basename "$p")
        echo "Applying $name"
        if ! patch -p1 --forward < "$p" >/tmp/patch_out 2>&1; then
            # "already applied" is not a real error — message goes to stdout
            if grep -q "Reversed (or previously applied)" /tmp/patch_out; then
                echo "  (already applied, skipping)"
            else
                err "Failed to apply $name"
                cat /tmp/patch_out >&2
                return 1
            fi
        fi
    done
}

apply_patches() {
    local target="$1"

    msg "Applying patches"
    apply_patch_dir "$PATCH_DIR/common"
    apply_patch_dir "$PATCH_DIR/base-files"
    apply_patch_dir "$PATCH_DIR/$target"
}

#################################
# feeds
#################################
load_feeds_conf() {
    local target="$1"

    # Per-target conf takes priority, fall back to common, then upstream default
    if [[ -f "$CONFIG_DIR/$target.feeds.conf" ]]; then
        cp "$CONFIG_DIR/$target.feeds.conf" feeds.conf
        msg "Using feeds.conf: $target.feeds.conf"
    elif [[ -f "$CONFIG_DIR/feeds.conf" ]]; then
        cp "$CONFIG_DIR/feeds.conf" feeds.conf
        msg "Using feeds.conf: configs/feeds.conf"
    else
        err "No feeds.conf found in configs/ — using upstream feeds.conf.default"
    fi
}

update_feeds() {
    local target="$1"

    load_feeds_conf "$target"
    msg "Updating feeds"
    ./scripts/feeds update -a
    ./scripts/feeds install -a
}

#################################
# config
#################################
load_config() {
    local target="$1"

    msg "Loading config"
    cp "$CONFIG_DIR/$target.config" .config
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
        \( -name "*.img*" -o -name "*.bin" -o -name "*.manifest" \) \
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

#################################
# openwrt_packit
#################################

# Clone openwrt_packit if not present, otherwise pull latest.
# Also ensures kernels/ dir and whoami file exist.
update_packit() {
    if [[ ! -d "$PACKIT_DIR/.git" ]]; then
        msg "Cloning openwrt_packit"
        git clone --depth=1 https://github.com/unifreq/openwrt_packit "$PACKIT_DIR"
    elif [[ -z "${CI:-}" ]]; then
        msg "Updating openwrt_packit"
        git -C "$PACKIT_DIR" restore .
        git -C "$PACKIT_DIR" pull --rebase
    else
        msg "Using existing openwrt_packit (CI)"
    fi

    # kernels/ holds pre-built flippy kernels; user populates it manually
    mkdir -p "$PACKIT_DIR/kernels"

    # Generate whoami if it doesn't exist yet; user can edit afterwards
    local whoami_file="$PACKIT_DIR/whoami"
    if [[ ! -f "$whoami_file" ]]; then
        msg "Creating default whoami: $whoami_file"
        cat > "$whoami_file" <<-WHOAMI
		# openwrt_packit configuration — edit as needed
		# Priority: whoami > env > make.env defaults

		WHOAMI="LeoChien"
		KERNEL_VERSION=""
		RK35XX_KERNEL_VERSION=""
		KERNEL_PKG_HOME="${PACKIT_DIR}/kernels"
		ENABLE_WIFI_K504=0
		ENABLE_WIFI_K510=0
		WHOAMI
    else
        # Always keep KERNEL_PKG_HOME pointing at the project kernels dir
        sed -i "s|^KERNEL_PKG_HOME=.*|KERNEL_PKG_HOME=\"${PACKIT_DIR}/kernels\"|" "$whoami_file"
        msg "Using existing whoami: $whoami_file"
    fi
}

# Copy the armvirt rootfs.tar.gz from the worktree into packit root
stage_rootfs() {
    local target="$1"
    local worktree="$BUILD_DIR/$target"

    msg "Staging rootfs"

    local rootfs
    rootfs=$(find "$worktree/bin/targets" -name "*rootfs.tar.gz" | head -n1)

    if [[ -z "$rootfs" ]]; then
        err "rootfs.tar.gz not found in $worktree/bin/targets"
        return 1
    fi

    cp -v "$rootfs" "$PACKIT_DIR/"
}

# Resolve the latest kernel version for a given dtb prefix from packit/kernels/.
# Writes the resolved version into $var_name in whoami.
# If whoami already has an explicit non-empty value for $var_name, it is kept.
_resolve_kernel_var() {
    local var_name="$1"   # e.g. KERNEL_VERSION or RK35XX_KERNEL_VERSION
    local dtb_prefix="$2" # e.g. dtb-amlogic or dtb-rockchip
    local whoami_file="$PACKIT_DIR/whoami"
    local kernels_dir="$PACKIT_DIR/kernels"

    # If whoami pins a specific version, respect it
    local pinned
    pinned=$(grep -E "^${var_name}=" "$whoami_file" 2>/dev/null \
        | head -n1 | cut -d= -f2 | tr -d '"')
    if [[ -n "$pinned" ]]; then
        msg "$var_name pinned in whoami: $pinned"
        return
    fi

    # Find the latest version via the dtb prefix (distinguishes amlogic vs rockchip)
    local latest
    latest=$(find "$kernels_dir" -maxdepth 1 -name "${dtb_prefix}-*.tar.gz" \
        | sed "s|.*${dtb_prefix}-||;s|\.tar\.gz||" \
        | sort -V | tail -n1)

    if [[ -z "$latest" ]]; then
        msg "No ${dtb_prefix} kernels found in $kernels_dir, skipping $var_name"
        return
    fi

    msg "Using latest kernel for $var_name: $latest"
    sed -i "s|^${var_name}=.*|${var_name}=\"$latest\"|" "$whoami_file"
}

resolve_kernel_version() {
    _resolve_kernel_var "KERNEL_VERSION"       "dtb-amlogic"
    _resolve_kernel_var "RK35XX_KERNEL_VERSION" "dtb-rockchip"
}

# Run the packit script; output .img files land in $PACKIT_DIR/output/
run_packit() {
    local script="$1"  # e.g. mk_s905d_n1.sh

    cd "$PACKIT_DIR"

    resolve_kernel_version

    # mk_s905d_n1.sh hardcodes ENABLE_WIFI_K510=1 in the script body,
    # which runs after whoami/make.env and overrides them.
    # Patch it directly before each run so the setting actually takes effect.
    sed -i 's/^ENABLE_WIFI_K510=.*/ENABLE_WIFI_K510=0/' "$script"

    msg "Running packit: $script"
    sudo "./$script"
}

# xz-compress .img files from packit output/, add timestamp prefix, move to output/<target>/firmware/
compress_firmware() {
    local target="$1"
    local out_dir="$OUTPUT_DIR/$target/firmware"

    mkdir -p "$out_dir"

    local ts
    ts=$(TZ=Asia/Shanghai date +%y%m%d%H%M)

    local count=0
    while IFS= read -r -d '' f; do
        local base
        base=$(basename "$f")
        local dest="$out_dir/${ts}-${base}.xz"
        msg "Compressing: $base"
        xz -T0 -c "$f" > "$dest"
        sudo rm -f "$f"
        echo "  -> $(basename "$dest")"
        (( count++ )) || true
    done < <(find "$PACKIT_DIR/output" -maxdepth 1 -name "*.img" -print0)

    msg "Compressed $count firmware file(s) into $out_dir"
}