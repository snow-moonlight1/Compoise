[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$ProjectRoot = Split-Path -Parent $PSScriptRoot
$SourcePath = Join-Path $ProjectRoot 'assets/branding/CompoiseLogo.png'
if (-not (Test-Path -LiteralPath $SourcePath)) {
    throw "Brand source image is missing: $SourcePath"
}

function New-BrandPng([System.Drawing.Image]$Source, [int]$Size) {
    $Bitmap = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
    try {
        $Graphics.Clear([System.Drawing.Color]::White)
        $Graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
        $Graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $Graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
        $Graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
        $Graphics.DrawImage($Source, 0, 0, $Size, $Size)
        $Stream = New-Object System.IO.MemoryStream
        try {
            $Bitmap.Save($Stream, [System.Drawing.Imaging.ImageFormat]::Png)
            return ,$Stream.ToArray()
        } finally {
            $Stream.Dispose()
        }
    } finally {
        $Graphics.Dispose()
        $Bitmap.Dispose()
    }
}

$Source = [System.Drawing.Image]::FromFile($SourcePath)
try {
    $AndroidSizes = @{
        'mipmap-mdpi' = 48
        'mipmap-hdpi' = 72
        'mipmap-xhdpi' = 96
        'mipmap-xxhdpi' = 144
        'mipmap-xxxhdpi' = 192
    }
    foreach ($Directory in $AndroidSizes.Keys) {
        $Destination = Join-Path $ProjectRoot "android/app/src/main/res/$Directory"
        if (-not (Test-Path -LiteralPath $Destination)) {
            New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        }
        $Png = New-BrandPng $Source $AndroidSizes[$Directory]
        [System.IO.File]::WriteAllBytes((Join-Path $Destination 'ic_launcher.png'), $Png)
        [System.IO.File]::WriteAllBytes((Join-Path $Destination 'ic_launcher_round.png'), $Png)
    }

    $IconSizes = @(16, 24, 32, 48, 64, 128, 256)
    $Frames = @(
        foreach ($Size in $IconSizes) {
            New-BrandPng $Source $Size
        }
    )
    $IconStream = New-Object System.IO.MemoryStream
    $Writer = New-Object System.IO.BinaryWriter($IconStream)
    try {
        $Writer.Write([UInt16]0)
        $Writer.Write([UInt16]1)
        $Writer.Write([UInt16]$Frames.Count)
        $Offset = 6 + (16 * $Frames.Count)
        for ($Index = 0; $Index -lt $Frames.Count; $Index++) {
            $Size = $IconSizes[$Index]
            $Writer.Write([byte]$(if ($Size -eq 256) { 0 } else { $Size }))
            $Writer.Write([byte]$(if ($Size -eq 256) { 0 } else { $Size }))
            $Writer.Write([byte]0)
            $Writer.Write([byte]0)
            $Writer.Write([UInt16]1)
            $Writer.Write([UInt16]32)
            $Writer.Write([UInt32]$Frames[$Index].Length)
            $Writer.Write([UInt32]$Offset)
            $Offset += $Frames[$Index].Length
        }
        foreach ($Frame in $Frames) {
            $Writer.Write($Frame)
        }
        $Writer.Flush()
        $Icon = $IconStream.ToArray()
        foreach ($Destination in @(
            (Join-Path $ProjectRoot 'windows/runner/resources/app_icon.ico'),
            (Join-Path $ProjectRoot 'assets/tray_icon.ico')
        )) {
            [System.IO.File]::WriteAllBytes($Destination, $Icon)
        }
    } finally {
        $Writer.Dispose()
        $IconStream.Dispose()
    }
} finally {
    $Source.Dispose()
}

Write-Host 'Generated Android launcher, Windows application, and tray icons from assets/branding/CompoiseLogo.png.'
