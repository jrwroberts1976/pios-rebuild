[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('PI3-CENTOS7','PI4-CENTOS9')]
    [string]$Profile,

    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [string]$Active,

    [Parameter(Mandatory = $true)]
    [string]$Router,

    [string]$Site = '',
    [string]$ChangeReference = '',
    [string]$Interface = 'eth0',
    [string]$SdDevice = '/dev/mmcblk0',
    [string]$DebianImage = '',
    [string]$OutputDirectory = '',
    [string]$TemplatePath = ''
)

$ErrorActionPreference = 'Stop'

function Require-Command([string]$Name) {
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Required command missing: $Name"
    }
}

function Invoke-RemoteProbe {
    param(
        [Parameter(Mandatory = $true)][string]$RemoteTarget,
        [Parameter(Mandatory = $true)][string]$RemoteInterface,
        [Parameter(Mandatory = $true)][string]$RemoteSdDevice
    )

    $probe = @'
set -eu
printf 'hostname=%s\n' "$(hostname -f 2>/dev/null || hostname)"
printf 'model='
tr -d '\0' </proc/device-tree/model 2>/dev/null || true
printf '\n'
printf 'arch=%s\n' "$(uname -m)"
if [ -r /etc/os-release ]; then
  . /etc/os-release
  printf 'os_id=%s\n' "${ID:-unknown}"
  printf 'os_version=%s\n' "${VERSION_ID:-unknown}"
  printf 'os_pretty=%s\n' "${PRETTY_NAME:-unknown}"
else
  printf 'os_id=unknown\nos_version=unknown\nos_pretty=unknown\n'
fi
if [ -r "/sys/class/net/__IFACE__/address" ]; then
  printf 'mac=%s\n' "$(cat /sys/class/net/__IFACE__/address)"
else
  printf 'mac=unknown\n'
fi
if [ -b "__SDDEV__" ]; then
  printf 'sd_size_bytes=%s\n' "$(lsblk -bndo SIZE "__SDDEV__" 2>/dev/null || echo unknown)"
  printf 'sd_type=%s\n' "$(lsblk -ndo TYPE "__SDDEV__" 2>/dev/null || echo unknown)"
else
  printf 'sd_size_bytes=unknown\nsd_type=missing\n'
fi
'@

    $probe = $probe.Replace('__IFACE__', $RemoteInterface).Replace('__SDDEV__', $RemoteSdDevice)
    $output = $probe | & ssh.exe -o BatchMode=yes -o ConnectTimeout=10 $RemoteTarget 'sh -s' 2>&1
    if ($LASTEXITCODE -ne 0) {
        $output | ForEach-Object { Write-Host $_ }
        throw "Unable to probe remote host: $RemoteTarget"
    }

    $map = @{}
    foreach ($line in $output) {
        if ($line -match '^([^=]+)=(.*)$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    return $map
}

function Safe-Value($Map, [string]$Key, [string]$Default = 'unknown') {
    if ($Map.ContainsKey($Key) -and -not [string]::IsNullOrWhiteSpace([string]$Map[$Key])) {
        return [string]$Map[$Key]
    }
    return $Default
}

function Format-Bytes([string]$Value) {
    [Int64]$bytes = 0
    if ([Int64]::TryParse($Value, [ref]$bytes)) {
        return ('{0:N2} GB ({1} bytes)' -f ($bytes / 1GB), $bytes)
    }
    return 'unknown'
}

Require-Command 'git.exe'
Require-Command 'ssh.exe'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
Set-Location $repoRoot

$gitRoot = (& git.exe rev-parse --show-toplevel 2>$null).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($gitRoot)) {
    throw 'This script must be run from a Git checkout of pios-rebuild.'
}

$dirty = & git.exe status --porcelain
if ($LASTEXITCODE -ne 0) { throw 'Unable to inspect Git working tree.' }
if ($dirty) {
    throw 'Git working tree is not clean. Pin and review the release checkout before creating the release record.'
}

$gitCommit = (& git.exe rev-parse HEAD).Trim()
$gitBranch = (& git.exe branch --show-current).Trim()

if ([string]::IsNullOrWhiteSpace($TemplatePath)) {
    $TemplatePath = Join-Path $repoRoot 'docs\RELEASE_RECORD_TEMPLATE.md'
}
if (-not (Test-Path $TemplatePath)) {
    throw "Release record template not found: $TemplatePath"
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $repoRoot 'releases'
}
New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

Write-Host '===== CREATE ELECTRONIC RELEASE RECORD ====='
Write-Host "profile=$Profile"
Write-Host "target=$Target"
Write-Host "active=$Active"
Write-Host "router=$Router"
Write-Host "git_commit=$gitCommit"

Write-Host "`n===== PROBE TARGET ====="
$targetInfo = Invoke-RemoteProbe -RemoteTarget $Target -RemoteInterface $Interface -RemoteSdDevice $SdDevice
$targetInfo.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name)=$($_.Value)" }

