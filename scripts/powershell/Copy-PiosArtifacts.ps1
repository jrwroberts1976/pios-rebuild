[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string]$RemotePath = '/var/tmp/pios-rebuild',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [int]$SshPort = 22
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command scp.exe -ErrorAction SilentlyContinue)) {
    throw 'scp.exe is required'
}

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$destination = Join-Path $OutputDirectory "remote-artifacts-$stamp"
New-Item -ItemType Directory -Path $destination -Force | Out-Null

Write-Host '===== COPY PIOS ARTIFACTS ====='
Write-Host "target=$Target"
Write-Host "remote_path=$RemotePath"
Write-Host "destination=$destination"

& scp.exe -P $SshPort -r "${Target}:$RemotePath/." $destination
if ($LASTEXITCODE -ne 0) {
    throw "Artifact copy failed with exit code $LASTEXITCODE"
}

$manifest = Join-Path $destination 'LOCAL-SHA256SUMS.txt'
Get-ChildItem -Path $destination -Recurse -File |
    Where-Object { $_.FullName -ne $manifest } |
    ForEach-Object {
        $hash = Get-FileHash -Algorithm SHA256 -Path $_.FullName
        $relative = [System.IO.Path]::GetRelativePath($destination, $_.FullName)
        "$($hash.Hash.ToLower())  $relative"
    } | Set-Content -Encoding utf8 $manifest

Write-Host "manifest=$manifest"
Write-Host 'ARTIFACT_COPY=PASS'
Write-Host 'Treat this directory as sensitive; FreeSWITCH exports may contain credentials and TLS material.'
