#Requires -Version 5.1
#Requires -RunAsAdministrator
#Requires -Modules Hyper-V

<#
.SYNOPSIS
Interactive, self-contained Debian Hyper-V VM creation wizard.

.DESCRIPTION
Creates all three layers in one run:
  1. A differencing OS VHDX based on the read-only Debian parent disk.
  2. A FAT32 NoCloud CIDATA VHDX with embedded cloud-init configuration.
  3. A Generation 2 Hyper-V VM with both disks attached.

The script refuses to overwrite an existing VM or disk.
#>

[CmdletBinding()]
param(
    [string]$DiskRoot = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks',

    [string]$ParentDisk = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\mother\debian-13-base.vhdx'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-Integer {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [int]$Default,

        [int]$Minimum = 1,

        [int]$Maximum = 9999
    )

    while ($true) {
        $inputValue = Read-Host "$Label [$Default]"
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            return $Default
        }

        $parsed = 0
        if ([int]::TryParse($inputValue, [ref]$parsed) -and
            $parsed -ge $Minimum -and
            $parsed -le $Maximum) {
            return $parsed
        }

        Write-Host "Enter an integer from $Minimum to $Maximum." -ForegroundColor Yellow
    }
}

function Read-MemoryBytes {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [Parameter(Mandatory = $true)]
        [string]$Default
    )

    while ($true) {
        $inputValue = Read-Host "$Label [$Default]"
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            $inputValue = $Default
        }

        if ($inputValue -match '^\s*([0-9]+)\s*(MB|GB)\s*$') {
            $amount = [int64]$matches[1]
            $unit = $matches[2].ToUpperInvariant()
            if ($amount -gt 0) {
                if ($unit -eq 'GB') {
                    return $amount * 1GB
                }
                return $amount * 1MB
            }
        }

        Write-Host 'Enter a value such as 256MB, 512MB, 2GB, or 8GB.' -ForegroundColor Yellow
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Label,

        [bool]$Default = $false
    )

    $suffix = if ($Default) { '[Y/n]' } else { '[y/N]' }
    while ($true) {
        $inputValue = Read-Host "$Label $suffix"
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            return $Default
        }

        switch ($inputValue.Trim().ToLowerInvariant()) {
            'y' { return $true }
            'yes' { return $true }
            'n' { return $false }
            'no' { return $false }
        }

        Write-Host 'Enter y or n.' -ForegroundColor Yellow
    }
}

function Read-SshPublicKey {
    while ($true) {
        Write-Host ''
        $inputValue = Read-Host 'SSH public key file path, or paste the complete public key'
        if ([string]::IsNullOrWhiteSpace($inputValue)) {
            Write-Host 'An SSH public key is required.' -ForegroundColor Yellow
            continue
        }

        $candidate = $inputValue.Trim()
        if (Test-Path -LiteralPath $candidate -PathType Leaf) {
            $candidate = (Get-Content -LiteralPath $candidate -Raw).Trim()
        }

        if ($candidate -match '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+[A-Za-z0-9+/=]+(?:\s+.*)?$') {
            return $candidate
        }

        Write-Host 'The SSH public key format is invalid. Use a .pub file or paste one complete public-key line.' -ForegroundColor Yellow
    }
}

function Format-Memory {
    param([int64]$Bytes)

    if (($Bytes % 1GB) -eq 0) {
        return "$(($Bytes / 1GB))GB"
    }
    return "$(($Bytes / 1MB))MB"
}

