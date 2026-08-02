#!/usr/bin/env bash

# Debian 13 运维母盘预装脚本
#
# 用途：
#   在临时维护 VM 内安装常用运维工具、全局 l/ll 别名以及官方 Docker Engine，
#   为后续封装新的 Hyper-V 基础镜像（母盘）做准备。
#
# 使用要求：
#   1. 必须以普通 Debian 用户运行，并已由 cloud-init 配置免密 sudo；
#   2. 安装期间建议给 VM 至少 1GB 内存；
#   3. VM 必须能够访问 Debian 和 Docker 官方软件源；
#   4. 脚本会把当前用户加入 docker 组，该组基本拥有 root 等级权限。
#
# 从 Mac 直接通过 SSH 执行，并在安装前临时使用 Mihomo 网关/DNS
# （不会在 VM 中留下脚本文件，也不会把网关永久写入母盘）：
#   ssh debian@VM_IP -i ~/.ssh/xxx \
#     'MIHOMO_GATEWAY=10.0.0.134 MIHOMO_DNS=10.0.0.134 bash -s' \
#     < ~/prj/hyperv/guest-tools/Prepare-DebianOpsBase.sh
#
# 注意：
#   本脚本只负责安装和配置。验证完成后，仍需按照 BASE-IMAGE.md 清除
#   Docker 运行状态、cloud-init 状态、machine-id、SSH 主机密钥和个人公钥，
#   然后关机并合并为新的版本化母盘。清理后不要再次启动维护 VM。

set -Eeuo pipefail

TARGET_USER="$(id -un)"

if [[ "$TARGET_USER" == "root" ]]; then
    echo "Run this script as the normal Debian user, not directly as root." >&2
    exit 1
fi

if ! sudo -n true; then
    echo "Passwordless sudo is required for non-interactive SSH execution." >&2
    exit 1
fi

MIHOMO_GATEWAY="${MIHOMO_GATEWAY:-}"
MIHOMO_DNS="${MIHOMO_DNS:-$MIHOMO_GATEWAY}"

if [[ -n "$MIHOMO_GATEWAY" ]]; then
    IFACE="$(ip route show default | awk 'NR==1 {print $5}')"
    if [[ -z "$IFACE" ]]; then
        echo "Unable to detect the current default network interface." >&2
        exit 1
    fi

    echo "[0/4] Temporarily routing through Mihomo at ${MIHOMO_GATEWAY}..."
    sudo -n ip route replace default via "$MIHOMO_GATEWAY" dev "$IFACE"

    if [[ -n "$MIHOMO_DNS" ]]; then
        sudo -n resolvectl dns "$IFACE" "$MIHOMO_DNS"
        sudo -n resolvectl domain "$IFACE" '~.'
        sudo -n resolvectl flush-caches
    fi

    if ! getent hosts get.docker.com >/dev/null; then
        echo "DNS verification failed for get.docker.com." >&2
        exit 1
    fi
fi

MEM_MIB="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
if (( MEM_MIB < 700 )); then
    echo "Warning: only ${MEM_MIB}MiB is currently visible; provide at least 1GB while installing." >&2
fi

echo "[1/4] Installing operations tools..."
sudo -n apt-get update
sudo -n env DEBIAN_FRONTEND=noninteractive apt-get install -y \
    ca-certificates \
    curl \
    htop \
    btop \
    jq \
    git \
    vim-tiny \
    less \
    tmux \
    tree \
    ncdu \
    rsync \
    unzip \
    lsof \
    dnsutils \
    iputils-ping \
    traceroute \
    netcat-openbsd \
    bash-completion

echo "[2/4] Installing global l/ll aliases..."
sudo -n tee /etc/profile.d/aliases.sh >/dev/null <<'EOF'
alias l='ls -CF --color=auto'
alias ll='ls -alFh --color=auto'
EOF
sudo -n chmod 0644 /etc/profile.d/aliases.sh

echo "[3/4] Installing Docker..."
if sudo -n docker version >/dev/null 2>&1; then
    echo "Docker is already installed and working; skipping."
else
    INSTALLER="$(mktemp)"
    trap 'rm -f "$INSTALLER"' EXIT
    curl -fsSL https://get.docker.com -o "$INSTALLER"
    sudo -n sh "$INSTALLER"
    sudo -n systemctl enable --now containerd docker
fi

echo "[4/4] Adding ${TARGET_USER} to the docker group..."
sudo -n usermod -aG docker "$TARGET_USER"

echo
echo "Installation complete:"
htop --version | head -n 1
btop --version
sudo -n docker --version
sudo -n docker compose version
echo
echo "Reconnect the SSH session to activate docker group membership and l/ll aliases."
