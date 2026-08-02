#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Create a Debian Hyper-V differencing OS disk.

.EXAMPLE
.\New-DebianDisk.ps1 -Number 8

Creates:
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\children\debian8\Virtual Hard Disks\debian-8-os.vhdx

Parent:
C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\mother\debian-13-base.vhdx
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 9999)]
    [int]$Number,

    [string]$DiskRoot = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks',

    [string]$ParentDisk = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks\mother\debian-13-base.vhdx'
)

$ErrorActionPreference = 'Stop'

$vmName = "debian-$Number"
$vmFolder = "debian$Number"
$diskDirectory = Join-Path $DiskRoot "children\$vmFolder\Virtual Hard Disks"
$childDisk = Join-Path $diskDirectory "$vmName-os.vhdx"

if (-not (Test-Path -LiteralPath $ParentDisk -PathType Leaf)) {
    throw "Parent disk not found: $ParentDisk"
}

if (Test-Path -LiteralPath $childDisk) {
    throw "Target disk already exists; refusing to overwrite: $childDisk"
}

# Create only the directory required by this VM.
New-Item -ItemType Directory -Path $diskDirectory -Force | Out-Null

# The parent disk must remain at the same path and stay read-only.
New-VHD -Path $childDisk -ParentPath $ParentDisk -Differencing | Out-Null

$createdDisk = Get-VHD -Path $childDisk

Write-Host ''
Write-Host "Created differencing OS disk for $vmName" -ForegroundColor Green
Write-Host "Child : $($createdDisk.Path)"
Write-Host "Parent: $($createdDisk.ParentPath)"
Write-Host "Type  : $($createdDisk.VhdType)"
Write-Host ''
Write-Host 'Next: create a Generation 2 VM and select Use an existing virtual hard disk.' -ForegroundColor Cyan
