# Modular Debian cloud-init workflow

这是单文件向导的分步骤版本，适合学习、调试或只重做某一层。

## 文件

```text
debian-cloud-init/
├── New-DebianCidata.ps1       # 创建 CIDATA 配置盘
├── New-DebianDisk.ps1         # 创建差分系统盘
├── New-DebianVM.ps1           # 使用两块现有磁盘创建 VM
├── common-network-config      # 可提交的通用网络配置
├── common-user-data.example   # 已脱敏的用户配置模板
└── common-user-data           # 本地实际配置，Git 忽略
```

推荐日常使用仓库根目录的 `New-DebianWizard.ps1`。这里的三个脚本故意保持分离，方便观察每一步。

## 准备个人配置

首次使用时复制模板：

```powershell
Copy-Item .\common-user-data.example .\common-user-data
notepad .\common-user-data
```

将下面的占位符替换为完整 SSH 公钥：

```text
REPLACE_WITH_YOUR_COMPLETE_SSH_PUBLIC_KEY
```

`common-user-data` 含个人公钥，已被 `.gitignore` 排除；不要强制提交。

## 创建实例

以 `debian-10` 为例，在管理员 PowerShell 中依次执行：

```powershell
.\New-DebianCidata.ps1 -Number 10
.\New-DebianDisk.ps1 -Number 10

.\New-DebianVM.ps1 `
  -Number 10 `
  -SwitchName '黄小庞' `
  -ProcessorCount 8 `
  -MinimumMemory 256MB `
  -StartupMemory 512MB `
  -MaximumMemory 512MB `
  -SecureBoot $false `
  -AutomaticCheckpoints $false `
  -StartAfterCreation $false
```

然后启动：

```powershell
Start-VM -Name 'debian-10'
```

默认母盘位置：

```text
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\mother\debian-13-base.vhdx
```

默认实例位置：

```text
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\children\debian10\Virtual Hard Disks\
```

## 各层职责

- `debian-N-os.vhdx`：只保存相对只读母盘发生的系统变化；
- `debian-N-cidata.vhdx`：保存 `meta-data`、`user-data` 和 `network-config`；
- Hyper-V VM 配置：保存 CPU、动态内存、交换机、安全启动和检查点设置。

母盘必须保持只读且不能移动。CIDATA 盘不要设置 Windows 只读属性。
