# Build the Windows SQL helper, the release app, and the per-user installer.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $root

$pubspecPath = Join-Path $root 'pubspec.yaml'
$pubspec = Get-Content -Raw -Encoding UTF8 -Path $pubspecPath
if ($pubspec -notmatch '(?m)^version:\s*(\d+\.\d+\.\d+)\+(\d+)\s*$') {
  throw 'Khong doc duoc version trong pubspec.yaml.'
}
$version = $Matches[1]
$build = $Matches[2]
$versionFile = Get-Content -Raw -Encoding UTF8 -Path (Join-Path $root 'lib\core\app_version.dart')
if ($versionFile -notmatch "static const name = '$version'" -or $versionFile -notmatch "static const build = $build;") {
  throw 'lib/core/app_version.dart khong khop pubspec.yaml.'
}

python -m pip install -r (Join-Path $root 'database_helper\requirements-build.txt')
if ($LASTEXITCODE -ne 0) { throw 'Cai thu vien cong cu SQL that bai.' }
python (Join-Path $root 'tool\build_database_helper.py')
if ($LASTEXITCODE -ne 0) { throw 'Dong goi cong cu SQL that bai.' }
$helperDir = Join-Path $root 'build\database_helper\xemay_database_helper_windows'
$helper = Join-Path $helperDir 'xemay_database_helper_windows.exe'
if (-not (Test-Path $helper)) { throw "Khong thay $helper" }

$requestPath = Join-Path $env:TEMP ("xemay-helper-{0}.json" -f [guid]::NewGuid().ToString('n'))
[System.IO.File]::WriteAllText($requestPath, '{"command":"checkSqlDriver"}', [System.Text.UTF8Encoding]::new($false))
$start = New-Object System.Diagnostics.ProcessStartInfo
$start.FileName = $helper
$start.Arguments = '"' + $requestPath + '"'
$start.WorkingDirectory = $helperDir
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$process = [System.Diagnostics.Process]::Start($start)
$outTask = $process.StandardOutput.ReadToEndAsync()
$errTask = $process.StandardError.ReadToEndAsync()
$process.WaitForExit()
$probe = $outTask.Result
$err = $errTask.Result
if (Test-Path $requestPath) { Remove-Item $requestPath -Force }
if ($process.ExitCode -ne 0 -or $probe -notmatch '"available":\s*true') {
  throw "Cong cu SQL khong phan hoi duoc: $probe $err"
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $root 'assets\database_helper\xemay_database_helper_windows.zip'
if (Test-Path $zip) { Remove-Item $zip }
[System.IO.Compression.ZipFile]::CreateFromDirectory($helperDir, $zip)

if ($pubspec -notmatch 'xemay_database_helper_windows\.zip') {
  $pubspec = $pubspec.Replace(
    '    - assets/database_helper/xemay_database_helper',
    "    - assets/database_helper/xemay_database_helper`r`n    - assets/database_helper/xemay_database_helper_windows.zip"
  )
  [System.IO.File]::WriteAllText($pubspecPath, $pubspec, [System.Text.UTF8Encoding]::new($false))
}

flutter config --enable-windows-desktop
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

$setupName = "QuanLyCuaHang-Setup-$version.exe"
$setup = Join-Path $root "build\installer\$setupName"
if (-not (Test-Path $setup)) { throw "Khong thay $setup" }
$hash = (Get-FileHash -Algorithm SHA256 -Path $setup).Hash.ToLower()
$repository = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { 'hoicauviet-svg/xemay-app' }
$tag = "v$version"
$downloadUrl = "https://github.com/$repository/releases/download/$tag/$setupName"
$manifest = [ordered]@{
  version = $version
  build = [int]$build
  notes = "Ban cai Windows $version"
  url = $downloadUrl
  sha256 = $hash
} | ConvertTo-Json
$manifestPath = Join-Path $root 'build\installer\latest.json'
[System.IO.File]::WriteAllText($manifestPath, $manifest, [System.Text.UTF8Encoding]::new($false))
Write-Output "Installer: $setup"
Write-Output "Feed: $manifestPath"
Write-Output "Download: $downloadUrl"
