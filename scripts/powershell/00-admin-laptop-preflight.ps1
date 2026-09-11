[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Router,

    [Parameter(Mandatory = $true)]
    [string]$Active,

    [Parameter(Mandatory = $true)]
    [string]$Passive,

    [int]$MinFreeGB = 80,

    [string]$ArtifactRoot = "$HOME\pios-rebuild-artifacts"
)

$ErrorActionPreference = 'Stop'
$script:Fail = $false

function Pass([string]$Message) { Write-Host "PASS: $Message" }
function Warn([string]$Message) { Write-Warning $Message }
function Fail([string]$Message) { Write-Host "FAIL: $Message"; $script:Fail = $true }

Write-Host '===== ADMIN LAPTOP PRE-FLIGHT (POWERSHELL) ====='
Write-Host "computer=$env:COMPUTERNAME"
Write-Host "powershell=$($PSVersionTable.PSVersion)"
Write-Host "os=$([System.Runtime.InteropServices.RuntimeInformation]::OSDescription)"

Write-Host "`n===== REQUIRED TOOLS ====="
foreach ($cmd in @('ssh.exe','scp.exe','git.exe')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Pass $cmd
    }
    else {
        Fail "$cmd missing"
    }
}

Write-Host "`n===== OPTIONAL TOOLS ====="
foreach ($cmd in @('xz.exe','zstd.exe','7z.exe','rsync.exe','wsl.exe','tracert.exe')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Pass $cmd
    }
    else {
        Warn "$cmd not installed"
    }
}

Write-Host "`n===== ARTIFACT DIRECTORY ====="
if (-not (Test-Path $ArtifactRoot)) {
    New-Item -ItemType Directory -Path $ArtifactRoot -Force | Out-Null
}
$resolved = (Resolve-Path $ArtifactRoot).Path
$root = [System.IO.Path]::GetPathRoot($resolved)
$driveName = $root.Substring(0,1)
$drive = Get-PSDrive -Name $driveName
$freeGB = [math]::Floor($drive.Free / 1GB)
Write-Host "artifact_root=$resolved"
Write-Host "free_gb=$freeGB"
Write-Host "required_free_gb=$MinFreeGB"
if ($freeGB -ge $MinFreeGB) {
    Pass "local free space ${freeGB}GB"
}
else {
    Fail "only ${freeGB}GB free; require at least ${MinFreeGB}GB"
}

Write-Host "`n===== REPOSITORY ====="
try {
    $inside = (& git.exe rev-parse --is-inside-work-tree 2>$null).Trim()
    if ($inside -eq 'true') {
        Pass 'running inside a Git work tree'
        Write-Host "commit=$((& git.exe rev-parse HEAD).Trim())"
        $status = (& git.exe status --porcelain)
        if ([string]::IsNullOrWhiteSpace(($status -join "`n"))) {
            Pass 'working tree clean'
        }
        else {
            Warn 'working tree contains local modifications; review them before migration'
            $status | ForEach-Object { Write-Host $_ }
        }
    }
    else {
        Fail 'not running from a Git work tree'
    }
}
catch {
    Fail "unable to inspect Git repository: $($_.Exception.Message)"
}

Write-Host "`n===== VPN / SITE REACHABILITY ====="
try {
    if (Test-Connection -ComputerName $Router -Count 2 -Quiet -ErrorAction SilentlyContinue) {
        Pass "router reachable: $Router"
    }
    else {
        Warn "router did not answer ICMP: $Router (this may be intentional)"
    }
}
catch {
    Warn "router ICMP check failed: $($_.Exception.Message)"
}

function Test-SshTarget {
    param([string]$Target,[string]$Role)

    $output = & ssh.exe -o BatchMode=yes -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=3 $Target 'printf "hostname="; hostname; printf "uptime="; uptime' 2>&1
    if ($LASTEXITCODE -eq 0) {
        Pass "$Role SSH: $Target"
        $output | ForEach-Object { Write-Host $_ }
    }
    else {
        Fail "$Role SSH failed: $Target"
        $output | ForEach-Object { Write-Host $_ }
    }
}

if (Get-Command ssh.exe -ErrorAction SilentlyContinue) {
    Test-SshTarget -Target $Active -Role 'active'
    Test-SshTarget -Target $Passive -Role 'passive'
}

Write-Host "`n===== WINDOWS POWER / SESSION CHECK ====="
if (Get-Command powercfg.exe -ErrorAction SilentlyContinue) {
    & powercfg.exe /GETACTIVESCHEME 2>$null | ForEach-Object { Write-Host $_ }
}
Write-Host 'MANUAL: laptop connected to mains power'
Write-Host 'MANUAL: sleep/hibernate disabled for the maintenance window'
Write-Host 'MANUAL: VPN reconnect credentials available'
Write-Host 'MANUAL: artifact directory is on protected/encrypted storage where practical'
Write-Host 'MANUAL: retain at least 80 GB free when holding complete raw backups of both 32 GB cards'

Write-Host "`n===== RESULT ====="
if ($script:Fail) {
    Write-Host 'ADMIN_LAPTOP_PREFLIGHT=FAIL'
    exit 2
}

Write-Host 'ADMIN_LAPTOP_PREFLIGHT=PASS'
exit 0
