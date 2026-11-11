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

python -m pip install -r (Join-Path $root 'database_helper\requirements-build.txt') -r (Join-Path $root 'database_helper\requirements-test.txt')
if ($LASTEXITCODE -ne 0) { throw 'Cai thu vien cong cu du lieu that bai.' }
python -m unittest discover -s (Join-Path $root 'database_helper\tests') -v
if ($LASTEXITCODE -ne 0) { throw 'Kiem tra cong cu du lieu that bai.' }
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

# Exercise a Vietnamese SQL error too: importing the driver alone does not
# detect crashes while writing non-ASCII text to a redirected Windows pipe.
python (Join-Path $root 'tool\check_database_helper.py') $helper
if ($LASTEXITCODE -ne 0) { throw 'Kiem tra phan hoi loi SQL that bai.' }

Add-Type -AssemblyName System.IO.Compression.FileSystem
$zip = Join-Path $root 'assets\database_helper\xemay_database_helper_windows.zip'
if (Test-Path $zip) { Remove-Item $zip }
[System.IO.Compression.ZipFile]::CreateFromDirectory($helperDir, $zip)

# Exercise the same archive layout that the installed Flutter app extracts.
python (Join-Path $root 'tool\check_database_helper.py') --zip $zip
if ($LASTEXITCODE -ne 0) { throw 'Kiem tra bo cong cu sau giai nen that bai.' }

flutter test test/database_settings_test.dart test/cloud_settings_test.dart test/cloud_sync_reminder_test.dart test/app_update_test.dart
if ($LASTEXITCODE -ne 0) { throw 'Kiem tra cai dat, cloud hoac cap nhat ung dung that bai.' }

# Package only Windows assets, and restore the source manifest afterwards.
$windowsPubspec = [regex]::Replace($pubspec, '(?m)^    - assets/database_helper/xemay_database_helper(?:_windows\.zip)?\r?\n', '')
$windowsPubspec = $windowsPubspec.Replace('  assets:', "  assets:`r`n    - assets/database_helper/xemay_database_helper_windows.zip")
try {
  [System.IO.File]::WriteAllText($pubspecPath, $windowsPubspec, [System.Text.UTF8Encoding]::new($false))
  flutter config --enable-windows-desktop
  flutter build windows --release
  if ($LASTEXITCODE -ne 0) { throw 'flutter build windows that bai.' }
} finally {
  [System.IO.File]::WriteAllText($pubspecPath, $pubspec, [System.Text.UTF8Encoding]::new($false))
}

$release = Join-Path $root 'build\windows\x64\runner\Release'
foreach ($dll in @('msvcp140.dll', 'vcruntime140.dll', 'vcruntime140_1.dll')) {
  if (-not (Test-Path (Join-Path $release $dll))) { throw "Bo cai thieu thu vien $dll" }
}
$bundledZip = Join-Path $release 'data\flutter_assets\assets\database_helper\xemay_database_helper_windows.zip'
if (-not (Test-Path $bundledZip)) { throw 'Ung dung thieu asset cong cu Windows.' }
if ((Get-FileHash -Algorithm SHA256 $bundledZip).Hash -ne (Get-FileHash -Algorithm SHA256 $zip).Hash) {
  throw 'Ung dung dang dong goi sai phien ban cong cu Windows.'
}

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
$tag = "v$version-build.$build"
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
