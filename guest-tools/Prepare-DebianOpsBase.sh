#!/usr/bin/env bash

# Debian 13 运维母盘预装脚本
#
# 用途：
#   在临时维护 VM 内安装常用运维工具、全局 l/ll 别名以及官方 Docker Engine，
#   为后续封装新的 Hyper-V 基础镜像（母盘）做准备。
#
# 使用要求：
#   1. 必须以普通 Debian 用户运行，脚本会在需要时调用 sudo；
#   2. 安装期间建议给 VM 至少 1GB 内存；
#   3. VM 必须能够访问 Debian 和 Docker 官方软件源；
#   4. 脚本会把当前用户加入 docker 组，该组基本拥有 root 等级权限。
#
# 从 Mac 直接通过 SSH 执行（不会在 VM 中留下脚本文件）：
#   ssh debian@VM_IP -i ~/.ssh/xxx \
#     'bash -s' < ~/prj/hyperv/guest-tools/Prepare-DebianOpsBase.sh
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

sudo -v

MEM_MIB="$(awk '/MemTotal/ {print int($2 / 1024)}' /proc/meminfo)"
if (( MEM_MIB < 700 )); then
    echo "Warning: only ${MEM_MIB}MiB is currently visible; provide at least 1GB while installing." >&2
fi

echo "[1/4] Installing operations tools..."
sudo apt-get update
sudo env DEBIAN_FRONTEND=noninteractive apt-get install -y \
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
sudo tee /etc/profile.d/aliases.sh >/dev/null <<'EOF'
alias l='ls -CF --color=auto'
alias ll='ls -alFh --color=auto'
EOF
sudo chmod 0644 /etc/profile.d/aliases.sh

echo "[3/4] Installing Docker..."
if sudo docker version >/dev/null 2>&1; then
    echo "Docker is already installed and working; skipping."
else
    INSTALLER="$(mktemp)"
    trap 'rm -f "$INSTALLER"' EXIT
    curl -fsSL https://get.docker.com -o "$INSTALLER"
    sudo sh "$INSTALLER"
    sudo systemctl enable --now containerd docker
fi

echo "[4/4] Adding ${TARGET_USER} to the docker group..."
sudo usermod -aG docker "$TARGET_USER"

echo
echo "Installation complete:"
htop --version | head -n 1
btop --version
sudo docker --version
sudo docker compose version
echo
echo "Reconnect the SSH session to activate docker group membership and l/ll aliases."