function Write-Utf8WithoutBom {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $encoding = [System.Text.UTF8Encoding]::new($false)
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Get-SuggestedNumber {
    param([string]$Root)

    $numbers = @()

    foreach ($vm in @(Get-VM -ErrorAction SilentlyContinue)) {
        if ($vm.Name -match '^debian-([0-9]+)$') {
            $numbers += [int]$matches[1]
        }
    }

    $childrenRoot = Join-Path $Root 'children'
    if (Test-Path -LiteralPath $childrenRoot -PathType Container) {
        foreach ($directory in @(Get-ChildItem -LiteralPath $childrenRoot -Directory)) {
            if ($directory.Name -match '^debian([0-9]+)$') {
                $numbers += [int]$matches[1]
            }
        }
    }

    if ($numbers.Count -eq 0) {
        return 1
    }

    return (($numbers | Measure-Object -Maximum).Maximum + 1)
}

if (-not (Test-Path -LiteralPath $ParentDisk -PathType Leaf)) {
    throw "Parent disk not found: $ParentDisk"
}

$switches = @(Get-VMSwitch | Sort-Object Name)
if ($switches.Count -eq 0) {
    throw 'No Hyper-V virtual switches were found.'
}

Write-Host ''
Write-Host 'Debian Hyper-V Creation Wizard' -ForegroundColor Cyan
Write-Host '================================'
Write-Host ''

$suggestedNumber = Get-SuggestedNumber -Root $DiskRoot
$number = Read-Integer -Label 'Debian instance number' -Default $suggestedNumber
$vmName = "debian-$number"
$vmFolder = "debian$number"
$vmPath = Join-Path $DiskRoot "children\$vmFolder"
$diskDirectory = Join-Path $vmPath 'Virtual Hard Disks'
$osDisk = Join-Path $diskDirectory "$vmName-os.vhdx"
$cidataDisk = Join-Path $diskDirectory "$vmName-cidata.vhdx"

Write-Host ''
Write-Host 'Available virtual switches:' -ForegroundColor Cyan

$defaultSwitchIndex = 0
for ($index = 0; $index -lt $switches.Count; $index++) {
    $switch = $switches[$index]
    $description = $switch.NetAdapterInterfaceDescription
    if ([string]::IsNullOrWhiteSpace($description)) {
        $description = '-'
    }

    if ($switch.NetAdapterInterfaceDescription -like '*Realtek Gaming 2.5GbE*') {
        $defaultSwitchIndex = $index
    }

    Write-Host ('[{0}] {1} | {2} | {3}' -f ($index + 1), $switch.Name, $switch.SwitchType, $description)
}

$switchChoice = Read-Integer `
    -Label 'Select virtual switch' `
    -Default ($defaultSwitchIndex + 1) `
    -Minimum 1 `
    -Maximum $switches.Count

$selectedSwitch = $switches[$switchChoice - 1]
$processorCount = Read-Integer -Label 'Virtual processor count' -Default 8 -Minimum 1 -Maximum 64
$minimumMemory = Read-MemoryBytes -Label 'Dynamic memory minimum' -Default '256MB'
$startupMemory = Read-MemoryBytes -Label 'Startup memory' -Default '512MB'
$maximumMemory = Read-MemoryBytes -Label 'Dynamic memory maximum' -Default '512MB'

if ($minimumMemory -gt $startupMemory -or $startupMemory -gt $maximumMemory) {
    throw 'Memory values must satisfy minimum <= startup <= maximum.'
}

$secureBoot = Read-YesNo -Label 'Enable Secure Boot?' -Default $false
$automaticCheckpoints = Read-YesNo -Label 'Enable automatic checkpoints?' -Default $false
$startAfterCreation = Read-YesNo -Label 'Start VM after creation?' -Default $false
$sshPublicKey = Read-SshPublicKey
$sshKeyParts = @($sshPublicKey -split '\s+', 3)
$sshKeySummary = $sshKeyParts[0]
if ($sshKeyParts.Count -ge 3) {
    $sshKeySummary = "$sshKeySummary | $($sshKeyParts[2])"
}

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    throw "VM already exists: $vmName"
}

if (Test-Path -LiteralPath $osDisk) {
    throw "OS disk already exists: $osDisk"
}

if (Test-Path -LiteralPath $cidataDisk) {
    throw "CIDATA disk already exists: $cidataDisk"
}

