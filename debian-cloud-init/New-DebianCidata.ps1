#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Create a Debian cloud-init NoCloud CIDATA VHDX.

.EXAMPLE
.\New-DebianCidata.ps1 -Number 8

Required files next to this script:
  common-user-data
  common-network-config
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 9999)]
    [int]$Number,

    [string]$DiskRoot = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks',

    [string]$ConfigRoot = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'

$vmName = "debian-$Number"
$vmFolder = "debian$Number"
$diskDirectory = Join-Path $DiskRoot "children\$vmFolder\Virtual Hard Disks"
$cidataDisk = Join-Path $diskDirectory "$vmName-cidata.vhdx"
$userData = Join-Path $ConfigRoot 'common-user-data'
$networkConfig = Join-Path $ConfigRoot 'common-network-config'
$mounted = $false
$created = $false

if (-not (Test-Path -LiteralPath $userData -PathType Leaf)) {
    throw "Required file not found: $userData"
}

if (-not (Test-Path -LiteralPath $networkConfig -PathType Leaf)) {
    throw "Required file not found: $networkConfig"
}

if (Test-Path -LiteralPath $cidataDisk) {
    throw "Target disk already exists; refusing to overwrite: $cidataDisk"
}

New-Item -ItemType Directory -Path $diskDirectory -Force | Out-Null

try {
    New-VHD -Path $cidataDisk -SizeBytes 64MB -Dynamic | Out-Null
    $created = $true

    $disk = Mount-VHD -Path $cidataDisk -Passthru | Get-Disk
    $mounted = $true

    $partition = $disk |
        Initialize-Disk -PartitionStyle MBR -PassThru |
        New-Partition -UseMaximumSize -AssignDriveLetter

    $partition |
        Format-Volume -FileSystem FAT32 -NewFileSystemLabel 'CIDATA' -Force -Confirm:$false |
        Out-Null

    $volumeRoot = "$($partition.DriveLetter):\"
    $metaData = Join-Path $volumeRoot 'meta-data'

    @(
        "instance-id: $vmName-001"
        "local-hostname: $vmName"
    ) | Set-Content -LiteralPath $metaData -Encoding Ascii

    Copy-Item -LiteralPath $userData -Destination (Join-Path $volumeRoot 'user-data')
    Copy-Item -LiteralPath $networkConfig -Destination (Join-Path $volumeRoot 'network-config')

    $writtenFiles = Get-ChildItem -LiteralPath $volumeRoot |
        Select-Object Name, Length

    Dismount-VHD -Path $cidataDisk
    $mounted = $false

    Write-Host ''
    Write-Host "Created CIDATA disk for $vmName" -ForegroundColor Green
    Write-Host "Disk: $cidataDisk"
    $writtenFiles | Format-Table -AutoSize
}
catch {
    if ($mounted) {
        Dismount-VHD -Path $cidataDisk -ErrorAction SilentlyContinue
        $mounted = $false
    }

    if ($created -and (Test-Path -LiteralPath $cidataDisk)) {
        Remove-Item -LiteralPath $cidataDisk -Force
    }

    throw
}
finally {
    if ($mounted) {
        Dismount-VHD -Path $cidataDisk -ErrorAction SilentlyContinue
    }
}
