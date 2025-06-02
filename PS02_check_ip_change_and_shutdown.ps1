
###############################################
# Script Owner: Esmaeil Yazdani               #
# Email: Esmaeil.Yazdani@Hotmail.Com          #
# Copyright © 2025 All Rights Reserved        #
# Github: https://github.com/esmaeilyazdani   #
# Linkedin: https://github.com/esmaeilyazdani #
###############################################
# -------------------------------
# Step 1: Disable Wi-Fi and Virtual Adapters
# -------------------------------
$adaptersToDisable = Get-NetAdapter | Where-Object {
    ($_.InterfaceDescription -match "Wi[- ]?Fi" -or
     $_.Name -match "Wi[- ]?Fi" -or
     $_.InterfaceType -eq 71) -or
    ($_.InterfaceDescription -match "vmware|virtualbox|hyper-v|vethernet" -or
     $_.Name -match "vmware|virtualbox|hyper-v|vethernet" -or
     ($_.InterfaceType -eq 6 -and $_.HardwareInterface -eq $false))
}

foreach ($adapter in $adaptersToDisable) {
    if ($adapter.Status -eq "Up") {
        Disable-NetAdapter -Name $adapter.Name -Confirm:$false
    }
}

# -------------------------------
# Step 2: Define paths and timestamps
# -------------------------------
$now = Get-Date
$today = $now.ToString("yyyy-MM-dd")
$timestamp = $now.ToString("HH-mm-ss")
$ipFolder = "$env:ProgramData\IPMonitor"
$initialFile = Join-Path $ipFolder "ip_${today}_initial.json"
$latestFile = Join-Path $ipFolder "ip_${today}_latest.json"

if (-not (Test-Path $ipFolder)) {
    New-Item -Path $ipFolder -ItemType Directory -Force | Out-Null
}

# Remove previous latest snapshot
if (Test-Path $latestFile) {
    Remove-Item $latestFile -Force
}

# -------------------------------
# Step 3: Filter only physical Ethernet interfaces (ignore VPNs)
# -------------------------------
$ethernetAdapters = Get-NetAdapter | Where-Object {
    $_.InterfaceType -eq 6 -and $_.Status -eq "Up" -and $_.HardwareInterface -eq $true -and
    ($_.InterfaceDescription -notmatch "vpn" -and $_.Name -notmatch "vpn")
}

$currentMap = @{}
foreach ($adapter in $ethernetAdapters) {
    $adapterIPs = Get-NetIPAddress -InterfaceIndex $adapter.InterfaceIndex -AddressFamily IPv4 | Where-Object {
        $_.IPAddress -notlike "169.254*" -and $_.IPAddress -notlike "127.*"
    }
    foreach ($ip in $adapterIPs) {
        $currentMap[$adapter.Name] = $ip.IPAddress
    }
}

# -------------------------------
# Step 4: Save initial file if not present
# -------------------------------
if (-not (Test-Path $initialFile)) {
    $currentMap | ConvertTo-Json -Depth 2 | Out-File $initialFile -Encoding UTF8
    Write-Host "Initial IP snapshot created."
    exit
}

# Save new latest snapshot
$currentMap | ConvertTo-Json -Depth 2 | Out-File $latestFile -Encoding UTF8

# -------------------------------
# Step 5: Load and compare with initial
# -------------------------------
$savedJson = Get-Content $initialFile -Raw
$oldMap = $savedJson | ConvertFrom-Json

$oldHash = @{}
foreach ($item in $oldMap.PSObject.Properties) {
    $oldHash[$item.Name] = $item.Value
}

foreach ($key in $currentMap.Keys) {
    if ($oldHash.ContainsKey($key)) {
        if ($currentMap[$key] -ne $oldHash[$key]) {
            Write-Host "IP changed on physical Ethernet interface '$key'"
            shutdown /r /t 0
            exit
        }
    } else {
        Write-Host "New physical Ethernet interface '$key' detected"
        shutdown /r /t 0
        exit
    }
}

foreach ($key in $oldHash.Keys) {
    if (-not $currentMap.ContainsKey($key)) {
        Write-Host "Physical Ethernet interface '$key' is missing"
        shutdown /r /t 0
        exit
    }
}

Write-Host "No changes detected in physical Ethernet IPs."
