# openwrt-ci

基于 [coolsnowwolf/lede](https://github.com/coolsnowwolf/lede) 的 OpenWRT 多 target 编译项目，支持 Rockchip（H28K）和 Amlogic（N1）设备。

## 目录结构

```
.
├── configs/                  # 编译配置
│   ├── feeds.conf            # 通用 feeds 配置
│   ├── rockchip.config       # Rockchip diffconfig
│   └── armvirt.config        # Armvirt diffconfig
├── patches/                  # 补丁
│   ├── common/               # 所有 target 通用
│   ├── base-files/           # base-files 相关
│   ├── rockchip/             # Rockchip 专属
│   └── armvirt/              # Armvirt 专属
├── scripts/
│   ├── lib.sh                # 公共函数库
│   ├── build-rockchip.sh     # Rockchip 编译脚本
│   ├── build-armvirt.sh      # Armvirt 编译脚本
│   └── build-n1.sh           # N1 打包脚本（依赖 armvirt 编译结果）
└── .github/
    └── workflows/
        └── weekly.yml        # 每周自动构建
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
    build-essential clang flex bison g++ gawk gcc-multilib \
    gettext git libncurses-dev libssl-dev python3-distutils \
    rsync unzip zlib1g-dev file wget ccache xz-utils
```

### 初次使用

在编译机上 clone 本仓库，然后初始化 upstream 源码和共享目录：

```bash
git clone https://github.com/<your-username>/openwrt-ci
cd openwrt-ci

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

## 自动构建（GitHub Actions）

每周日 UTC 16:00（北京时间周一 00:00）自动触发，也可在 Actions 页面手动触发。

产物发布到 GitHub Releases，tag 格式为 `weekly-YYYYMMDD`，保留最近 4 次。

### N1 内核缓存

GitHub Actions 无法访问编译机上的 `packit/kernels/`，需要提前将内核文件上传到 Actions Cache。在编译机上执行：

```bash
# 安装 gh CLI（如未安装）
sudo apt install gh
gh auth login

# 上传内核缓存（在项目根目录执行）
gh cache set packit-kernels --dir packit/kernels
```

此后每次 Actions 运行时会自动从 cache 恢复内核文件。有新内核时重新执行上述命令更新 cache 即可。