Write-Host ''
Write-Host 'FINAL CONFIRMATION CHECKLIST' -ForegroundColor Cyan
Write-Host '============================'
Write-Host "[ ] VM name is correct                : $vmName"
Write-Host "[ ] VM location is correct            : $vmPath"
Write-Host "[ ] Parent disk is correct            : $ParentDisk"
Write-Host "[ ] Parent disk is read-only          : $((Get-Item -LiteralPath $ParentDisk).IsReadOnly)"
Write-Host "[ ] New OS disk path is correct       : $osDisk"
Write-Host "[ ] New CIDATA disk path is correct   : $cidataDisk"
Write-Host "[ ] Wired virtual switch is correct   : $($selectedSwitch.Name)"
Write-Host "[ ] Processor count is correct        : $processorCount"
Write-Host "[ ] Dynamic memory is correct         : $(Format-Memory $minimumMemory) min / $(Format-Memory $startupMemory) startup / $(Format-Memory $maximumMemory) max"
Write-Host "[ ] Secure Boot setting is correct    : $secureBoot"
Write-Host "[ ] Automatic checkpoints are correct : $automaticCheckpoints"
Write-Host "[ ] Start-after-create is correct     : $startAfterCreation"
Write-Host '[ ] Existing VM and disks will not be overwritten'
Write-Host "[ ] SSH public key is correct            : $sshKeySummary"
Write-Host ''
Write-Host 'Review every item above.' -ForegroundColor Yellow
$confirmation = Read-Host 'Type CREATE to confirm, or press Enter to cancel'

if ($confirmation -cne 'CREATE') {
    Write-Host 'Cancelled. Nothing was changed.' -ForegroundColor Yellow
    exit 0
}

$userData = @'
## template: jinja
#cloud-config
hostname: "{{ v1.local_hostname }}"
manage_etc_hosts: true

users:
  - name: debian
    gecos: Debian Administrator
    groups: [adm, sudo]
    shell: /bin/bash
    sudo: ALL=(ALL) NOPASSWD:ALL
    lock_passwd: true
    ssh_authorized_keys:
      - '__SSH_PUBLIC_KEY__'

disable_root: true
ssh_pwauth: false

ssh_deletekeys: true
ssh_genkeytypes:
  - rsa
  - ecdsa
  - ed25519

growpart:
  mode: auto
  devices: ['/']
resize_rootfs: true

bootcmd:
  - [cloud-init-per, instance, unique-machine-id, sh, -c, 'new_id=$(tr -d "-" < /proc/sys/kernel/random/uuid); printf "%s\n" "$new_id" > /etc/machine-id; rm -f /var/lib/dbus/machine-id; ln -s /etc/machine-id /var/lib/dbus/machine-id; systemctl restart systemd-networkd']

package_update: true
packages:
  - hyperv-daemons
  - curl
  - ca-certificates

final_message: "Debian {{ v1.local_hostname }} is ready."

power_state:
  mode: reboot
  delay: now
  message: Rebooting with unique machine-id
  timeout: 30
  condition: true
'@

$userData = $userData.Replace('__SSH_PUBLIC_KEY__', $sshPublicKey.Replace("'", "''"))

$networkConfig = @'
version: 2
ethernets:
  eth0:
    dhcp4: true
    dhcp-identifier: mac
'@

$vmCreated = $false
$osDiskCreated = $false
$cidataDiskCreated = $false
$cidataMounted = $false

