# Release-day node configuration guidance

This page is part of the release-day procedure. At Release Gate 0, the checked-in profile under `config/` is a template only. The production copy must be created outside the Git repository.

For Pi 4 / CentOS 9:

```powershell
$SecurePath = 'C:\pios-rebuild-secure'
New-Item -ItemType Directory -Path $SecurePath -Force | Out-Null

Copy-Item '.\config\site-pi4-centos9.env.example' "$SecurePath\passive-site.env"
Copy-Item '.\config\site-pi4-centos9.env.example' "$SecurePath\active-site.env"
```

Expected layout:

```text
C:\Users\<engineer>\pios-rebuild\
└── config\
    └── site-pi4-centos9.env.example   <-- generic template only

C:\pios-rebuild-secure\
├── passive-site.env                   <-- real passive-node values; never commit
└── active-site.env                    <-- real active-node values; never commit
```

Populate the protected copies with the real values for each node. Use the exact variable names from the checked-in template. Values can include the migration profile, expected Pi model and architecture, CentOS version, hostname/IP information, network interface, confirmed whole SD-card device, approved rescue paths/port and Debian image checksum.

The populated configuration can contain infrastructure details or secrets such as real IP addresses, hostnames, SIP/gateway credentials, TLS/private-key paths, API tokens or other production-specific values. It must never be added, committed or pushed to Git. Removing a value later does not remove it from Git history.

Where practical, keep the directory on encrypted local storage and restrict its permissions:

```powershell
icacls $SecurePath /inheritance:r
icacls $SecurePath /grant:r "$env:USERNAME:(OI)(CI)F"
icacls $SecurePath
```

Before the release continues:

```powershell
$RepoPath = (Resolve-Path '.').Path
$PassiveConfig = 'C:\pios-rebuild-secure\passive-site.env'
$ActiveConfig  = 'C:\pios-rebuild-secure\active-site.env'

Write-Host "Repository:     $RepoPath"
Write-Host "Passive config: $PassiveConfig"
Write-Host "Active config:  $ActiveConfig"

git status --short
```

`git status --short` must not show either populated `.env` file.

Use the protected copy by its full path when running release scripts:

```powershell
$Config = 'C:\pios-rebuild-secure\passive-site.env'

pwsh .\scripts\powershell\Invoke-PiosRemoteStage.ps1 `
  -Target <user@passive-pi-ip> `
  -RemoteScript 01-preflight.sh `
  -SiteConfig $Config
```

**NO-GO:** if a populated production configuration has been created inside the repository, appears in `git status`, or has already been committed or pushed, stop the release and treat it as a potential credentials/information exposure before continuing.
