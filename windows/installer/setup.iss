; Adeghe Professional Services - Windows installer
; Requires Inno Setup 6 (https://jrsoftware.org/isinfo.php)
; Compile: ISCC.exe windows\installer\setup.iss
;   from the repo root, OR open this file in Inno Setup Studio and press Build.
; The Flutter release build must exist first:  flutter build windows --release

#define MyAppName "Adeghe Professional Services"
#define MyAppVersion "1.0.0"
#define MyAppPublisher "AIGHEWI EGHOSA"
#define MyAppExeName "loantrack.exe"
#define MyAppId "6C2E9A1F-4B7D-4E39-8A5C-0D1E2F3A4B5C"

[Setup]
AppId={#MyAppId}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
DefaultDirName={localappdata}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=..\..\build\installer
OutputBaseFilename=AdegheProfessionalServices-Setup-{#MyAppVersion}
SetupIconFile=..\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
PrivilegesRequired=lowest
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "..\..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"
Name: "{autodesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,{#StringChange(MyAppName, '&', '&&')}}"; Flags: nowait postinstall skipifsilent
