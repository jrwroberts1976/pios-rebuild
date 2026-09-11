[CmdletBinding()]
param(
    [string]$RepoUrl = 'https://github.com/jrwroberts1976/pios-rebuild.git',
    [string]$RepoPath = (Join-Path $HOME 'pios-rebuild'),
    [string]$Branch = 'main'
)

$ErrorActionPreference = 'Stop'

function Pass([string]$Message) { Write-Host "PASS: $Message" }
function Fail([string]$Message) { throw $Message }

Write-Host '===== PIOS REBUILD ENVIRONMENT SETUP ====='
Write-Host "repo_url=$RepoUrl"
Write-Host "repo_path=$RepoPath"
Write-Host "branch=$Branch"

foreach ($cmd in @('git.exe','ssh.exe','scp.exe')) {
    if (Get-Command $cmd -ErrorAction SilentlyContinue) {
        Pass "$cmd available"
    }
    else {
        Fail "$cmd is required before continuing"
    }
}

if (-not (Test-Path $RepoPath)) {
    Write-Host "`n===== CLONE REPOSITORY ====="
    & git.exe clone $RepoUrl $RepoPath
    if ($LASTEXITCODE -ne 0) {
        Fail "git clone failed with exit code $LASTEXITCODE"
    }
}
else {
    Pass 'repository directory already exists'
}

Set-Location $RepoPath

if (-not (Test-Path '.git')) {
    Fail "$RepoPath exists but is not a Git repository"
}

Write-Host "`n===== VERIFY REMOTE ====="
$origin = (& git.exe remote get-url origin 2>$null).Trim()
Write-Host "origin=$origin"
if ([string]::IsNullOrWhiteSpace($origin)) {
    Fail 'origin remote is not configured'
}

Write-Host "`n===== WORKING TREE CHECK ====="
$status = & git.exe status --porcelain
if (-not [string]::IsNullOrWhiteSpace(($status -join "`n"))) {
    $status | ForEach-Object { Write-Host $_ }
    Fail 'working tree contains local changes; commit, stash or discard them before updating the release checkout'
}
Pass 'working tree clean'

Write-Host "`n===== UPDATE REPOSITORY ====="
& git.exe fetch origin --prune
if ($LASTEXITCODE -ne 0) {
    Fail "git fetch failed with exit code $LASTEXITCODE"
}

& git.exe checkout $Branch
if ($LASTEXITCODE -ne 0) {
    Fail "git checkout $Branch failed with exit code $LASTEXITCODE"
}

& git.exe pull --ff-only origin $Branch
if ($LASTEXITCODE -ne 0) {
    Fail "git pull --ff-only origin $Branch failed with exit code $LASTEXITCODE"
}

Write-Host "`n===== PIN RELEASE VERSION ====="
$commit = (& git.exe rev-parse HEAD).Trim()
$short = (& git.exe rev-parse --short HEAD).Trim()
$log = (& git.exe log -1 --pretty=format:'%h %ad %s' --date=iso-strict).Trim()
Write-Host "commit=$commit"
Write-Host "release_commit=$short"
Write-Host "latest=$log"

$statusAfter = & git.exe status --porcelain
if (-not [string]::IsNullOrWhiteSpace(($statusAfter -join "`n"))) {
    Fail 'working tree became dirty unexpectedly during setup'
}

Write-Host "`n===== RESULT ====="
Write-Host 'ENVIRONMENT_SETUP=PASS'
Write-Host "Use this exact commit for the release: $commit"
Write-Host 'Do not run git pull again after the migration/change window has started.'
