[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [Parameter(Mandatory = $true)]
    [ValidateSet(
        '01-preflight.sh',
        '02-backup-inventory.sh',
        '02a-export-freeswitch-config.sh',
        '03-rescue-readiness.sh',
        '04-load-rescue.sh',
        '05-enter-rescue.sh',
        '07-validate-debian.sh',
        '07a-restore-freeswitch-config.sh',
        '08-freeswitch-smoke-test.sh'
    )]
    [string]$RemoteScript,

    [Parameter(Mandatory = $true)]
    [string]$SiteConfig,

    [string[]]$RemoteArgs = @(),

    [int]$SshPort = 22,

    [string]$RemoteRoot = '/var/tmp/pios-rebuild-toolkit'
)

$ErrorActionPreference = 'Stop'

function Quote-Bash([string]$Value) {
    return "'" + ($Value -replace "'", "'\"'\"'") + "'"
}

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoRoot = (Resolve-Path (Join-Path $scriptDir '..\..')).Path
$localScripts = Join-Path $repoRoot 'scripts'
$localConfig = (Resolve-Path $SiteConfig).Path

if (-not (Test-Path (Join-Path $localScripts $RemoteScript))) {
    throw "Remote script does not exist in repository: $RemoteScript"
}

foreach ($cmd in @('ssh.exe','scp.exe')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is required"
    }
}

Write-Host '===== STAGE TOOLKIT ON REMOTE PI ====='
Write-Host "target=$Target"
Write-Host "script=$RemoteScript"
Write-Host "ssh_port=$SshPort"

& ssh.exe -p $SshPort $Target "mkdir -p $(Quote-Bash $RemoteRoot) && chmod 700 $(Quote-Bash $RemoteRoot)"
if ($LASTEXITCODE -ne 0) { throw 'Unable to create remote staging directory.' }

& scp.exe -P $SshPort -r $localScripts "${Target}:$RemoteRoot/"
if ($LASTEXITCODE -ne 0) { throw 'Unable to copy scripts to remote Pi.' }

& scp.exe -P $SshPort $localConfig "${Target}:$RemoteRoot/site.env"
if ($LASTEXITCODE -ne 0) { throw 'Unable to copy site configuration to remote Pi.' }

& ssh.exe -p $SshPort $Target "chmod 600 $(Quote-Bash "$RemoteRoot/site.env")"
if ($LASTEXITCODE -ne 0) { throw 'Unable to secure remote site configuration.' }

$argText = ($RemoteArgs | ForEach-Object { Quote-Bash $_ }) -join ' '
$remoteCommand = "sudo env PIOS_CONFIG=$(Quote-Bash "$RemoteRoot/site.env") bash $(Quote-Bash "$RemoteRoot/scripts/$RemoteScript")"
if (-not [string]::IsNullOrWhiteSpace($argText)) {
    $remoteCommand += " $argText"
}

Write-Host "`n===== RUN REMOTE STAGE ====="
Write-Host "remote_script=$RemoteRoot/scripts/$RemoteScript"

& ssh.exe -tt -p $SshPort $Target $remoteCommand
$rc = $LASTEXITCODE

# For ordinary stages, remove the staged config after execution. If kexec has
# replaced userspace the SSH session may disappear before cleanup; this is
# expected and the old filesystem remains the source of that temporary file.
if ($RemoteScript -ne '05-enter-rescue.sh') {
    & ssh.exe -p $SshPort $Target "rm -f $(Quote-Bash "$RemoteRoot/site.env")" 2>$null | Out-Null
}

if ($rc -ne 0) {
    throw "Remote stage failed with exit code $rc"
}

Write-Host 'REMOTE_STAGE=PASS'
