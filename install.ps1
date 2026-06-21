# meta-skill installer (Windows PowerShell)
# Usage: powershell -ExecutionPolicy Bypass -File install.ps1 [-GithubUrl <url>]

param(
    [string]$GithubUrl = "https://github.com/user/meta-skill",
    [string]$Version = "1.0.0",
    [switch]$All = $false,
    [string]$Ide = ""
)

$ErrorActionPreference = "Stop"

$MetaHome = Join-Path $env:USERPROFILE ".meta-skill"
$SkillsDir = Join-Path $MetaHome "skills"
$BinDir = Join-Path $MetaHome "bin"
$TemplateDir = Join-Path $PSScriptRoot "templates"

function Write-Info { Write-Host "[meta-skill installer] $args" }
function Write-Warn { Write-Host "[meta-skill installer] WARN: $args" -ForegroundColor Yellow }

Write-Info "=== meta-skill installer v$Version ==="
Write-Info "Install destination: $MetaHome"

# ---- preflight ----

$missingDeps = @()
foreach ($cmd in @("git", "bash")) {
    if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
        $missingDeps += $cmd
    }
}

if ($missingDeps.Count -gt 0) {
    Write-Warn "Missing dependencies: $($missingDeps -join ', ')"
    Write-Host ""
    Write-Host "Install them with:"
    Write-Host "  Git:  winget install Git.Git"
    Write-Host "  Bash: winget install Git.Git  (includes bash)"
    exit 1
}

Write-Info "All dependencies satisfied."

# ---- create directory structure ----

Write-Info "Creating directory structure..."

New-Item -ItemType Directory -Force -Path $SkillsDir | Out-Null
New-Item -ItemType Directory -Force -Path $BinDir | Out-Null
New-Item -ItemType Directory -Force -Path (Join-Path $MetaHome "backups") | Out-Null

# ---- install metadata.json ----

$ts = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = @{
    name = "meta-skill"
    version = $Version
    description = "Universal skill manager for AI coding agents"
    github = $GithubUrl
    created_at = $ts
    updated_at = $ts
}

if (Test-Path (Join-Path $TemplateDir "metadata.json")) {
    $template = Get-Content (Join-Path $TemplateDir "metadata.json") -Raw | ConvertFrom-Json
    $template.version = $Version
    $template.github = $GithubUrl
    $template.created_at = $ts
    $template.updated_at = $ts
    $template | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MetaHome "metadata.json")
} else {
    $metadata | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MetaHome "metadata.json")
}
Write-Info "metadata.json created"

# ---- install registry.json ----

if (Test-Path (Join-Path $TemplateDir "registry.json")) {
    Copy-Item (Join-Path $TemplateDir "registry.json") (Join-Path $MetaHome "registry.json")
    Write-Info "registry.json created"
} else {
    Write-Warn "registry.json template not found, creating minimal registry..."
    @{
        version = "1.0.0"
        agents = @{}
        sources = @{}
    } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MetaHome "registry.json")
}

# ---- install manifest.json ----

if (-not (Test-Path (Join-Path $MetaHome "manifest.json"))) {
    @{
        skills = @{}
        projects = @{}
    } | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $MetaHome "manifest.json")
    Write-Info "manifest.json created"
}

# ---- install meta-skill CLI ----

Copy-Item (Join-Path $PSScriptRoot "meta-skill.sh") (Join-Path $BinDir "meta-skill")
Write-Info "CLI installed: $BinDir\meta-skill"

# Create a .bat wrapper for Windows
@"
@echo off
bash "%~dp0..\bin\meta-skill" %*
"@ | Set-Content (Join-Path $MetaHome "meta-skill.cmd")
Write-Info "Windows CMD wrapper created: $MetaHome\meta-skill.cmd"

# ---- install operation scripts ----

$ScriptsDest = Join-Path $MetaHome "scripts"
New-Item -ItemType Directory -Force -Path $ScriptsDest | Out-Null
$sourceScriptsDir = Join-Path $PSScriptRoot "scripts"
if (Test-Path $sourceScriptsDir) {
    Get-ChildItem "$sourceScriptsDir\*.sh" | ForEach-Object {
        Copy-Item $_.FullName (Join-Path $ScriptsDest $_.Name)
        Write-Info "Script installed: $($_.Name)"
    }
}