Write-Host "`n===== PROBE ACTIVE PEER ====="
$activeInfo = Invoke-RemoteProbe -RemoteTarget $Active -RemoteInterface $Interface -RemoteSdDevice $SdDevice
$activeInfo.GetEnumerator() | Sort-Object Name | ForEach-Object { Write-Host "$($_.Name)=$($_.Value)" }

$targetModel = Safe-Value $targetInfo 'model'
$targetOsId = Safe-Value $targetInfo 'os_id'
$targetOsVersion = Safe-Value $targetInfo 'os_version'
$targetArch = Safe-Value $targetInfo 'arch'

switch ($Profile) {
    'PI4-CENTOS9' {
        $expectedDescription = 'Raspberry Pi 4 running CentOS 9, migrating to Debian 13 arm64'
        $hardwarePass = $targetModel -match '^Raspberry Pi 4'
        $osPass = ($targetOsId -eq 'centos') -and ($targetOsVersion -match '^9($|\.)')
    }
    'PI3-CENTOS7' {
        $expectedDescription = 'Raspberry Pi 3 running CentOS 7, migrating to Debian 13 arm64'
        $hardwarePass = $targetModel -match '^Raspberry Pi 3'
        $osPass = ($targetOsId -eq 'centos') -and ($targetOsVersion -match '^7($|\.)')
    }
}
$archPass = $targetArch -match '^(aarch64|arm64)$'
$overallPass = $hardwarePass -and $osPass -and $archPass

$hardwareResult = if ($hardwarePass) { 'PASS' } else { 'FAIL' }
$osResult = if ($osPass) { 'PASS' } else { 'FAIL' }
$archResult = if ($archPass) { 'PASS' } else { 'FAIL' }
$overallResult = if ($overallPass) { 'PASS' } else { 'NO-GO' }

$targetHostname = Safe-Value $targetInfo 'hostname'
$activeHostname = Safe-Value $activeInfo 'hostname'
$targetOsPretty = Safe-Value $targetInfo 'os_pretty'
$activeOsPretty = Safe-Value $activeInfo 'os_pretty'
$targetMac = Safe-Value $targetInfo 'mac'
$sdCapacity = Format-Bytes (Safe-Value $targetInfo 'sd_size_bytes')

$debianImageDisplay = if ([string]::IsNullOrWhiteSpace($DebianImage)) { '_fill in before change_' } else { $DebianImage }
$debianSha = '_fill in before change_'
if (-not [string]::IsNullOrWhiteSpace($DebianImage)) {
    if (-not (Test-Path $DebianImage)) { throw "Debian image not found: $DebianImage" }
    Write-Host "`nCalculating Debian image SHA512..."
    $debianSha = (Get-FileHash -Algorithm SHA512 -Path $DebianImage).Hash.ToLower()
    $debianImageDisplay = (Resolve-Path $DebianImage).Path
}

$engineer = (& git.exe config user.name).Trim()
if ([string]::IsNullOrWhiteSpace($engineer)) { $engineer = $env:USERNAME }
if ([string]::IsNullOrWhiteSpace($engineer)) { $engineer = 'unknown' }

