# AutoLoop Plugin Installer for Claude Code (Windows)
# Usage: irm https://raw.githubusercontent.com/AdamHoldinPurge/autoloop-plugin/main/install.ps1 | iex
$ErrorActionPreference = "Stop"

$PluginDir = "$env:USERPROFILE\.claude\plugins\autoloop"
$RepoZip = "https://github.com/AdamHoldinPurge/autoloop-plugin/archive/refs/heads/main.zip"
$TmpDir = Join-Path $env:TEMP "autoloop-install-$(Get-Random)"

Write-Host "=== AutoLoop Plugin Installer ===" -ForegroundColor Cyan
Write-Host ""

# Check if already installed
if (Test-Path "$PluginDir\.claude-plugin") {
    $answer = Read-Host "AutoLoop is already installed. Reinstall/update? [y/N]"
    if ($answer -ne "y" -and $answer -ne "Y") {
        Write-Host "Cancelled."
        exit 0
    }
    Write-Host "Updating existing installation..."
}

# Download
Write-Host "Downloading AutoLoop plugin..."
New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null
$zipPath = Join-Path $TmpDir "autoloop.zip"
Invoke-WebRequest -Uri $RepoZip -OutFile $zipPath -UseBasicParsing

# Extract
Write-Host "Installing to $PluginDir..."
Expand-Archive -Path $zipPath -DestinationPath $TmpDir -Force

$Extracted = Join-Path $TmpDir "autoloop-plugin-main"

# Backup accounts.json if it exists
$accountsBackup = $null
$accountsPath = Join-Path $PluginDir "accounts\accounts.json"
if (Test-Path $accountsPath) {
    $accountsBackup = Join-Path $TmpDir "accounts_backup.json"
    Copy-Item $accountsPath $accountsBackup
}

# Create plugin directory
New-Item -ItemType Directory -Path $PluginDir -Force | Out-Null

# Copy files
Copy-Item "$Extracted\.claude-plugin" "$PluginDir\" -Recurse -Force
Copy-Item "$Extracted\scripts" "$PluginDir\" -Recurse -Force
Copy-Item "$Extracted\skills" "$PluginDir\" -Recurse -Force
Get-ChildItem "$Extracted\icon*" -ErrorAction SilentlyContinue | Copy-Item -Destination $PluginDir -Force
if (Test-Path "$Extracted\.gitignore") {
    Copy-Item "$Extracted\.gitignore" "$PluginDir\" -Force
}

# Ensure accounts directory
New-Item -ItemType Directory -Path "$PluginDir\accounts" -Force | Out-Null

# Restore accounts.json
if ($accountsBackup -and (Test-Path $accountsBackup)) {
    Copy-Item $accountsBackup $accountsPath
}

# Fix marketplace.json
$marketplace = @{
    name = "autoloop-local"
    description = "Local marketplace for the autoloop plugin"
    plugins = @(
        @{
            name = "autoloop"
            description = "Self-planning autonomous loop. Claude executes tasks, updates its own plan, and generates next steps - forever."
            version = "1.0.0"
            source = @{
                type = "directory"
                path = $PluginDir
            }
        }
    )
} | ConvertTo-Json -Depth 4

Set-Content -Path "$PluginDir\.claude-plugin\marketplace.json" -Value $marketplace

# Cleanup
Remove-Item -Path $TmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ""
Write-Host "=== AutoLoop installed successfully! ===" -ForegroundColor Green
Write-Host "Location: $PluginDir"
Write-Host ""
Write-Host "Restart Claude Code to activate the plugin."
Write-Host "Then use /start to begin an autonomous session."