# ---- install sub-skills ----

$subSkillsDir = Join-Path $PSScriptRoot "skills"
if (Test-Path $subSkillsDir) {
    Get-ChildItem "$subSkillsDir" -Directory | ForEach-Object {
        $skillMd = Join-Path $_.FullName "SKILL.md"
        if (Test-Path $skillMd) {
            $skillName = $_.Name
            $destDir = Join-Path $SkillsDir $skillName
            New-Item -ItemType Directory -Force -Path $destDir | Out-Null
            Copy-Item $skillMd (Join-Path $destDir "SKILL.md")
            Write-Info "Sub-skill installed: $skillName"
        }
    }
}

<# :: Register meta-skill in manifest :: #>
$registryPath = Join-Path $MetaHome "registry.json"
$registry = Get-Content $registryPath -Raw | ConvertFrom-Json

# Collect all agent keys
$allAgentKeys = $registry.agents.PSObject.Properties | ForEach-Object { $_.Name }

$manifestPath = Join-Path $MetaHome "manifest.json"
$manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json

$manifest.skills | Add-Member -Name "meta-skill" -Value @{
    source = @{
        type = "github"
        url = $GithubUrl
        version = $Version
    }
    installed_at = $ts
    updated_at = $ts
    agents = $allAgentKeys
    projects = @{}
} -MemberType NoteProperty -Force

$manifest | ConvertTo-Json -Depth 10 | Set-Content $manifestPath
Write-Info "meta-skill registered in manifest"

# ---- link meta-skill to AI agents ----
Write-Info "Linking meta-skill to AI agents..."

# Determine which agents to link to
# Default: only agents whose home directory exists on disk
# -All:    all agents in manifest
# -Ide:    comma-separated list of specific agents

$ideList = @()
if ($Ide) {
    $ideList = $Ide -split ',' | ForEach-Object { $_.Trim() }
}

$linked = 0
$skipped = 0

foreach ($agentKey in $allAgentKeys) {
    $homeDir = $registry.agents.$agentKey.home
    $skillDir = $registry.agents.$agentKey.skill_dir

    if (-not $skillDir) { continue }

    # Filter logic
    $shouldLink = $false
    if ($All) {
        $shouldLink = $true
    } elseif ($ideList.Count -gt 0) {
        $shouldLink = $ideList -contains $agentKey
    } else {
        # Default: only if home directory exists
        $homeDirExpanded = $homeDir -replace '^~', $env:USERPROFILE
        $shouldLink = Test-Path $homeDirExpanded
    }

    if (-not $shouldLink) {
        Write-Info "  Skipping $agentKey (not installed, use -All or -Ide to force)"
        $skipped++
        continue
    }

    # Create symlink
    $skillDirExpanded = $skillDir -replace '^~', $env:USERPROFILE
    New-Item -ItemType Directory -Force -Path $skillDirExpanded | Out-Null
    $linkPath = Join-Path $skillDirExpanded "meta-skill"
    if (-not (Test-Path $linkPath)) {
        New-Item -ItemType SymbolicLink -Path $linkPath -Target (Join-Path $SkillsDir "meta-skill") | Out-Null
        Write-Info "  Linked to $agentKey ($skillDirExpanded)"
    } else {
        Write-Info "  Already linked: $agentKey"
    }
    $linked++
}

Write-Info "Linked: $linked, Skipped: $skipped"

# ---- PATH configuration ----

# Add to user PATH if not already present
$currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
if ($currentPath -notlike "*$MetaHome*") {
    [Environment]::SetEnvironmentVariable("PATH", "$MetaHome;$currentPath", "User")
    $env:PATH = "$MetaHome;$env:PATH"
    Write-Info "Added $MetaHome to user PATH"
} else {
    Write-Info "$MetaHome already in PATH"
}

# ---- summary ----

Write-Host ""
Write-Info "========================================="
Write-Info " meta-skill installed successfully!"
Write-Info "========================================="
Write-Host ""
Write-Host "  Location: $MetaHome"
Write-Host "  CLI:      meta-skill"
Write-Host ""
Write-Host "  Quick start:"
Write-Host "    meta-skill list"
Write-Host "    meta-skill install <name> --source <url> --agent trae"
Write-Host ""
Write-Host "  Open a new PowerShell window for PATH changes to take effect."
Write-Host ""