try {
    New-Item -ItemType Directory -Path $diskDirectory -Force | Out-Null

    Write-Host ''
    Write-Host '[1/3] Creating differencing OS disk...'
    New-VHD -Path $osDisk -ParentPath $ParentDisk -Differencing | Out-Null
    $osDiskCreated = $true

    Write-Host '[2/3] Creating CIDATA disk...'
    New-VHD -Path $cidataDisk -SizeBytes 64MB -Dynamic | Out-Null
    $cidataDiskCreated = $true

    $disk = Mount-VHD -Path $cidataDisk -Passthru | Get-Disk
    $cidataMounted = $true

    $partition = $disk |
        Initialize-Disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -AssignDriveLetter

    $volume = $partition |
        Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Force -Confirm:$false

    $volumeRoot = "$($volume.DriveLetter):\"
    $metaData = "instance-id: $vmName-001`nlocal-hostname: $vmName`n"

    Write-Utf8WithoutBom -Path (Join-Path $volumeRoot 'meta-data') -Content $metaData
    Write-Utf8WithoutBom -Path (Join-Path $volumeRoot 'user-data') -Content $userData
    Write-Utf8WithoutBom -Path (Join-Path $volumeRoot 'network-config') -Content $networkConfig

    Dismount-VHD -Path $cidataDisk
    $cidataMounted = $false

    Write-Host '[3/3] Creating and configuring VM...'
    New-VM `
        -Name $vmName `
        -Generation 2 `
        -Path $vmPath `
        -MemoryStartupBytes $startupMemory `
        -VHDPath $osDisk `
        -SwitchName $selectedSwitch.Name |
        Out-Null

    $vmCreated = $true

    Set-VMProcessor -VMName $vmName -Count $processorCount

    Set-VMMemory `
        -VMName $vmName `
        -DynamicMemoryEnabled $true `
        -MinimumBytes $minimumMemory `
        -StartupBytes $startupMemory `
        -MaximumBytes $maximumMemory

    Add-VMHardDiskDrive `
        -VMName $vmName `
        -ControllerType SCSI `
        -ControllerNumber 0 `
        -ControllerLocation 1 `
        -Path $cidataDisk

    $osDrive = Get-VMHardDiskDrive -VMName $vmName |
        Where-Object { $_.Path -eq $osDisk }

    if ($secureBoot) {
        Set-VMFirmware `
            -VMName $vmName `
            -EnableSecureBoot On `
            -SecureBootTemplate 'MicrosoftUEFICertificateAuthority' `
            -FirstBootDevice $osDrive
    }
    else {
        Set-VMFirmware `
            -VMName $vmName `
            -EnableSecureBoot Off `
            -FirstBootDevice $osDrive
    }

    Set-VM `
        -VMName $vmName `
        -AutomaticCheckpointsEnabled $automaticCheckpoints
}
catch {
    $failure = $_

    if ($cidataMounted) {
        Dismount-VHD -Path $cidataDisk -ErrorAction SilentlyContinue
    }

    if ($vmCreated) {
        Stop-VM -Name $vmName -TurnOff -Force -ErrorAction SilentlyContinue
        Remove-VM -Name $vmName -Force -ErrorAction SilentlyContinue
    }

    if ($cidataDiskCreated -and (Test-Path -LiteralPath $cidataDisk)) {
        Remove-Item -LiteralPath $cidataDisk -Force -ErrorAction SilentlyContinue
    }

    if ($osDiskCreated -and (Test-Path -LiteralPath $osDisk)) {
        Remove-Item -LiteralPath $osDisk -Force -ErrorAction SilentlyContinue
    }

    Write-Host ''
    Write-Host 'Creation failed. New partial VM and disks were rolled back.' -ForegroundColor Red
    throw $failure
}

Write-Host ''
Write-Host "Created successfully: $vmName" -ForegroundColor Green
Write-Host "OS disk    : $osDisk"
Write-Host "CIDATA disk: $cidataDisk"
Write-Host "Switch     : $($selectedSwitch.Name)"

if ($startAfterCreation) {
    Start-VM -Name $vmName | Out-Null
    Write-Host "Started: $vmName" -ForegroundColor Cyan
}
else {
    Write-Host "Start later: Start-VM -Name '$vmName'" -ForegroundColor Cyan
}
