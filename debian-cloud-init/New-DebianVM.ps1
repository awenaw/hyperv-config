#Requires -Version 5.1
#Requires -RunAsAdministrator

<#
.SYNOPSIS
Create and configure a Generation 2 Debian Hyper-V VM from existing disks.

.EXAMPLE
.\New-DebianVM.ps1 -Number 8

.EXAMPLE
.\New-DebianVM.ps1 -Number 8 -SwitchName 'Your wired switch' -StartAfterCreation $true
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(1, 9999)]
    [int]$Number,

    [string]$DiskRoot = 'C:\ProgramData\Microsoft\Windows\Virtual Hard Disks',

    [string]$SwitchName = '',

    [string]$WiredAdapterPattern = '*Realtek Gaming 2.5GbE*',

    [ValidateRange(1, 64)]
    [int]$ProcessorCount = 8,

    [ValidateRange(256MB, 1TB)]
    [long]$MinimumMemory = 2GB,

    [ValidateRange(256MB, 1TB)]
    [long]$StartupMemory = 4GB,

    [ValidateRange(256MB, 1TB)]
    [long]$MaximumMemory = 8GB,

    [bool]$SecureBoot = $false,

    [bool]$AutomaticCheckpoints = $false,

    [bool]$StartAfterCreation = $false
)

$ErrorActionPreference = 'Stop'

$vmName = "debian-$Number"
$vmFolder = "debian$Number"
$vmPath = Join-Path $DiskRoot "children\$vmFolder"
$diskDirectory = Join-Path $vmPath 'Virtual Hard Disks'
$osDisk = Join-Path $diskDirectory "$vmName-os.vhdx"
$cidataDisk = Join-Path $diskDirectory "$vmName-cidata.vhdx"

if ($MinimumMemory -gt $StartupMemory -or $StartupMemory -gt $MaximumMemory) {
    throw 'Memory values must satisfy MinimumMemory <= StartupMemory <= MaximumMemory.'
}

if (Get-VM -Name $vmName -ErrorAction SilentlyContinue) {
    throw "VM already exists; refusing to overwrite: $vmName"
}

if (-not (Test-Path -LiteralPath $osDisk -PathType Leaf)) {
    throw "OS disk not found: $osDisk"
}

if (-not (Test-Path -LiteralPath $cidataDisk -PathType Leaf)) {
    throw "CIDATA disk not found: $cidataDisk"
}

if ([string]::IsNullOrWhiteSpace($SwitchName)) {
    $wiredSwitches = @(
        Get-VMSwitch -SwitchType External |
            Where-Object {
                $_.NetAdapterInterfaceDescription -like $WiredAdapterPattern
            }
    )

    if ($wiredSwitches.Count -ne 1) {
        $available = (Get-VMSwitch | Select-Object -ExpandProperty Name) -join ', '
        throw "Could not select exactly one wired switch. Available switches: $available. Specify -SwitchName explicitly."
    }

    $SwitchName = $wiredSwitches[0].Name
}
elseif (-not (Get-VMSwitch -Name $SwitchName -ErrorAction SilentlyContinue)) {
    throw "Virtual switch not found: $SwitchName"
}

$vm = New-VM `
    -Name $vmName `
    -Generation 2 `
    -Path $vmPath `
    -MemoryStartupBytes $StartupMemory `
    -VHDPath $osDisk `
    -SwitchName $SwitchName

Set-VMProcessor -VMName $vmName -Count $ProcessorCount

Set-VMMemory `
    -VMName $vmName `
    -DynamicMemoryEnabled $true `
    -MinimumBytes $MinimumMemory `
    -StartupBytes $StartupMemory `
    -MaximumBytes $MaximumMemory

Add-VMHardDiskDrive `
    -VMName $vmName `
    -ControllerType SCSI `
    -ControllerNumber 0 `
    -ControllerLocation 1 `
    -Path $cidataDisk

$osDrive = Get-VMHardDiskDrive -VMName $vmName |
    Where-Object { $_.Path -eq $osDisk }

if ($SecureBoot) {
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
    -AutomaticCheckpointsEnabled $AutomaticCheckpoints

Write-Host ''
Write-Host "Created and configured VM: $vmName" -ForegroundColor Green
Write-Host "Switch : $SwitchName"
Write-Host "CPU    : $ProcessorCount"
Write-Host "Memory : $($MinimumMemory / 1GB) GB min / $($StartupMemory / 1GB) GB startup / $($MaximumMemory / 1GB) GB max"
Write-Host "OS     : $osDisk"
Write-Host "CIDATA : $cidataDisk"
Write-Host "Secure Boot: $SecureBoot"
Write-Host "Automatic checkpoints: $AutomaticCheckpoints"

if ($StartAfterCreation) {
    Start-VM -Name $vmName | Out-Null
    Write-Host "Started: $vmName" -ForegroundColor Cyan
}
else {
    Write-Host ''
    Write-Host "Review the VM, then run: Start-VM -Name '$vmName'" -ForegroundColor Cyan
}
