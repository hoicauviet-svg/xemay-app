; Inno Setup 6 script. Version is passed by tool/build_windows_installer.ps1.
#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Quan Ly Cua Hang"
#define AppExeName "xemay_app.exe"
#define AppPublisher "vn.cuahang"

[Setup]
AppId={{7C4E9A21-5B18-4F63-9D0E-2A6C8B4F1E77}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
DefaultDirName={localappdata}\Quan Ly Cua Hang
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
OutputDir=..\..\build\installer
OutputBaseFilename=QuanLyCuaHang-Setup-{#AppVersion}
SetupIconFile=..\..\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=lowest
CloseApplications=yes
RestartApplications=no
UsePreviousAppDir=yes

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExeName}"

[Run]
Filename: "{app}\{#AppExeName}"; Description: "Mo Quan Ly Cua Hang"; Flags: nowait postinstall
