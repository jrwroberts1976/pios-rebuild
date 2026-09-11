[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [int]$Port = 2222,

    [string]$User = 'root'
)

$ErrorActionPreference = 'Stop'

if (-not (Get-Command ssh.exe -ErrorAction SilentlyContinue)) {
    throw 'ssh.exe is required'
}

Write-Host '===== RAM RESCUE CONNECTION ====='
Write-Host "target=$Target"
Write-Host "port=$Port"
Write-Host "user=$User"
Write-Host 'Opening an interactive rescue SSH session.'

& ssh.exe -p $Port "${User}@${Target}"
exit $LASTEXITCODE
