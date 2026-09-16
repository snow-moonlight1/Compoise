<#
.SYNOPSIS
    MatrixFlow AI - Release Build and Packaging Automation Script
.DESCRIPTION
    Builds Flutter Android Release APK and Windows Release Desktop bundle,
    extracts version from pubspec.yaml, packages portable ZIP, and generates SHA256SUMS.txt.
.PARAMETER Platform
    Build platform: 'All', 'Android', 'Windows' (default: 'All')
.PARAMETER OutputDir
    Output directory for release artifacts (default: <root>/release_dist)
.PARAMETER FlutterSdk
    Flutter SDK directory (default: 'D:\Dev_SDKs\Flutter_SDK')
#>

[CmdletBinding()]
param (
    [ValidateSet('All', 'Android', 'Windows')]
    [string]$Platform = 'All',

    [string]$OutputDir = '',

    [string]$FlutterSdk = 'D:\Dev_SDKs\Flutter_SDK'
)

$ErrorActionPreference = 'Stop'

# 1. Resolve paths
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Split-Path -Parent $ScriptDir
$NativeDir = Join-Path $ProjectRoot 'matrixflow-native'

if (-not (Test-Path $NativeDir)) {
    Write-Error "Cannot find matrixflow-native directory: $NativeDir"
}

if ([string]::IsNullOrWhiteSpace($OutputDir)) {
    $OutputDir = Join-Path $ProjectRoot 'release_dist'
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# 2. Locate Flutter executable
$FlutterBin = Join-Path $FlutterSdk 'bin\flutter.bat'
if (-not (Test-Path $FlutterBin)) {
    $FlutterCmd = Get-Command 'flutter' -ErrorAction SilentlyContinue
    if ($FlutterCmd) {
        $FlutterBin = $FlutterCmd.Source
    } else {
        Write-Error 'Flutter SDK not found. Please specify -FlutterSdk or add to PATH.'
    }
}

Write-Host '=================================================' -ForegroundColor Cyan
Write-Host ' MatrixFlow AI Release Build and Packaging' -ForegroundColor Cyan
Write-Host '=================================================' -ForegroundColor Cyan
Write-Host "Flutter Engine: $FlutterBin"
Write-Host "Source Dir:     $NativeDir"
Write-Host "Output Dir:     $OutputDir"
Write-Host "Target:         $Platform"

# 3. Parse Version from pubspec.yaml
$PubspecPath = Join-Path $NativeDir 'pubspec.yaml'
$AppVersion = '1.0.0'
$BuildNumber = '1'

foreach ($line in (Get-Content $PubspecPath)) {
    if ($line -match '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)(?:\+([0-9]+))?') {
        $AppVersion = $Matches[1]
        if ($Matches[2]) {
            $BuildNumber = $Matches[2]
        }
        break
    }
}

Write-Host "App Version:    v$AppVersion (Build $BuildNumber)"
Write-Host '-------------------------------------------------'

$GeneratedArtifacts = @()

# 4. Build Android Release APK
if ($Platform -eq 'All' -or $Platform -eq 'Android') {
    Write-Host "`n[1/2] Building Android Release APK..." -ForegroundColor Yellow
    Push-Location $NativeDir
    try {
        & $FlutterBin build apk --release --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "Android build failed with exit code: $LASTEXITCODE"
        }

        $ApkSource = Join-Path $NativeDir 'build\app\outputs\flutter-apk\app-release.apk'
        if (-not (Test-Path $ApkSource)) {
            throw "Built APK not found at: $ApkSource"
        }

        $TargetApkName = "matrixflow-v$AppVersion-android.apk"
        $TargetApkPath = Join-Path $OutputDir $TargetApkName
        Copy-Item -Path $ApkSource -Destination $TargetApkPath -Force

        $ApkItem = Get-Item $TargetApkPath
        $ApkSizeMB = [math]::Round($ApkItem.Length / 1MB, 2)
        Write-Host "[OK] Android APK created: $TargetApkName ($ApkSizeMB MB)" -ForegroundColor Green
        $GeneratedArtifacts += $TargetApkPath
    }
    finally {
        Pop-Location
    }
}

# 5. Build Windows Release and create Portable ZIP
if ($Platform -eq 'All' -or $Platform -eq 'Windows') {
    Write-Host "`n[2/2] Building Windows Release Desktop Application..." -ForegroundColor Yellow
    Push-Location $NativeDir
    try {
        & $FlutterBin build windows --release --no-pub
        if ($LASTEXITCODE -ne 0) {
            throw "Windows build failed with exit code: $LASTEXITCODE"
        }

        $WindowsReleaseDir = Join-Path $NativeDir 'build\windows\x64\runner\Release'
        if (-not (Test-Path $WindowsReleaseDir)) {
            throw "Windows Release output dir not found: $WindowsReleaseDir"
        }

        $TargetZipName = "matrixflow-v$AppVersion-windows-portable.zip"
        $TargetZipPath = Join-Path $OutputDir $TargetZipName
        if (Test-Path $TargetZipPath) {
            Remove-Item $TargetZipPath -Force
        }

        Write-Host "Creating Windows Portable ZIP archive..." -ForegroundColor Gray
        Compress-Archive -Path "$WindowsReleaseDir\*" -DestinationPath $TargetZipPath -CompressionLevel Optimal

        $ZipItem = Get-Item $TargetZipPath
        $ZipSizeMB = [math]::Round($ZipItem.Length / 1MB, 2)
        Write-Host "[OK] Windows Portable ZIP created: $TargetZipName ($ZipSizeMB MB)" -ForegroundColor Green
        $GeneratedArtifacts += $TargetZipPath
    }
    finally {
        Pop-Location
    }
}

# 6. Generate SHA256 Checksums
Write-Host "`nGenerating SHA256 checksums..." -ForegroundColor Cyan
$ChecksumFilePath = Join-Path $OutputDir 'SHA256SUMS.txt'
$ChecksumLines = @()

foreach ($Artifact in $GeneratedArtifacts) {
    $FileName = Split-Path -Leaf $Artifact
    $FileHash = (Get-FileHash -Path $Artifact -Algorithm SHA256).Hash.ToLower()
    $ChecksumLines += "$FileHash  $FileName"
    Write-Host "  $FileName : $FileHash" -ForegroundColor Gray
}

$ChecksumLines | Out-File -FilePath $ChecksumFilePath -Encoding ASCII -Force
Write-Host "[OK] Checksums written to: SHA256SUMS.txt" -ForegroundColor Green

Write-Host "`n=================================================" -ForegroundColor Green
Write-Host " MatrixFlow AI Packaging Completed Successfully!" -ForegroundColor Green
Write-Host "=================================================" -ForegroundColor Green
Get-ChildItem $OutputDir | Select-Object Name, Length, LastWriteTime | Format-Table -AutoSize
