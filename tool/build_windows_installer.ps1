# Build the release app and the per-user Windows installer on a Windows machine.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$pubspec = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root 'pubspec.yaml')
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw 'Khong doc duoc version trong pubspec.yaml.'
}
$version = $Matches[1]
$build = $Matches[2]
$versionFile = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root 'lib\core\app_version.dart')
if ($versionFile -notmatch "static const name = '$version'" -or $versionFile -notmatch "static const build = $build;") {
  throw 'lib/core/app_version.dart khong khop pubspec.yaml.'
}

flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'flutter build windows that bai.' }

$candidates = @(
  "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
  "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
)
$iscc = $candidates | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) {
  throw 'Chua cai Inno Setup 6. Tai ban cai tai https://jrsoftware.org/isdl.php'
}

& $iscc "/DAppVersion=$version" (Join-Path $root 'installer\windows\QuanLyCuaHang.iss')
if ($LASTEXITCODE -ne 0) { throw 'Dong goi trinh cai that bai.' }

$setup = Join-Path $root "build\installer\QuanLyCuaHang-Setup-$version.exe"
if (-not (Test-Path $setup)) { throw "Khong thay $setup" }
$hash = (Get-FileHash -Algorithm SHA256 -Path $setup).Hash.ToLower()
$manifest = [ordered]@{
  version = $version
  build = [int]$build
  notes = "Ban $version"
  url = ''
  sha256 = $hash
} | ConvertTo-Json
$manifestPath = Join-Path $root 'build\installer\latest.json'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
Write-Output "Installer: $setup"
Write-Output "Feed: $manifestPath"
Write-Output 'Dien url trong latest.json bang dia chi tai file cai, roi dua latest.json len may chu cap nhat.'