$now = Get-Date
$date = $now.ToString('yyyy-MM-dd')
$createdAt = $now.ToString('yyyy-MM-dd HH:mm:ss zzz')
$createdTime = $now.ToString('HH:mm:ss')

if ([string]::IsNullOrWhiteSpace($ChangeReference)) {
    $ChangeReference = "PIOS-$($now.ToString('yyyyMMdd-HHmm'))-$Profile"
}

$safeHost = ($targetHostname -replace '[^A-Za-z0-9._-]', '-')
if ([string]::IsNullOrWhiteSpace($safeHost) -or $safeHost -eq 'unknown') {
    $safeHost = ($Target -replace '[^A-Za-z0-9._-]', '-')
}
$recordName = "$date-$safeHost-$($Profile.ToLower())-release.md"
$recordPath = Join-Path $OutputDirectory $recordName

$template = Get-Content -Raw -Path $TemplatePath
$profileSummary = "model='$targetModel'; os='$targetOsPretty'; arch='$targetArch'"

$replacements = [ordered]@{
    '{{CHANGE_REFERENCE}}' = $ChangeReference
    '{{DATE}}' = $date
    '{{CREATED_AT}}' = $createdAt
    '{{CREATED_TIME}}' = $createdTime
    '{{ENGINEER}}' = $engineer
    '{{SITE}}' = $(if ([string]::IsNullOrWhiteSpace($Site)) { '_fill in_' } else { $Site })
    '{{PROFILE}}' = $Profile
    '{{GIT_COMMIT}}' = $gitCommit
    '{{GIT_BRANCH}}' = $gitBranch
    '{{RECORD_FILE}}' = $recordPath
    '{{ACTIVE_TARGET}}' = $Active
    '{{ACTIVE_HOSTNAME}}' = $activeHostname
    '{{ACTIVE_OS}}' = $activeOsPretty
    '{{TARGET}}' = $Target
    '{{TARGET_HOSTNAME}}' = $targetHostname
    '{{TARGET_MODEL}}' = $targetModel
    '{{TARGET_ARCH}}' = $targetArch
    '{{TARGET_OS}}' = $targetOsPretty
    '{{TARGET_OS_ID}}' = $targetOsId
    '{{TARGET_OS_VERSION}}' = $targetOsVersion
    '{{INTERFACE}}' = $Interface
    '{{TARGET_MAC}}' = $targetMac
    '{{SD_DEVICE}}' = $SdDevice
    '{{SD_CAPACITY}}' = $sdCapacity
    '{{ROUTER}}' = $Router
    '{{EXPECTED_PROFILE_DESCRIPTION}}' = $expectedDescription
    '{{PROFILE_HARDWARE_RESULT}}' = $hardwareResult
    '{{PROFILE_OS_RESULT}}' = $osResult
    '{{PROFILE_ARCH_RESULT}}' = $archResult
    '{{PROFILE_OVERALL_RESULT}}' = $overallResult
    '{{PROFILE_SUMMARY}}' = $profileSummary
    '{{GATE_MINUS1_INITIAL}}' = 'PASS'
    '{{DEBIAN_IMAGE}}' = $debianImageDisplay
    '{{DEBIAN_IMAGE_SHA512}}' = $debianSha
}

foreach ($key in $replacements.Keys) {
    $template = $template.Replace($key, [string]$replacements[$key])
}

Set-Content -Path $recordPath -Value $template -Encoding utf8

Write-Host "`n===== RESULT ====="
Write-Host "release_record=$recordPath"
Write-Host "profile_hardware=$hardwareResult"
Write-Host "profile_os=$osResult"
Write-Host "profile_arch=$archResult"
Write-Host "profile_gate=$overallResult"

if (-not $overallPass) {
    Write-Host 'RELEASE_RECORD_CREATED=YES'
    Write-Host 'RELEASE_PROFILE_GATE=NO-GO'
    Write-Host 'The record was created for evidence, but the migration must not proceed.'
    exit 2
}

Write-Host 'RELEASE_RECORD_CREATED=YES'
Write-Host 'RELEASE_PROFILE_GATE=PASS'
Write-Host 'Open the generated Markdown file and keep it updated electronically during the release.'
