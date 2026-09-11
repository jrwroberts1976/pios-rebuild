[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Target,

    [string]$Device = '/dev/mmcblk0',

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [string]$Label = 'pi-before-debian',

    [int]$SshPort = 22
)

$ErrorActionPreference = 'Stop'

foreach ($cmd in @('ssh.exe','cmd.exe')) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        throw "$cmd is required"
    }
}

if (-not (Test-Path $OutputDirectory)) {
    New-Item -ItemType Directory -Path $OutputDirectory -Force | Out-Null
}
$OutputDirectory = (Resolve-Path $OutputDirectory).Path

Write-Host '===== REMOTE SD BACKUP PREFLIGHT ====='
Write-Host "target=$Target"
Write-Host "device=$Device"
Write-Host "output_directory=$OutputDirectory"

$check = & ssh.exe -p $SshPort $Target "sudo sh -c 'test -b $Device && echo type=\$(lsblk -ndo TYPE $Device) && echo size=\$(blockdev --getsize64 $Device) && findmnt -no SOURCE /'" 2>&1
if ($LASTEXITCODE -ne 0) {
    $check | ForEach-Object { Write-Host $_ }
    throw 'Remote block-device preflight failed.'
}
$check | ForEach-Object { Write-Host $_ }

$typeLine = $check | Where-Object { $_ -like 'type=*' } | Select-Object -First 1
if ($typeLine -ne 'type=disk') {
    throw "Refusing backup: $Device is not reported as a whole disk."
}

$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$filename = "$Label-$timestamp.img"
$outFile = Join-Path $OutputDirectory $filename
$hashFile = "$outFile.sha256"

$driveRoot = [System.IO.Path]::GetPathRoot($outFile)
$drive = Get-PSDrive -Name $driveRoot.Substring(0,1)
if ($drive.Free -lt 40GB) {
    throw "Less than 40 GB free on destination drive. Refusing to start a full 32 GB card backup."
}

Write-Host "`n===== FULL RAW SD IMAGE ====="
Write-Host "output=$outFile"
Write-Host 'This is a read-only operation on the Pi, but it may run for tens of minutes.'

# Use cmd.exe redirection deliberately so the SSH byte stream is written directly
# to disk without PowerShell attempting to treat it as text.
$escapedOut = $outFile.Replace('"','\"')
$cmdLine = "ssh.exe -p $SshPort $Target \"sudo dd if=$Device bs=4M status=none\" > \"$escapedOut\""

& cmd.exe /D /S /C $cmdLine
if ($LASTEXITCODE -ne 0) {
    throw "SD image transfer failed with exit code $LASTEXITCODE"
}

$length = (Get-Item $outFile).Length
Write-Host "bytes_written=$length"
if ($length -lt 20GB) {
    throw 'Backup file is unexpectedly small. Do not treat it as a valid rollback image.'
}

Write-Host "`n===== CHECKSUM ====="
$hash = Get-FileHash -Algorithm SHA256 -Path $outFile
"$($hash.Hash.ToLower())  $filename" | Set-Content -Encoding ascii $hashFile
Write-Host "sha256=$($hash.Hash.ToLower())"
Write-Host "checksum_file=$hashFile"

Write-Host "`nFULL_SD_BACKUP=PASS"
Write-Host 'Keep this image available until the Debian node has completed its agreed soak period.'
