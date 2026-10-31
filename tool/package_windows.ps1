# Builds VN Pathfinder for Windows and packages it into dist\:
#   VN-Pathfinder-<version>-windows-portable.zip   always
#   VN-Pathfinder-<version>-windows-setup.exe      if Inno Setup 6 is installed
#
# Usage, from anywhere:  powershell -File tool\package_windows.ps1 [-SkipBuild]
param([switch]$SkipBuild)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

$versionLine = Select-String -Path 'lib\services\app_update_service.dart' -Pattern "const appVersion = '([^']+)'"
$version = $versionLine.Matches[0].Groups[1].Value
Write-Host "Packaging VN Pathfinder $version"

if (-not $SkipBuild) {
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build failed' }
}

$release = 'build\windows\x64\runner\Release'
if (-not (Test-Path "$release\vn_pathfinder.exe")) { throw "No build found at $release" }

$dist = Join-Path $repo 'dist'
$app = Join-Path $dist 'app'
if (Test-Path $app) { Remove-Item $app -Recurse -Force }
New-Item -ItemType Directory -Force $app | Out-Null
Copy-Item "$release\*" $app -Recurse

# Flutter apps need the Visual C++ runtime, which not every PC has. These three
# files sit next to the exe so the app runs without a separate install.
foreach ($dll in 'msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll') {
  Copy-Item "$env:WINDIR\System32\$dll" $app
}

$zip = Join-Path $dist "VN-Pathfinder-$version-windows-portable.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Compress-Archive -Path "$app\*" -DestinationPath $zip
Write-Host "Portable: $zip ($([math]::Round((Get-Item $zip).Length / 1MB)) MB)"

$iscc = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1

if ($iscc) {
  & $iscc "/DAppVersion=$version" 'installer\vn_pathfinder.iss'
  if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed' }
  Write-Host "Installer: $dist\VN-Pathfinder-$version-windows-setup.exe"
} else {
  Write-Host 'Inno Setup 6 not found, so the installer was skipped.'
}
