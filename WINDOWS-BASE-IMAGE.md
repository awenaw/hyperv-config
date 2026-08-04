# 在 Windows 上制作 Debian Hyper-V 母盘

本文记录如何直接在 Windows 宿主机上，将 Debian 官方 QCOW2 云镜像转换为 Hyper-V 可用的动态 VHDX 母盘。整个过程不需要 ISO，也不需要启动 QEMU 虚拟机。

示例布局：

```text
C:\Hyper-V\
├── mother\
│   └── debian-13-base.vhdx
└── children\
```

## 1. 下载 Debian 官方云镜像

用浏览器下载：

- <https://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2>

默认假设文件位于：

```text
C:\Users\你的用户名\Downloads\debian-13-generic-amd64.qcow2
```

`generic` 镜像使用标准 Debian 内核，适合作为兼容性优先的 Hyper-V 基础镜像。`latest` 指向当前最新版，重新制作母盘时实际内容可能已经更新。

## 2. 安装 QEMU for Windows

打开 QEMU 官方下载页推荐的 Windows 64 位安装包目录：

- <https://qemu.weilnetz.de/w64/>

下载并运行 `qemu-w64-setup-日期.exe`。默认安装目录通常是：

```text
C:\Program Files\qemu
```

在 PowerShell 中确认 `qemu-img.exe` 可用：

```powershell
& 'C:\Program Files\qemu\qemu-img.exe' --version
```

QEMU 在这里仅作为磁盘格式转换工具，不会替代或影响 Hyper-V。

## 3. 转换 QCOW2 为动态 VHDX

关闭正在使用目标文件的程序，以管理员身份打开 PowerShell，然后设置路径：

```powershell
$QemuImg = 'C:\Program Files\qemu\qemu-img.exe'
$Source   = "$env:USERPROFILE\Downloads\debian-13-generic-amd64.qcow2"
$Parent   = 'C:\Hyper-V\mother\debian-13-base.vhdx'
```

确认 `C:\Hyper-V\mother` 已存在，并确认目标 VHDX 不需要保留。然后执行转换：

```powershell
& $QemuImg convert -p `
  -f qcow2 `
  -O vhdx `
  -o subformat=dynamic `
  $Source `
  $Parent
```

查看转换结果：

```powershell
& $QemuImg info $Parent
Get-VHD -Path $Parent | Format-List Path,VhdType,Size,FileSize
```

动态 VHDX 的 `Size` 是虚拟容量，`FileSize` 才是宿主机当前实际占用，两者不同是正常现象。

## 4. 将虚拟容量扩展到 32 GB

扩容只增加磁盘的虚拟上限，不会立即占用 32 GB 宿主机空间：

```powershell
Resize-VHD -Path $Parent -SizeBytes 32GB
```

也可以使用 Hyper-V 管理器：

```text
编辑磁盘 → 选择母盘 → 扩展 → 32 GB
```

这里仅扩展虚拟磁盘。子虚拟机首次启动时，cloud-init 会通过 `growpart` 和 `resize_rootfs` 扩展根分区及文件系统。

## 5. 将母盘设为只读

确认扩容完成后：

```powershell
(Get-Item -LiteralPath $Parent).IsReadOnly = $true
Get-Item -LiteralPath $Parent | Select-Object FullName,Length,IsReadOnly
```

从此不要直接启动、修改、移动或删除母盘。所有差分子盘都依赖母盘的内容和路径。

如果尚未创建任何差分子盘，需要重新加工母盘，可以先解除只读：

```powershell
(Get-Item -LiteralPath $Parent).IsReadOnly = $false
```

加工完毕后必须重新设为只读。

## 6. 交给 Debian 创建向导

当前仓库脚本的默认路径仍是 `C:\ProgramData\Microsoft\Windows\Virtual Hard Disks`。使用本布局时明确传入两个参数：

```powershell
.\New-DebianWizard.ps1 `
  -DiskRoot 'C:\Hyper-V' `
  -ParentDisk 'C:\Hyper-V\mother\debian-13-base.vhdx'
```

向导会基于母盘创建差分系统盘，并将每台虚拟机的文件放入：

```text
C:\Hyper-V\children\debianN\
└── Virtual Hard Disks\
    ├── debian-N-os.vhdx
    └── debian-N-cidata.vhdx
```

## 最终核对清单

- [ ] 镜像来源是 Debian 官方 `generic-amd64.qcow2`
- [ ] 输出格式是动态 VHDX
- [ ] `Get-VHD` 可以正常读取母盘
- [ ] 母盘虚拟容量已经扩展到 32 GB
- [ ] 母盘位于 `C:\Hyper-V\mother\debian-13-base.vhdx`
- [ ] 母盘已经设为只读
- [ ] 没有直接把母盘挂载到正在运行的虚拟机
- [ ] 向导同时传入了正确的 `DiskRoot` 和 `ParentDisk`

