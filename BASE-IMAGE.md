# Debian 母盘预装建议

母盘只负责提供所有 VM 都需要的公共能力；主机名、用户、公钥、网络和 `machine-id` 等实例身份由 CIDATA/cloud-init 注入。

## 推荐分层

### `base`：最小通用母盘

建议所有实例具备：

```text
cloud-init
openssh-server
sudo
ca-certificates
hyperv-daemons
```

这层应尽量小、稳定，适合作为默认父盘。

### `ops`：运维母盘

在 `base` 之上，可按实际需要增加：

```text
htop
curl
jq
vim-tiny 或 nano
less
bash-completion
rsync
unzip
dnsutils
iputils-ping
lsof
```

如果只是偶尔使用某个工具，例如 `htop`，优先放进 cloud-init 的 `packages`，不必立即制作新母盘。

### `dev`：开发母盘

在 `base` 或 `ops` 之上，可增加：

```text
git
build-essential
make
pkg-config
```

语言运行时、容器平台和数据库变化较快，建议由配置管理或项目初始化流程安装，不要全部塞进通用母盘。

## 不应写入母盘

- SSH 私钥、令牌、密码或其他秘密；
- 固定主机名、静态 IP、个人账号和个人公钥；
- 已生成的 `/etc/machine-id`；
- 已生成的 SSH 主机密钥；
- 临时文件、APT 缓存、日志和 shell 历史；
- 只服务单台 VM 的业务配置；
- 更新频繁且不同项目版本不一致的软件栈。

一句话：**母盘提供能力，CIDATA 提供身份。**

## 制作新版本母盘

不要直接启动或修改正在被差分盘引用的只读母盘，也不要用新文件覆盖它。

建议流程：

1. 从当前母盘创建临时维护盘和维护 VM；
2. 启动维护 VM，更新系统并安装公共软件；
3. 执行清理；
4. 关机，将维护结果合并或转换为新的独立 VHDX；
5. 使用版本化名称保存，例如 `debian-13-base-v2.vhdx`；
6. 检查新盘可以独立启动，再将它设置为只读；
7. 新 VM 使用 `v2`，已有 VM 继续使用原来的 `v1`。

建议在维护 VM 中清理：

```bash
sudo cloud-init clean --logs --machine-id
sudo rm -f /etc/ssh/ssh_host_*
sudo apt-get clean
sudo rm -rf /var/lib/apt/lists/*
sudo rm -rf /tmp/* /var/tmp/*
sudo journalctl --rotate
sudo journalctl --vacuum-time=1s
history -c
sudo fstrim -av
sudo poweroff
```

下一台 VM 首次启动时，由 cloud-init 重新生成 `machine-id` 和 SSH 主机密钥。

## 版本和依赖规则

- 母盘一旦成为差分盘的父盘，就视为不可变文件；
- 不要移动、改名、覆盖或删除仍有子盘依赖的母盘；
- “相同 Debian 版本”不等于“相同父盘”，不能用重新制作的文件冒充原父盘；
- 至少保留一份离线备份，并记录文件名、路径、版本和创建日期；
- 删除旧母盘前，必须确认没有任何 `.vhdx` 或 `.avhdx` 仍引用它。

## 当前项目的建议

现有 `debian-13-base.vhdx` 继续保持只读和不变。短期只想增加 `htop` 时，可在 cloud-init 的 `packages` 中添加：

```yaml
packages:
  - hyperv-daemons
  - curl
  - ca-certificates
  - htop
```

等公共软件明显增多，再制作 `debian-13-base-v2.vhdx`，不要原地升级 `debian-13-base.vhdx`。
