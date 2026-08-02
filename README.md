# Debian Hyper-V Wizard

一个面向 Hyper-V 的单文件 Debian 云镜像创建向导。它使用只读 Debian 13 母盘，在一次交互流程中完成：

- 创建差分系统盘；
- 创建 FAT32 `CIDATA` cloud-init 配置盘；
- 创建并配置第二代 Hyper-V 虚拟机；
- 设置 CPU、动态内存、虚拟交换机、安全启动和自动检查点；
- 写入 SSH 公钥、生成独立主机身份，并通过 DHCP 获取地址；
- 创建前显示完整核对清单，只有输入 `CREATE` 才执行；
- 拒绝覆盖已有 VM/磁盘，失败时回滚本次产生的不完整资源。

仓库同时保留两种使用模式：

- `New-DebianWizard.ps1`：推荐的单文件交互向导；
- `debian-cloud-init/`：拆分为 CIDATA、差分盘和 VM 三步的学习/排错版本。

## 前提

- Windows 10/11 Pro、Enterprise 或 Windows Server；
- 已启用 Hyper-V；
- 以管理员身份运行 Windows PowerShell 5.1 或更高版本；
- 已准备只读母盘：

  ```text
  C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\mother\debian-13-base.vhdx
  ```

- 已创建 Hyper-V 虚拟交换机；多台 VM 接入局域网时推荐绑定有线网卡的外部交换机；
- 准备一个 SSH 公钥，可粘贴完整内容，也可提供 `.pub` 文件路径。

## 仓库内容

```text
.
├── New-DebianWizard.ps1
├── debian-cloud-init/
│   ├── New-DebianCidata.ps1
│   ├── New-DebianDisk.ps1
│   ├── New-DebianVM.ps1
│   ├── common-network-config
│   ├── common-user-data.example
│   └── README.md
├── README.md
├── .gitattributes
└── .gitignore
```

仓库不包含母盘、差分盘、CIDATA VHDX、RAW、QCOW2 或个人 SSH 公钥。

## 运行

将 `New-DebianWizard.ps1` 复制到 Hyper-V 宿主机，以管理员身份打开 PowerShell：

如果当前正在资源管理器的脚本目录中，可在地址栏粘贴下面整行。它会触发 UAC，并在同一个目录打开管理员 PowerShell：

```powershell
powershell -NoProfile -Command "$here=(Get-Location).Path; Start-Process powershell -Verb RunAs -ArgumentList '-NoExit','-Command',('Set-Location -LiteralPath ''{0}''' -f $here)"
```

然后执行：

```powershell
Unblock-File .\New-DebianWizard.ps1
.\New-DebianWizard.ps1
```

向导会询问：

1. Debian 实例编号；
2. 虚拟交换机；
3. 虚拟处理器数量；
4. 动态内存最小值、启动值和最大值；
5. 是否启用安全启动；
6. 是否启用自动检查点；
7. 是否创建后立即启动；
8. SSH 公钥文件路径或完整公钥。

直接回车接受方括号中的默认值。默认配置为：

```text
CPU                       8
动态内存                  256MB / 512MB / 512MB
安全启动                  关闭
自动检查点                关闭
创建后启动                关闭
交换机                    优先推荐 Realtek Gaming 2.5GbE 有线外部交换机
```

最后会显示核对清单。确认无误后输入大写：

```text
CREATE
```

输入其他内容或直接回车都会安全取消。

## 默认输出

以 `debian-9` 为例：

```text
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\children\debian9\
├── Virtual Machines\
└── Virtual Hard Disks\
    ├── debian-9-os.vhdx
    └── debian-9-cidata.vhdx
```

手动启动：

```powershell
Start-VM -Name 'debian-9'
```

首次启动会执行 cloud-init 并自动重启一次。随后查看 DHCP 地址并登录：

```bash
ssh debian@VM_IP -i /path/to/private_key
```

## cloud-init 行为

- 创建 `debian` 管理用户；
- 禁止 root 和 SSH 密码登录；
- 使用运行向导时提供的 SSH 公钥；
- 每台 VM 重新生成 SSH 主机密钥和 `machine-id`；
- DHCP 使用虚拟网卡 MAC 作为客户端标识；
- 自动扩展根分区和文件系统；
- 安装 `hyperv-daemons`、`curl` 和 `ca-certificates`；
- 初始化完成后重启一次。

## 安全说明

- 母盘必须保持原路径并保持只读；所有差分系统盘都依赖它。
- 向导不会覆盖同名 VM、系统盘或 CIDATA 盘。
- 创建失败时，只回滚本次运行新建的 VM 和磁盘。
- SSH 私钥不会被读取、复制或写入 VM。
- SSH 公钥不会保存在仓库源码中，仅在运行时写入对应 CIDATA 盘。
