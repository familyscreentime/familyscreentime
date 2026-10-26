; Installer of the Windows client, built by the "Windows client" workflow:
;   ISCC.exe /DAppVersion=0.27.0 FamilyScreenTime.iss
; from the release build in apps\family_screen_time\build\windows\x64\runner\Release.
;
; Installed for every account of the PC (administrator rights needed, so a
; child with a standard account can neither install nor remove it). The
; monitor starts at each sign-in, in every account; in accounts not set up
; for a child (a parent's), it stops at once.

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif
#define AppName "Family Screen Time"
#define AppExe "FamilyScreenTime.exe"
#define Build "..\..\apps\family_screen_time\build\windows\x64\runner\Release"

[Setup]
AppId={{DC324F4B-A0BA-43A8-A64E-BF8EC166E9D1}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Family Screen Time
AppPublisherURL=https://familyscreentime.org
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.17763
OutputBaseFilename=FamilyScreenTime-{#AppVersion}-windows-setup
SetupIconFile=..\..\apps\family_screen_time\windows\runner\resources\app_icon.ico
UninstallDisplayIcon={app}\{#AppExe}
LicenseFile=..\..\LICENSE
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=force
RestartApplications=no

[Languages]
Name: "fr"; MessagesFile: "compiler:Languages\French.isl"
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"
Name: "en"; MessagesFile: "compiler:Default.isl"

[CustomMessages]
fr.Launch=Ouvrir Family Screen Time
nl.Launch=Family Screen Time openen
en.Launch=Open Family Screen Time

[Files]
; With the Visual C++ runtime, which the workflow puts next to the app: no
; separate installation.
Source: "{#Build}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{app}\{#AppExe}"

[Registry]
; The monitor, at each sign-in, in every account.
Root: HKLM; Subkey: "Software\Microsoft\Windows\CurrentVersion\Run"; ValueType: string; ValueName: "FamilyScreenTime"; ValueData: """{app}\{#AppExe}"" --monitor"; Flags: uninsdeletevalue

[Run]
; The devices of the family find each other on the local network.
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; StatusMsg: "Firewall"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall add rule name=""{#AppName}"" dir=in action=allow program=""{app}\{#AppExe}"" enable=yes"; Flags: runhidden
Filename: "{app}\{#AppExe}"; Description: "{cm:Launch}"; Flags: nowait postinstall skipifsilent runasoriginaluser

[UninstallRun]
Filename: "{sys}\taskkill.exe"; Parameters: "/F /IM {#AppExe}"; Flags: runhidden; RunOnceId: "StopApp"
Filename: "{sys}\netsh.exe"; Parameters: "advfirewall firewall delete rule name=""{#AppName}"""; Flags: runhidden; RunOnceId: "Firewall"
