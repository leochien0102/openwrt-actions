# openwrt-ci

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 的 OpenWRT 多 target 编译项目，支持 Rockchip（H28K）和 Amlogic（N1）设备。

## 分支说明

| 分支 | 用途 |
|------|------|
| `main` | 编译脚本、配置、补丁 |
| `kernels` | flippy 预编译内核文件（孤立分支） |

## 目录结构（main 分支）

```
.
├── configs/
│   ├── feeds.conf               # 通用 feeds 配置
│   ├── rockchip.config          # Rockchip 编译配置
│   └── armvirt.config           # Armvirt 编译配置
├── patches/
│   ├── common/                  # 所有 target 通用
│   ├── base-files/              # base-files 相关
│   ├── rockchip/                # Rockchip 专属
│   └── armvirt/                 # Armvirt 专属
├── scripts/
│   ├── lib.sh                   # 公共函数库
│   ├── build-rockchip.sh        # Rockchip 编译脚本
│   ├── build-armvirt.sh         # Armvirt 编译脚本
│   └── build-n1.sh              # N1 打包脚本（依赖 armvirt 编译结果）
└── .github/
    └── workflows/
        ├── rockchip.yml         # Rockchip 每周自动构建
        └── armvirt.yml          # Armvirt 每周自动构建
```

以下目录由编译机运行时自动创建，不进 git：

```
lede-src/    # upstream 源码
build/       # 各 target 的 git worktree
output/      # 编译产物
packit/      # unifreq/openwrt_packit
shared/      # dl / feeds / ccache 共享缓存
```

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
git clone https://github.com/coolsnowwolf/lede lede-src

# 创建共享缓存目录
mkdir -p shared/dl shared/feeds shared/ccache
```

### 编译 Rockchip（H28K）

```bash
bash scripts/build-rockchip.sh
```

产物输出到 `output/rockchip/firmware/`，packages 在 `output/rockchip/packages/`。

### 编译 Armvirt + 打包 N1

```bash
# 第一步：编译 armvirt 固件（生成 rootfs）
bash scripts/build-armvirt.sh

# 第二步：使用 openwrt_packit 打包 N1 固件
bash scripts/build-n1.sh
```

N1 固件输出到 `output/armvirt/firmware/`，格式为 `<timestamp>-*.img.xz`。

### N1 内核

首次运行 `build-n1.sh` 后，`packit/kernels/` 目录会自动创建。将 flippy 预编译内核文件平铺放入该目录：

```
packit/kernels/
├── boot-<version>.tar.gz
├── modules-<version>.tar.gz
└── dtb-amlogic-<version>.tar.gz
```

脚本会自动选用版本号最新的内核。如需锁定特定版本，编辑 `packit/whoami`：

```bash
KERNEL_VERSION="6.6.62-flippy-92+"
```

若锁定版本在 `kernels/` 目录中找不到对应文件，脚本会自动 fallback 到最新可用版本并打印警告。

## 自动构建（GitHub Actions）

每周日 UTC 16:00（北京时间周一 00:00）自动触发，也可在 Actions 页面手动触发。

| Workflow | Target | Release tag |
|----------|--------|-------------|
| rockchip.yml | H28K | `rockchip-YYYYMMDD` |
| armvirt.yml | N1 | `armvirt-YYYYMMDD` |

各保留最近 4 次 Release。

### N1 内核更新

内核文件存放在 `kernels` 分支根目录下，Actions 构建时会自动 checkout 该分支获取内核。

更新内核时：

```bash
git checkout kernels

# 删除旧内核文件，添加新文件
git rm *.tar.gz
# 复制新内核文件到当前目录
git add *.tar.gz
git commit -m "Kernels: bump to <version>"
git push origin kernels

git checkout main
```