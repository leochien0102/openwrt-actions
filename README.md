# openwrt-ci

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 的 OpenWRT 多 target 编译项目，支持 Rockchip（H28K）和 x86_64（PVE）设备。

## 分支说明

| 分支 | 用途 |
|------|------|
| `main` | 编译脚本、配置、补丁 |

## 目录结构（main 分支）

```
.
├── configs/
│   ├── feeds.conf               # 通用 feeds 配置
│   ├── rockchip.config          # Rockchip 编译配置
│   └── x86.config               # x86_64 编译配置
├── patches/
│   ├── common/                  # 所有 target 通用
│   ├── base-files/              # 默认 IP 等基础配置（可被 target 专属 patch 覆盖）
│   ├── rockchip/                # Rockchip 专属
│   └── x86/                     # x86_64 专属
├── scripts/
│   ├── lib.sh                   # 公共函数库
│   ├── build-rockchip.sh        # Rockchip 编译脚本
│   └── build-x86.sh             # x86_64 编译脚本
└── .github/
    └── workflows/
        ├── rockchip.yml         # Rockchip 每周自动构建
        └── x86.yml              # x86_64 每周自动构建
```

以下目录由编译机运行时自动创建，不进 git：

```
lede-src/    # upstream 源码
build/       # 各 target 的 git worktree（含各自的 .ccache）
output/      # 编译产物
shared/      # dl / feeds 共享缓存
```

> **注意**：ccache 由 OpenWrt 编译系统硬编码在各 worktree 的 `.ccache/` 目录下，不在 `shared/` 里共享。

## 本地编译（编译机 / WSL2）

### 前置要求

- Ubuntu 22.04 / 24.04
- 磁盘空间 50GB+

安装编译依赖：

```bash
sudo apt-get update
sudo apt-get install -y \
    ack antlr3 asciidoc autoconf automake autopoint binutils bison build-essential \
    bzip2 ccache clang cmake cpio curl device-tree-compiler flex gawk gcc-multilib g++-multilib gettext \
    genisoimage git gperf haveged help2man intltool libc6-dev-i386 libelf-dev libfuse-dev libglib2.0-dev \
    libgmp3-dev libltdl-dev libmpc-dev libmpfr-dev libncurses5-dev libncursesw5-dev libpython3-dev \
    libreadline-dev libssl-dev libtool llvm lrzsz libnsl-dev ninja-build p7zip p7zip-full patch pkgconf \
    python3 python3-pyelftools python3-setuptools qemu-utils rsync scons squashfs-tools subversion \
    swig texinfo uglifyjs upx-ucl unzip vim wget xmlto xxd zlib1g-dev
```

### 初次使用

```bash
git clone https://github.com/leochien0102/openwrt-actions
cd openwrt-actions

# 初始化 upstream 源码
git clone --depth=1 https://github.com/coolsnowwolf/lede lede-src

# 创建共享缓存目录
mkdir -p shared/dl shared/feeds
```

### 创建 worktree

每个 target 对应一个独立的 git worktree，首次使用需手动创建：

```bash
git -C lede-src worktree add --detach ../build/rockchip origin/master
git -C lede-src worktree add --detach ../build/x86 origin/master
```

创建完成后为各 worktree 建立共享目录的 symlink：

```bash
for target in rockchip x86; do
    ln -snf ../../shared/dl    build/$target/dl
    ln -snf ../../shared/feeds build/$target/feeds
done
```

> 各 worktree 下的 `.ccache/` 由编译系统自动创建，无需手动处理。

### 开始编译

worktree 建好后，直接运行对应脚本即可，脚本会自动完成 source 更新、patch、feeds、config 加载和编译：

```bash
# Rockchip H28K
bash scripts/build-rockchip.sh

# x86_64
bash scripts/build-x86.sh
```

产物输出目录：

| Target | 固件 | Packages |
|--------|------|----------|
| rockchip | `output/rockchip/firmware/` | `output/rockchip/packages/` |
| x86 | `output/x86/firmware/` | `output/x86/packages/` |

### 自定义编译配置

仓库提供的 `configs/*.config` 是 diffconfig 格式的精简配置，`make defconfig` 会自动补全其余选项为默认值。如需根据自己的需求调整包选择：

```bash
# 1. 初始化 worktree 环境（更新源码、打 patch、更新 feeds、加载 config）
bash scripts/init-worktree.sh <target>

# 2. 进入 worktree，打开 menuconfig 调整
cd build/<target>
make menuconfig

# 3. 导出新的 diffconfig，覆盖仓库中的配置文件
cd ../..
./build/<target>/scripts/diffconfig.sh > configs/<target>.config
```

此后每次运行编译脚本都会自动加载更新后的配置，无需重复操作。

## 自动构建（GitHub Actions）

每周日 UTC 16:00（北京时间周一 00:00）自动触发，也可在 Actions 页面手动触发。

| Workflow | Target | Release tag |
|----------|--------|-------------|
| rockchip.yml | H28K | `rockchip-YYYYMMDD` |
| x86.yml | x86_64 | `x86-YYYYMMDD` |

各保留最近 4 次 Release。
