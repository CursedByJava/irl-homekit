; IRL Homekit Setup: a normal Windows setup wizard around install.ps1.
;
; The wizard asks its questions on pages (channels, OBS, overlays, dashboard login, phone connection with the
; optional relay server, remote dashboard), then runs install.ps1 -NonInteractive with those answers and shows its
; progress live. Everything install.ps1 does stays the same, so Setup.exe, the .cmd and the built-in updater all
; install IRL Homekit the same way.
;
; Build (Inno Setup 6.3 or newer):  iscc installer\IRLHomekit.iss          -> installer\Output\IRL-Homekit-Setup-<version>.exe
; Test build:  iscc /DTestInstallDir=C:\Temp\irlhk-test /DOutputName=Test installer\IRLHomekit.iss  installs into that folder
; with install.ps1 -SkipSystem (no tasks, shortcuts, firewall rules or Apps entry), so the whole wizard can be run on a PC
; that already has IRL Homekit.
; The release workflow (.github/workflows/release.yml) builds it and attaches it to every GitHub release.

#ifndef AppVersion
  #define VerFile FileOpen(SourcePath + "..\VERSION")
  #define AppVersion Trim(FileRead(VerFile))
  #expr FileClose(VerFile)
  #undef VerFile
#endif
; Windows file versions are numbers only: 1.0.0-beta.12 -> 1.0.0
#define NumVersion Copy(AppVersion, 1, Pos("-", AppVersion + "-") - 1)

[Setup]
AppId={{7E1C2B5A-3D4F-4E8B-9A61-1F2C3D4E5A6B}
AppName=IRL Homekit
AppVersion={#AppVersion}
AppVerName=IRL Homekit {#AppVersion}
AppPublisher=IRL Homekit
AppPublisherURL=https://github.com/CursedByJava/irl-homekit
AppSupportURL=https://github.com/CursedByJava/irl-homekit/issues
VersionInfoVersion={#NumVersion}
VersionInfoProductVersion={#NumVersion}
VersionInfoDescription=IRL Homekit Setup
VersionInfoProductName=IRL Homekit
VersionInfoProductTextVersion={#AppVersion}
DefaultDirName={code:GetDefaultDir}
DisableWelcomePage=no
DisableDirPage=no
DirExistsWarning=no
; What install.ps1 downloads and unpacks (OBS, Node.js and the tools), so the folder page shows a real figure.
ExtraDiskSpaceRequired=1500000000
DisableProgramGroupPage=yes
DisableReadyMemo=no
; install.ps1 registers IRL Homekit in Settings > Apps with its own uninstaller.
Uninstallable=no
CreateUninstallRegKey=no
PrivilegesRequired=admin
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
CloseApplications=no
RestartApplications=no
; IRL Homekit's look: dark (like the dashboard and the IRL Homekit OBS), the logo's gradient on the first and last
; pages and the app icon on the others. installer\images\Make-SetupImages.ps1 draws the images from the logo.
WizardStyle=modern dark windows11 includetitlebar hidebevels
WizardBackColor=#1c1c1e
WizardImageFile=images\wizard-202.png,images\wizard-336.png,images\wizard-430.png,images\wizard-534.png
WizardImageBackColor=#d4145a
WizardSmallImageFile=images\small-58.png,images\small-87.png,images\small-116.png,images\small-145.png
SetupIconFile=..\dashboard\public\icon.ico
OutputDir=Output
#ifdef OutputName
OutputBaseFilename=IRL-Homekit-Setup-{#AppVersion}-{#OutputName}
#else
OutputBaseFilename=IRL-Homekit-Setup-{#AppVersion}
#endif
Compression=lzma2/max
SolidCompression=yes
SetupLogging=yes

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Messages]
WelcomeLabel2=This sets up IRL Homekit {#AppVersion} on this PC: your own IRL streaming server (bonded phone stream, automatic LIVE / LOW / BRB scenes, multistreaming and a phone dashboard).%n%nIt takes about 5 minutes and downloads about 400 MB. Your regular OBS is not changed.%n%nIf IRL Homekit is already installed, this updates it and keeps all your settings.
FinishedHeadingLabel=IRL Homekit is ready
ClickFinish=Click Finish to close Setup.

[Files]
; The whole app, unpacked to a temporary folder for install.ps1 (which copies what it needs into the install folder).
Source: "..\*"; Excludes: ".git,.github,\installer\Output,\installer\images,\docs\images"; DestDir: "{tmp}\src"; Flags: recursesubdirs createallsubdirs ignoreversion
; Needed before the pages are shown.
Source: "Get-SetupInfo.ps1"; Flags: dontcopy
Source: "..\scripts\Connect-Twitch.ps1"; Flags: dontcopy
Source: "..\templates\relay-vps.sh"; Flags: dontcopy

[Run]
Filename: "{win}\notepad.exe"; Parameters: """{code:GetGuidePath}"""; Description: "Open my phone settings and the last steps (PHONE-SETUP.md)"; Flags: postinstall nowait skipifsilent runasoriginaluser; Check: InstallSucceeded
Filename: "{code:GetDashboardUrl}"; Description: "Open the dashboard"; Flags: postinstall shellexec nowait skipifsilent runasoriginaluser unchecked; Check: InstallSucceeded

[Code]
const
  EM_LINESCROLL = $00B6;
  OracleUrl = 'https://cloud.oracle.com';
  RelayGuideUrl = 'https://github.com/CursedByJava/irl-homekit/blob/main/docs/RELAY.md';
  DuckDnsUrl = 'https://www.duckdns.org';
  TotalSteps = 10;

var
  Info: TStringList;            // lines from Get-SetupInfo.ps1: kind<TAB>value[<TAB>value]
  IsUpdate: Boolean;
  InstalledVersion, RelayToken, RelayScript: String;
  InstallOk: Boolean;
  InstallLog, ResultLines: TStringList;
  DashboardUrl, GuidePath: String;

  UpdatePage: TInputOptionWizardPage;
  ChannelsPage, CustomPage: TWizardPage;
  TwitchEdit, KickEdit, YoutubeEdit, CustomNameEdit, CustomServerEdit, CustomKeyEdit: TNewEdit;
  CustomKeyHint: TNewStaticText;
  TwitchStatus: TNewStaticText;
  TwitchSignedIn: Boolean;
  ObsPage: TWizardPage;
  CollectionCombo, ProfileCombo: TNewComboBox;
  ImportObsCheck: TNewCheckBox;
  OverlayPage: TInputOptionWizardPage;
  OverlayFor: String;
  LoginPage: TWizardPage;
  LoginUser, LoginPass, LoginPass2: TNewEdit;
  LoginGenerate: TNewCheckBox;
  NetworkPage: TInputOptionWizardPage;
  RelayPage: TWizardPage;
  RelayHostEdit: TNewEdit;
  RelayMemo: TNewMemo;
  RemotePage: TInputOptionWizardPage;
  RemoteDetailPage: TWizardPage;
  DuckNameEdit, DuckTokenEdit, DomainEdit: TNewEdit;
  DuckPanel, DomainPanel: TPanel;
  DuckTokenHint: TNewStaticText;
  DuckTimer: Longword;
  OptionsPage: TInputOptionWizardPage;
  InstallMemo: TNewMemo;
  SummaryPage: TOutputMsgMemoWizardPage;

function SetEnvironmentVariable(lpName, lpValue: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';
function SendMessageStr(hWnd: HWND; Msg: Cardinal; wParam: Longint; lParam: String): Longint;
  external 'SendMessageW@user32.dll stdcall';
// Clipboard (the DuckDNS token is picked up from it) and a timer to check it while that page is open.
function OpenClipboard(hWndNewOwner: HWND): Boolean; external 'OpenClipboard@user32.dll stdcall';
function CloseClipboard: Boolean; external 'CloseClipboard@user32.dll stdcall';
function GetClipboardData(uFormat: Cardinal): Longword; external 'GetClipboardData@user32.dll stdcall';
function GlobalLock(hMem: Longword): Longword; external 'GlobalLock@kernel32.dll stdcall';
function GlobalUnlock(hMem: Longword): Boolean; external 'GlobalUnlock@kernel32.dll stdcall';
function lstrlenW(lpString: Longword): Integer; external 'lstrlenW@kernel32.dll stdcall';
function lstrcpynW(lpString1: String; lpString2: Longword; iMaxLength: Integer): Longword; external 'lstrcpynW@kernel32.dll stdcall';
function SetTimer(hWnd: HWND; nIDEvent, uElapse: Cardinal; lpTimerFunc: Longword): Cardinal; external 'SetTimer@user32.dll stdcall';
function KillTimer(hWnd: HWND; uIDEvent: Cardinal): Boolean; external 'KillTimer@user32.dll stdcall';

const
  EM_SETCUEBANNER = $1501;
  CF_UNICODETEXT = 13;
  // Brand and platform colours ($bbggrr).
  ClrBrand = $552DFF;     // #FF2D55
  ClrMuted = $A0A0A0;
  ClrTwitch = $FF70A9;    // #A970FF
  ClrKick = $18FC53;      // #53FC18
  ClrYouTube = $454EFF;   // #FF4E45

// Grey placeholder text inside an empty box.
procedure Hint(E: TNewEdit; Text: String);
begin
  SendMessageStr(E.Handle, EM_SETCUEBANNER, 1, Text);
end;

function ClipboardText: String;
var
  H, P: Longword;
  N: Integer;
begin
  Result := '';
  if not OpenClipboard(0) then Exit;
  try
    H := GetClipboardData(CF_UNICODETEXT);
    if H = 0 then Exit;
    P := GlobalLock(H);
    if P = 0 then Exit;
    try
      N := lstrlenW(P);
      if (N > 0) and (N < 4096) then
      begin
        Result := StringOfChar(' ', N + 1);
        lstrcpynW(Result, P, N + 1);
        Result := Copy(Result, 1, N);
      end;
    finally
      GlobalUnlock(H);
    end;
  finally
    CloseClipboard;
  end;
end;

// ------------------------------------------------------------------ small helpers
function PowerShellExe: String;
begin
  Result := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
end;

// N-th (0-based) tab-separated field of S.
function Field(S: String; N: Integer): String;
var
  P: Integer;
begin
  while N > 0 do
  begin
    P := Pos(#9, S);
    if P = 0 then begin Result := ''; Exit; end;
    Delete(S, 1, P);
    N := N - 1;
  end;
  P := Pos(#9, S);
  if P > 0 then Result := Copy(S, 1, P - 1) else Result := S;
end;

function InfoValue(Kind, Key: String): String;
var
  I: Integer;
begin
  Result := '';
  if Info = nil then Exit;
  for I := 0 to Info.Count - 1 do
    if Field(Info[I], 0) = Kind then
    begin
      if Key = '' then begin Result := Field(Info[I], 1); Exit; end;
      if Field(Info[I], 1) = Key then begin Result := Field(Info[I], 2); Exit; end;
    end;
end;

function JsonStr(S: String): String;
begin
  StringChangeEx(S, '\', '\\', True);
  StringChangeEx(S, '"', '\"', True);
  StringChangeEx(S, #13, '\r', True);
  StringChangeEx(S, #10, '\n', True);
  StringChangeEx(S, #9, '\t', True);
  Result := '"' + S + '"';
end;

function OnlyChars(S, Allowed: String): Boolean;
var
  I: Integer;
begin
  Result := Length(S) > 0;
  for I := 1 to Length(S) do
    if Pos(S[I], Allowed) = 0 then begin Result := False; Exit; end;
end;

function IsHostOrIp(S: String): Boolean;
begin
  Result := OnlyChars(S, 'abcdefghijklmnopqrstuvwxyz0123456789.-') and (Pos('.', S) > 1) and (S[Length(S)] <> '.');
end;

procedure OpenUrl(Url: String);
var
  Code: Integer;
begin
  ShellExecAsOriginalUser('open', Url, '', '', SW_SHOWNORMAL, ewNoWait, Code);
end;

function NewLabel(Page: TWizardPage; Top: Integer; Text: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(Page);
  Result.Parent := Page.Surface;
  Result.Left := 0;
  Result.Top := Top;
  Result.Width := Page.SurfaceWidth;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Caption := Text;
  Result.AdjustHeight;
end;

function NewEdit(Parent: TWinControl; Top: Integer; Width: Integer): TNewEdit;
begin
  Result := TNewEdit.Create(Parent);
  Result.Parent := Parent;
  Result.Left := 0;
  Result.Top := Top;
  Result.Width := Width;
end;

function NewButton(Page: TWizardPage; Left, Top, Width: Integer; Caption: String; OnClick: TNotifyEvent): TNewButton;
begin
  Result := TNewButton.Create(Page);
  Result.Parent := Page.Surface;
  Result.Left := Left;
  Result.Top := Top;
  Result.Width := Width;
  Result.Height := ScaleY(25);
  Result.Caption := Caption;
  Result.OnClick := OnClick;
end;

// A clickable text link in the brand colour.
function NewLink(Parent: TWinControl; Left, Top: Integer; Caption: String; OnClick: TNotifyEvent): TNewStaticText;
begin
  Result := TNewStaticText.Create(Parent);
  Result.Parent := Parent;
  Result.Left := Left;
  Result.Top := Top;
  Result.Caption := Caption;
  Result.Font.Color := ClrBrand;
  Result.StyleElements := Result.StyleElements - [seFont];   // keep our colour under the dark style
  Result.Font.Style := [fsUnderline];
  Result.Cursor := crHand;
  Result.OnClick := OnClick;
end;

// A platform's name in its own colour, bold.
function NewTitle(Parent: TWinControl; Top: Integer; Caption: String; Color: Integer): TNewStaticText;
begin
  Result := TNewStaticText.Create(Parent);
  Result.Parent := Parent;
  Result.Top := Top;
  Result.Caption := Caption;
  Result.Font.Style := [fsBold];
  Result.Font.Color := Color;
  Result.StyleElements := Result.StyleElements - [seFont];
end;

function NewNote(Parent: TWinControl; Left, Top, Width: Integer; Caption: String): TNewStaticText;
begin
  Result := TNewStaticText.Create(Parent);
  Result.Parent := Parent;
  Result.Left := Left;
  Result.Top := Top;
  Result.Width := Width;
  Result.AutoSize := False;
  Result.WordWrap := True;
  Result.Caption := Caption;
  Result.Font.Color := ClrMuted;
  Result.StyleElements := Result.StyleElements - [seFont];
  Result.AdjustHeight;
end;

// ------------------------------------------------------------------ install folder
function GetDefaultDir(Param: String): String;
begin
#ifdef TestInstallDir
  // Test builds only (iscc /DTestInstallDir=<folder>): install there, without the system changes (see RunInstall).
  Result := '{#TestInstallDir}'; Exit;
#endif
  // install.ps1 records the folder for Settings > Apps.
  if not RegQueryStringValue(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\IRLHomekit', 'InstallLocation', Result) or (Result = '') then
    Result := 'C:\IRLHomekit';
end;

function GetGuidePath(Param: String): String;
begin
  Result := GuidePath;
  if Result = '' then Result := AddBackslash(WizardDirValue) + 'PHONE-SETUP.md';
end;

function GetDashboardUrl(Param: String): String;
begin
  Result := DashboardUrl;
  if Result = '' then Result := 'http://localhost:8090';
end;

function InstallSucceeded: Boolean;
begin
  Result := InstallOk;
end;

// ------------------------------------------------------------------ what's on this PC
function LoadSetupInfo: Boolean;
var
  Code: Integer;
  OutFile: String;
begin
  Info := TStringList.Create;
  ExtractTemporaryFile('Get-SetupInfo.ps1');
  OutFile := ExpandConstant('{tmp}\setupinfo.txt');
  Result := Exec(PowerShellExe, '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\Get-SetupInfo.ps1') + '" -Out "' + OutFile +
    '" -InstallDir "' + GetDefaultDir('') + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) and FileExists(OutFile);
  if Result then Info.LoadFromFile(OutFile);
  InstalledVersion := InfoValue('installed', '');
  IsUpdate := InstalledVersion <> '';
  RelayToken := InfoValue('relaytoken', '');
  Result := Result and (RelayToken <> '');
end;

// Before any page: Setup needs PowerShell to look at this PC (and IRL Homekit itself runs on it).
function InitializeSetup: Boolean;
begin
  Result := LoadSetupInfo;
  if not Result then
    MsgBox('Setup couldn''t run Windows PowerShell on this PC, which IRL Homekit needs.' + #13#10#13#10 +
      'If your organization blocks PowerShell scripts, IRL Homekit can''t run here. Otherwise restart the PC and run Setup again. ' +
      'Help: https://github.com/CursedByJava/irl-homekit/issues', mbCriticalError, MB_OK);
end;

// The relay VM's setup script, with this PC's relay password in it (LF line endings: it runs on Linux).
procedure PrepareRelayScript;
var
  S: AnsiString;
  T: String;
begin
  ExtractTemporaryFile('relay-vps.sh');
  LoadStringFromFile(ExpandConstant('{tmp}\relay-vps.sh'), S);
  T := String(S);
  StringChangeEx(T, #13#10, #10, True);
  StringChangeEx(T, '{{RELAY_TOKEN}}', RelayToken, True);
  StringChangeEx(T, '{{VERSION}}', '{#AppVersion}', True);
  RelayScript := T;
  SaveStringToFile(ExpandConstant('{tmp}\relay-vps-ready.sh'), AnsiString(T), False);
end;

procedure CopyRelayScript(Sender: TObject);
var
  Code: Integer;
begin
  if Exec(PowerShellExe, '-NoProfile -Command "Set-Clipboard -Value ([IO.File]::ReadAllText(''' + ExpandConstant('{tmp}\relay-vps-ready.sh') + '''))"',
    '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0) then
    MsgBox('Copied. In Oracle Cloud, paste it into Create instance > Advanced options > Management > Initialization script (Paste cloud-init script).', mbInformation, MB_OK)
  else
  begin
    // Copying from the box would give Windows line breaks, which break the script on Linux. Notepad keeps them as they are.
    MsgBox('Couldn''t copy it automatically. It opens in Notepad now: press Ctrl+A, then Ctrl+C there.', mbInformation, MB_OK);
    ShellExecAsOriginalUser('open', ExpandConstant('{win}\notepad.exe'), '"' + ExpandConstant('{tmp}\relay-vps-ready.sh') + '"', '', SW_SHOWNORMAL, ewNoWait, Code);
  end;
end;

procedure OpenOracle(Sender: TObject); begin OpenUrl(OracleUrl); end;
procedure OpenRelayGuide(Sender: TObject); begin OpenUrl(RelayGuideUrl); end;
procedure OpenDuckDns(Sender: TObject); begin OpenUrl(DuckDnsUrl); end;
// Where each platform shows your name (Twitch and Kick put it in the address once you're signed in; YouTube shows
// the channel ID with a copy button).
// Sign in with Twitch (scripts\Connect-Twitch.ps1): a small window shows a code and Twitch opens in the browser.
// The result (tokens, stream key) stays in a file in Setup's temp folder until install.ps1 uses and deletes it.
procedure TwitchSignIn(Sender: TObject);
var
  Code: Integer;
  Login, Err: AnsiString;
  OutFile: String;
begin
  OutFile := ExpandConstant('{tmp}\twitch-auth.json');
  ExtractTemporaryFile('Connect-Twitch.ps1');
  DeleteFile(OutFile); DeleteFile(OutFile + '.login'); DeleteFile(OutFile + '.error');
  Code := -1;
  WizardForm.Enabled := False;
  try
    Exec(PowerShellExe, '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "' + ExpandConstant('{tmp}\Connect-Twitch.ps1') +
      '" -OutFile "' + OutFile + '"', '', SW_SHOWNORMAL, ewWaitUntilTerminated, Code);
  finally
    WizardForm.Enabled := True;
  end;
  if (Code = 0) and LoadStringFromFile(OutFile + '.login', Login) then
  begin
    TwitchSignedIn := True;
    TwitchEdit.Text := Trim(String(Login));
    TwitchStatus.Caption := 'Signed in. Your stream key and chat commands get set up for you.';
    TwitchStatus.Font.Color := ClrKick;
  end
  else if LoadStringFromFile(OutFile + '.error', Err) then
    MsgBox('Couldn''t sign in with Twitch: ' + String(Err) + #13#10#13#10 +
      'You can type your Twitch name instead, and sign in later: Start menu > IRL Homekit - Connect Twitch.', mbError, MB_OK);
end;
procedure OpenKick(Sender: TObject); begin OpenUrl('https://kick.com/dashboard'); end;
procedure OpenYoutube(Sender: TObject); begin OpenUrl('https://www.youtube.com/account_advanced'); end;

procedure SkipChannels(Sender: TObject);
begin
  TwitchEdit.Text := ''; KickEdit.Text := ''; YoutubeEdit.Text := '';
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

procedure SkipCustom(Sender: TObject);
begin
  CustomNameEdit.Text := ''; CustomServerEdit.Text := ''; CustomKeyEdit.Text := '';
  WizardForm.NextButton.OnClick(WizardForm.NextButton);
end;

// DuckDNS token: 36 characters, like 8 hex - 4 - 4 - 4 - 12.
function IsDuckToken(S: String): Boolean;
begin
  S := Lowercase(Trim(S));
  Result := (Length(S) = 36) and OnlyChars(S, '0123456789abcdef-') and (S[9] = '-') and (S[14] = '-') and (S[19] = '-') and (S[24] = '-');
end;

// While the DuckDNS page is open: a token copied on duckdns.org fills itself in.
procedure DuckClipboardTick(H: Longword; Msg: Longword; IdEvent: Longword; Time: Longword);
var
  S: String;
begin
  S := Trim(ClipboardText);
  if IsDuckToken(S) and (Lowercase(S) <> Lowercase(Trim(DuckTokenEdit.Text))) then
  begin
    DuckTokenEdit.Text := Lowercase(S);
    DuckTokenHint.Caption := 'Got your token from the clipboard.';
    DuckTokenHint.Font.Color := ClrKick;
  end;
end;

procedure LoginGenerateClick(Sender: TObject);
begin
  LoginPass.Enabled := not LoginGenerate.Checked;
  LoginPass2.Enabled := not LoginGenerate.Checked;
end;

// ------------------------------------------------------------------ pages
procedure CreatePages;
var
  I, Y: Integer;
  L: TNewStaticText;
  B: TNewButton;
  Prev: String;
begin
  // Updating: keep everything unless asked.
  UpdatePage := CreateInputOptionPage(wpWelcome, 'Update IRL Homekit',
    'IRL Homekit ' + InstalledVersion + ' is installed on this PC.',
    'Setup updates it to {#AppVersion} and keeps all your settings: channels, scenes, overlays, passwords, stream keys, ' +
    'the remote dashboard and your phone connection.' + #13#10#13#10 +
    'Make sure you are not live: IRL Homekit closes during the update and opens again when it''s done.',
    False, False);
  UpdatePage.Add('Also change how my phone and the dashboard connect (port forwarding or relay server, remote dashboard)');
  UpdatePage.Add('Also change my channels and stream destinations (Twitch, Kick, YouTube, custom)');

  // Channels: all optional. Skipped ones can be added any time by running Setup again.
  ChannelsPage := CreateCustomPage(wpSelectDir, 'Your channels', 'All optional: skip any of them and add them later by running Setup again.');
  Y := 0;
  NewTitle(ChannelsPage.Surface, Y, 'Twitch', ClrTwitch);
  TwitchEdit := NewEdit(ChannelsPage.Surface, Y + ScaleY(17), ScaleX(240));
  Hint(TwitchEdit, 'your Twitch name');
  TwitchEdit.Text := InfoValue('prev', 'twitchChannel');
  NewButton(ChannelsPage, ScaleX(252), Y + ScaleY(15), ScaleX(140), 'Sign in with Twitch', @TwitchSignIn);
  TwitchStatus := NewNote(ChannelsPage.Surface, ScaleX(400), Y + ScaleY(13), ChannelsPage.SurfaceWidth - ScaleX(400),
    'Brings in your stream key and turns on chat commands.');
  Y := Y + ScaleY(54);
  NewTitle(ChannelsPage.Surface, Y, 'Kick', ClrKick);
  NewLink(ChannelsPage.Surface, ScaleX(70), Y, 'Open my Kick', @OpenKick);
  KickEdit := NewEdit(ChannelsPage.Surface, Y + ScaleY(17), ScaleX(240));
  Hint(KickEdit, 'your Kick name');
  KickEdit.Text := InfoValue('prev', 'kickChannel');
  NewNote(ChannelsPage.Surface, ScaleX(252), Y + ScaleY(17), ChannelsPage.SurfaceWidth - ScaleX(252), 'Live status and chat in Studio.');
  Y := Y + ScaleY(54);
  NewTitle(ChannelsPage.Surface, Y, 'YouTube', ClrYouTube);
  NewLink(ChannelsPage.Surface, ScaleX(70), Y, 'Find my channel', @OpenYoutube);
  YoutubeEdit := NewEdit(ChannelsPage.Surface, Y + ScaleY(17), ScaleX(240));
  Hint(YoutubeEdit, 'channel link, @handle or ID');
  YoutubeEdit.Text := InfoValue('prev', 'youtubeChannelId');
  NewNote(ChannelsPage.Surface, ScaleX(252), Y + ScaleY(17), ChannelsPage.SurfaceWidth - ScaleX(252), 'Paste the link from your browser.');
  Y := Y + ScaleY(58);
  NewNote(ChannelsPage.Surface, 0, Y, ChannelsPage.SurfaceWidth,
    'Signing in with Twitch puts your Twitch stream key in for you. Kick and YouTube keys go into the IRL Homekit OBS later; their chat and titles connect in Studio (its Connect buttons).');
  NewLink(ChannelsPage.Surface, 0, ChannelsPage.SurfaceHeight - ScaleY(16), 'Skip for now', @SkipChannels);

  // Your own extra destination: any RTMP server, streamed to alongside the others.
  CustomPage := CreateCustomPage(ChannelsPage.ID, 'Custom destination', 'Optional: also stream to another service or your own server.');
  L := NewNote(CustomPage.Surface, 0, 0, CustomPage.SurfaceWidth,
    'Any RTMP server works, like Restream, Facebook, Trovo or your own. It gets its own switch under Stream to on the dashboard.');
  Y := L.Top + L.Height + ScaleY(10);
  NewTitle(CustomPage.Surface, Y, 'Name', ClrBrand);
  CustomNameEdit := NewEdit(CustomPage.Surface, Y + ScaleY(17), ScaleX(240));
  Hint(CustomNameEdit, 'e.g. Restream');
  CustomNameEdit.Text := InfoValue('prev', 'customName');
  Y := Y + ScaleY(50);
  NewTitle(CustomPage.Surface, Y, 'Server (RTMP URL)', ClrBrand);
  CustomServerEdit := NewEdit(CustomPage.Surface, Y + ScaleY(17), CustomPage.SurfaceWidth);
  Hint(CustomServerEdit, 'rtmp://live.example.com/app');
  CustomServerEdit.Text := InfoValue('prev', 'customServer');
  Y := Y + ScaleY(50);
  NewTitle(CustomPage.Surface, Y, 'Stream key', ClrBrand);
  CustomKeyEdit := NewEdit(CustomPage.Surface, Y + ScaleY(17), CustomPage.SurfaceWidth);
  CustomKeyEdit.PasswordChar := '*';
  Hint(CustomKeyEdit, 'from that service''s settings');
  CustomKeyHint := NewNote(CustomPage.Surface, 0, Y + ScaleY(42), CustomPage.SurfaceWidth, '');
  if InfoValue('prev', 'hasCustomKey') = '1' then begin CustomKeyHint.Caption := 'Leave empty to keep the stream key you entered before.'; CustomKeyHint.AdjustHeight; end;
  NewLink(CustomPage.Surface, 0, CustomPage.SurfaceHeight - ScaleY(16), 'Skip for now', @SkipCustom);

  // Your regular OBS: what to start from.
  ObsPage := CreateCustomPage(CustomPage.ID, 'Your OBS', 'IRL Homekit runs its own copy of OBS. Choose what it starts with.');
  L := NewLabel(ObsPage, 0, 'Scenes and overlays: copy a scene collection from your regular OBS (the IRL scenes are built from it):');
  CollectionCombo := TNewComboBox.Create(ObsPage);
  CollectionCombo.Parent := ObsPage.Surface;
  CollectionCombo.Style := csDropDownList;
  CollectionCombo.Top := L.Top + L.Height + ScaleY(4);
  CollectionCombo.Width := ObsPage.SurfaceWidth;
  CollectionCombo.Items.Add('Start empty (just the IRL scenes)');
  L := NewLabel(ObsPage, CollectionCombo.Top + CollectionCombo.Height + ScaleY(14), 'Output and stream settings: copy a profile (includes your Twitch stream key):');
  ProfileCombo := TNewComboBox.Create(ObsPage);
  ProfileCombo.Parent := ObsPage.Surface;
  ProfileCombo.Style := csDropDownList;
  ProfileCombo.Top := L.Top + L.Height + ScaleY(4);
  ProfileCombo.Width := ObsPage.SurfaceWidth;
  ProfileCombo.Items.Add('Fresh profile: 1920x1080, 60 fps, 8000 kbps');
  for I := 0 to Info.Count - 1 do
  begin
    if Field(Info[I], 0) = 'collection' then CollectionCombo.Items.Add(Field(Info[I], 1));
    if Field(Info[I], 0) = 'profile' then ProfileCombo.Items.Add(Field(Info[I], 1));
  end;
  CollectionCombo.ItemIndex := 0;
  ProfileCombo.ItemIndex := 0;
  ImportObsCheck := TNewCheckBox.Create(ObsPage);
  ImportObsCheck.Parent := ObsPage.Surface;
  ImportObsCheck.Top := ProfileCombo.Top + ProfileCombo.Height + ScaleY(18);
  ImportObsCheck.Width := ObsPage.SurfaceWidth;
  ImportObsCheck.Caption := 'Also copy everything else from my regular OBS';
  NewLabel(ObsPage, ImportObsCheck.Top + ImportObsCheck.Height + ScaleY(6), 'That''s all its profiles, scene collections, settings and plugins. Your regular OBS is only read from, never changed. ' +
    'You can import from it again later: Start menu > IRL Homekit - Import from OBS.');

  OverlayPage := CreateInputOptionPage(ObsPage.ID, 'Overlays', 'Which browser sources (chat, alerts, ...) should show on the IRL scenes?',
    'Ticked sources appear on top of your phone video on the IRL LIVE / LOW scenes.', False, True);

  // Dashboard login.
  LoginPage := CreateCustomPage(OverlayPage.ID, 'Dashboard login', 'The login for your phone dashboard and Studio pages.');
  L := NewLabel(LoginPage, 0, 'Username:');
  LoginUser := NewEdit(LoginPage.Surface, L.Top + L.Height + ScaleY(3), ScaleX(220));
  LoginGenerate := TNewCheckBox.Create(LoginPage);
  LoginGenerate.Parent := LoginPage.Surface;
  LoginGenerate.Top := LoginUser.Top + LoginUser.Height + ScaleY(14);
  LoginGenerate.Width := LoginPage.SurfaceWidth;
  LoginGenerate.Caption := 'Make a strong password for me';
  LoginGenerate.OnClick := @LoginGenerateClick;
  L := NewLabel(LoginPage, LoginGenerate.Top + LoginGenerate.Height + ScaleY(4), 'It''s shown at the end of Setup and saved in PHONE-SETUP.md. Or choose your own (at least 10 characters):');
  LoginPass := NewEdit(LoginPage.Surface, L.Top + L.Height + ScaleY(3), ScaleX(220));
  LoginPass.PasswordChar := '*';
  L := NewLabel(LoginPage, LoginPass.Top + LoginPass.Height + ScaleY(8), 'Type it again:');
  LoginPass2 := NewEdit(LoginPage.Surface, L.Top + L.Height + ScaleY(3), ScaleX(220));
  LoginPass2.PasswordChar := '*';
  NewLabel(LoginPage, LoginPass2.Top + LoginPass2.Height + ScaleY(14), 'Change it any time: Start menu > IRL Homekit - Change login.');

  // How the phone reaches this PC.
  NetworkPage := CreateInputOptionPage(LoginPage.ID, 'Phone connection',
    'How does your phone reach this PC when you''re out?',
    'Your phone streams to this PC over the internet, so the internet must be able to reach it.', True, False);
  NetworkPage.Add('Home router (recommended): IRL Homekit opens the ports on it by itself; if your router can''t, Setup says what to do');
  NetworkPage.Add('Relay server: only if the router can''t work (e.g. some 5G home internet, Starlink). Free Oracle Cloud account, 15 minutes');
  NetworkPage.SelectedValueIndex := 0;

  RelayPage := CreateCustomPage(NetworkPage.ID, 'Relay server', 'Set up your free relay on Oracle Cloud, then enter its address.');
  L := NewLabel(RelayPage, 0,
    '1. Create a free Oracle Cloud account and a VM: Ubuntu image, Always Free shape (step by step: the guide button).' + #13#10 +
    '2. Under Advanced options > Management > Initialization script, paste this setup script (it holds your relay password: keep it private).' + #13#10 +
    '3. In the VM''s security list, open UDP 5000, 8890, 51820 and TCP 1935, 80, 443.' + #13#10 +
    '4. Enter the VM''s public IP address below.');
  Y := L.Top + L.Height + ScaleY(6);
  NewButton(RelayPage, 0, Y, ScaleX(140), 'Copy setup script', @CopyRelayScript);
  NewButton(RelayPage, ScaleX(148), Y, ScaleX(130), 'Open Oracle Cloud', @OpenOracle);
  NewButton(RelayPage, ScaleX(286), Y, ScaleX(150), 'Step-by-step guide', @OpenRelayGuide);
  RelayMemo := TNewMemo.Create(RelayPage);
  RelayMemo.Parent := RelayPage.Surface;
  RelayMemo.Top := Y + ScaleY(31);
  RelayMemo.Width := RelayPage.SurfaceWidth;
  RelayMemo.Height := ScaleY(60);
  RelayMemo.ReadOnly := True;
  RelayMemo.ScrollBars := ssVertical;
  RelayMemo.WordWrap := False;
  L := NewLabel(RelayPage, RelayMemo.Top + RelayMemo.Height + ScaleY(8), 'The relay VM''s public IP address:');
  RelayHostEdit := NewEdit(RelayPage.Surface, L.Top + L.Height + ScaleY(3), ScaleX(220));
  RelayHostEdit.Text := InfoValue('prev', 'relayHost');

  // Remote dashboard.
  RemotePage := CreateInputOptionPage(RelayPage.ID, 'Remote dashboard',
    'Open your dashboard from your phone anywhere?',
    'Control the stream, scenes and chat from your phone at https://your-name..., with a free HTTPS certificate.', True, False);
  RemotePage.Add('Yes, with a free DuckDNS name like yourname.duckdns.org (recommended, 2 minutes)');
  RemotePage.Add('Yes, with a domain I own, like irl.yourname.com');
  RemotePage.Add('Not now: only on this PC (set it up later: Start menu > IRL Homekit - Set up remote dashboard)');
  Prev := InfoValue('prev', 'domain');
  if InfoValue('prev', 'duckdnsName') <> '' then RemotePage.SelectedValueIndex := 0
  else if Prev <> '' then RemotePage.SelectedValueIndex := 1
  else if IsUpdate then RemotePage.SelectedValueIndex := 2
  else RemotePage.SelectedValueIndex := 0;
  if InfoValue('prev', 'relayHost') <> '' then NetworkPage.SelectedValueIndex := 1;

  RemoteDetailPage := CreateCustomPage(RemotePage.ID, 'Remote dashboard', 'Your dashboard''s address.');
  DuckPanel := TPanel.Create(RemoteDetailPage);
  DuckPanel.Parent := RemoteDetailPage.Surface;
  DuckPanel.BevelOuter := bvNone;
  DuckPanel.Width := RemoteDetailPage.SurfaceWidth;
  DuckPanel.Height := RemoteDetailPage.SurfaceHeight;
  L := TNewStaticText.Create(DuckPanel);
  L.Parent := DuckPanel; L.AutoSize := False; L.WordWrap := True; L.Width := DuckPanel.Width;
  L.Caption := 'On duckdns.org: sign in (Google, GitHub, Reddit or X), type a name under "sub domain" and press "add domain". ' +
    'Then click the token at the top of the page to copy it: Setup picks it up by itself.';
  L.AdjustHeight;
  B := NewButton(RemoteDetailPage, 0, L.Top + L.Height + ScaleY(6), ScaleX(140), 'Open duckdns.org', @OpenDuckDns);
  B.Parent := DuckPanel;
  L := TNewStaticText.Create(DuckPanel);
  L.Parent := DuckPanel; L.Top := B.Top + B.Height + ScaleY(12); L.Caption := 'The name you added (without .duckdns.org):';
  DuckNameEdit := NewEdit(DuckPanel, L.Top + L.Height + ScaleY(3), ScaleX(220));
  DuckNameEdit.Text := InfoValue('prev', 'duckdnsName');
  L := TNewStaticText.Create(DuckPanel);
  L.Parent := DuckPanel; L.Top := DuckNameEdit.Top + DuckNameEdit.Height + ScaleY(10); L.Caption := 'Your DuckDNS token:';
  DuckTokenEdit := NewEdit(DuckPanel, L.Top + L.Height + ScaleY(3), ScaleX(320));
  DuckTokenHint := TNewStaticText.Create(DuckPanel);
  DuckTokenHint.Parent := DuckPanel; DuckTokenHint.Top := DuckTokenEdit.Top + DuckTokenEdit.Height + ScaleY(4);
  DuckTokenHint.Caption := '';
  if InfoValue('prev', 'hasDuckdnsToken') = '1' then DuckTokenHint.Caption := 'Leave empty to keep the token you entered before.';

  DomainPanel := TPanel.Create(RemoteDetailPage);
  DomainPanel.Parent := RemoteDetailPage.Surface;
  DomainPanel.BevelOuter := bvNone;
  DomainPanel.Width := RemoteDetailPage.SurfaceWidth;
  DomainPanel.Height := RemoteDetailPage.SurfaceHeight;
  L := TNewStaticText.Create(DomainPanel);
  L.Parent := DomainPanel; L.AutoSize := False; L.WordWrap := True; L.Width := DomainPanel.Width;
  L.Caption := 'Use a subdomain for the dashboard, e.g. irl.yourname.com. Studio will be studio.yourname.com.' + #13#10 +
    'After Setup, add an A record for both names pointing to this PC''s home IP (or to your relay server if you use one), ' +
    'then run Start menu > IRL Homekit - Set up remote dashboard to check them. Details: docs\DOMAIN.md.';
  L.AdjustHeight;
  Y := L.Top + L.Height + ScaleY(12);
  L := TNewStaticText.Create(DomainPanel);
  L.Parent := DomainPanel; L.Top := Y; L.Caption := 'Dashboard address:';
  DomainEdit := NewEdit(DomainPanel, L.Top + L.Height + ScaleY(3), ScaleX(260));
  Prev := InfoValue('prev', 'domain');
  if Pos('.duckdns.org', Prev) = 0 then DomainEdit.Text := Prev;

  OptionsPage := CreateInputOptionPage(RemoteDetailPage.ID, 'Start with Windows', 'Should IRL Homekit open by itself?',
    'With this on, IRL Homekit opens (minimized) when you sign in to Windows, so you can go live from your phone any time ' +
    'and the dashboard is always reachable. Change it later on the dashboard (Home PC > Start with Windows).', False, False);
  OptionsPage.Add('Open IRL Homekit automatically when I sign in to Windows (recommended)');
  OptionsPage.Values[0] := True;

  SummaryPage := CreateOutputMsgMemoPage(wpInfoAfter, 'Your IRL Homekit', 'Keep this: your dashboard login and what to do next.',
    'Everything below is also in PHONE-SETUP.md in the install folder.', '');
end;

procedure InitializeWizard;
begin
  InstallLog := TStringList.Create;
  ResultLines := TStringList.Create;
  CreatePages;
  PrepareRelayScript;
  // Live output of install.ps1 under the progress bar.
  InstallMemo := TNewMemo.Create(WizardForm);
  InstallMemo.Parent := WizardForm.InstallingPage;
  InstallMemo.Left := WizardForm.ProgressGauge.Left;
  InstallMemo.Width := WizardForm.ProgressGauge.Width;
  InstallMemo.Top := WizardForm.ProgressGauge.Top + WizardForm.ProgressGauge.Height + ScaleY(12);
  InstallMemo.Height := WizardForm.InstallingPage.Height - InstallMemo.Top - ScaleY(4);
  InstallMemo.ReadOnly := True;
  InstallMemo.ScrollBars := ssVertical;
  InstallMemo.Font.Name := 'Consolas';
  InstallMemo.Font.Size := 8;
end;

function ChangingNetwork: Boolean;
begin
  Result := (not IsUpdate) or UpdatePage.Values[0];
end;

function ChangingChannels: Boolean;
begin
  Result := (not IsUpdate) or UpdatePage.Values[1];
end;

// Checks a DuckDNS name and token with DuckDNS (without moving the name: it's re-pointed at the address it has now).
function DuckDnsAccepts(Name, Token: String): Boolean;
var
  Code: Integer;
  Cmd: String;
begin
  Cmd := '$n=''' + Name + '''; $t=''' + Token + '''; $ip=try{(Resolve-DnsName ($n+''.duckdns.org'') -Type A -DnsOnly -ErrorAction Stop | ? IPAddress | select -First 1).IPAddress}catch{''}; ' +
    '$r=Invoke-RestMethod (''https://www.duckdns.org/update?domains=''+$n+''&token=''+$t+$(if($ip){''&ip=''+$ip})) -TimeoutSec 15; if($r -eq ''OK''){exit 0}else{exit 3}';
  Result := Exec(PowerShellExe, '-NoProfile -Command "' + Cmd + '"', '', SW_HIDE, ewWaitUntilTerminated, Code) and (Code = 0);
  // No internet right now: don't block Setup, the installer checks again.
  if not Result and (Code <> 3) then Result := True;
end;

function ShouldSkipPage(PageID: Integer): Boolean;
var
  I: Integer;
  HasOverlay: Boolean;
begin
  Result := False;
  if PageID = wpWelcome then Result := IsUpdate   // the update page says it all
  else if PageID = UpdatePage.ID then Result := not IsUpdate
  else if (PageID = wpSelectDir) or (PageID = OptionsPage.ID) then Result := IsUpdate
  else if (PageID = ChannelsPage.ID) or (PageID = CustomPage.ID) then Result := not ChangingChannels
  else if PageID = ObsPage.ID then Result := IsUpdate or ((CollectionCombo.Items.Count = 1) and (ProfileCombo.Items.Count = 1))
  else if PageID = OverlayPage.ID then
  begin
    HasOverlay := False;
    if (not IsUpdate) and (CollectionCombo.ItemIndex > 0) then
      for I := 0 to Info.Count - 1 do
        if (Field(Info[I], 0) = 'browser') and (Field(Info[I], 1) = CollectionCombo.Text) then HasOverlay := True;
    Result := not HasOverlay;
  end
  else if PageID = LoginPage.ID then Result := InfoValue('prev', 'dashboardUser') <> ''
  else if (PageID = NetworkPage.ID) or (PageID = RemotePage.ID) then Result := not ChangingNetwork
  else if PageID = RelayPage.ID then Result := (not ChangingNetwork) or (NetworkPage.SelectedValueIndex <> 1)
  else if PageID = RemoteDetailPage.ID then Result := (not ChangingNetwork) or (RemotePage.SelectedValueIndex = 2)
  else if PageID = SummaryPage.ID then Result := ResultLines.Count + InstallLog.Count = 0;
end;

procedure CurPageChanged(CurPageID: Integer);
var
  I: Integer;
begin
  if (CurPageID <> RemoteDetailPage.ID) and (DuckTimer <> 0) then begin KillTimer(0, DuckTimer); DuckTimer := 0; end;
  if CurPageID = OverlayPage.ID then
  begin
    if OverlayFor <> CollectionCombo.Text then
    begin
      OverlayPage.CheckListBox.Items.Clear;
      for I := 0 to Info.Count - 1 do
        if (Field(Info[I], 0) = 'browser') and (Field(Info[I], 1) = CollectionCombo.Text) then OverlayPage.Add(Field(Info[I], 2));
      OverlayFor := CollectionCombo.Text;
    end;
  end
  else if CurPageID = LoginPage.ID then
  begin
    if LoginUser.Text = '' then LoginUser.Text := Lowercase(Trim(TwitchEdit.Text));
    if LoginUser.Text = '' then LoginUser.Text := 'admin';
    LoginGenerateClick(nil);
  end
  else if CurPageID = RelayPage.ID then
  begin
    if RelayMemo.Lines.Count = 0 then
    begin
      RelayMemo.Lines.Text := RelayScript;   // shown with Windows line breaks; the Copy button copies the Linux (LF) original
    end;
  end
  else if CurPageID = RemoteDetailPage.ID then
  begin
    DuckPanel.Visible := RemotePage.SelectedValueIndex = 0;
    DomainPanel.Visible := RemotePage.SelectedValueIndex = 1;
    // A name suggestion from your Twitch name (DuckDNS names are first come, first served).
    if (DuckNameEdit.Text = '') and (Trim(TwitchEdit.Text) <> '') then DuckNameEdit.Text := Lowercase(Trim(TwitchEdit.Text)) + '-irl';
    if DuckPanel.Visible and (DuckTimer = 0) then DuckTimer := SetTimer(0, 0, 1000, CreateCallback(@DuckClipboardTick));
  end
  else if (CurPageID = wpFinished) and not InstallOk then
  begin
    WizardForm.FinishedHeadingLabel.Caption := 'Setup couldn''t finish';
    WizardForm.FinishedLabel.Caption := 'IRL Homekit wasn''t fully installed. The log is in the install folder (logs\setup.log). Fix the problem shown on the previous page and run Setup again.';
    WizardForm.FinishedLabel.AdjustHeight;
  end;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  S: String;
begin
  Result := True;
  if CurPageID = ChannelsPage.ID then
  begin
    // A pasted link works too: keep just the name.
    S := Lowercase(Trim(TwitchEdit.Text));
    StringChangeEx(S, 'https://', '', True); StringChangeEx(S, 'www.', '', True); StringChangeEx(S, 'twitch.tv/', '', True);
    if Pos('/', S) > 0 then S := Copy(S, 1, Pos('/', S) - 1);
    if (S <> '') and not OnlyChars(S, 'abcdefghijklmnopqrstuvwxyz0123456789_') then
    begin
      MsgBox('That doesn''t look like a Twitch name (letters, numbers and _ only). Or leave it empty to skip Twitch for now.', mbError, MB_OK); Result := False; Exit;
    end;
    TwitchEdit.Text := S;
    S := Lowercase(Trim(KickEdit.Text));
    StringChangeEx(S, 'https://', '', True); StringChangeEx(S, 'www.', '', True); StringChangeEx(S, 'kick.com/', '', True);
    if Pos('/', S) > 0 then S := Copy(S, 1, Pos('/', S) - 1);
    if (S <> '') and not OnlyChars(S, 'abcdefghijklmnopqrstuvwxyz0123456789_-') then
    begin
      MsgBox('That doesn''t look like a Kick name (letters, numbers, - and _ only). Or leave it empty to skip Kick for now.', mbError, MB_OK); Result := False; Exit;
    end;
    KickEdit.Text := S;
    YoutubeEdit.Text := Trim(YoutubeEdit.Text);   // a link, @handle or UC... ID: the installer finds the channel
  end
  else if CurPageID = CustomPage.ID then
  begin
    S := Trim(CustomServerEdit.Text);
    if (S = '') and ((Trim(CustomNameEdit.Text) <> '') or (Trim(CustomKeyEdit.Text) <> '')) then
    begin
      MsgBox('Enter the server address too (it starts with rtmp://), or click "Skip for now".', mbError, MB_OK); Result := False; Exit;
    end;
    if (S <> '') and (Pos('rtmp://', Lowercase(S)) <> 1) and (Pos('rtmps://', Lowercase(S)) <> 1) then
    begin
      MsgBox('The server address starts with rtmp:// or rtmps:// (that service shows it next to your stream key).', mbError, MB_OK); Result := False; Exit;
    end;
    CustomServerEdit.Text := S;
  end
  else if CurPageID = LoginPage.ID then
  begin
    if Trim(LoginUser.Text) = '' then begin MsgBox('Enter a username.', mbError, MB_OK); Result := False; Exit; end;
    if (Pos(' ', Trim(LoginUser.Text)) > 0) or (Pos(#9, LoginUser.Text) > 0) then begin MsgBox('The username can''t contain spaces.', mbError, MB_OK); Result := False; Exit; end;
    if not LoginGenerate.Checked then
    begin
      if Length(LoginPass.Text) < 10 then begin MsgBox('Use at least 10 characters, or tick "Make a strong password for me".', mbError, MB_OK); Result := False; Exit; end;
      if LoginPass.Text <> LoginPass2.Text then begin MsgBox('The two passwords don''t match.', mbError, MB_OK); Result := False; Exit; end;
    end;
  end
  else if CurPageID = RelayPage.ID then
  begin
    S := Lowercase(Trim(RelayHostEdit.Text));
    if not IsHostOrIp(S) then
    begin
      MsgBox('Enter the relay VM''s public IP address (like 129.146.10.20). You''ll find it on the VM''s page in Oracle Cloud.', mbError, MB_OK); Result := False; Exit;
    end;
    RelayHostEdit.Text := S;
  end
  else if CurPageID = RemoteDetailPage.ID then
  begin
    if RemotePage.SelectedValueIndex = 0 then
    begin
      S := Lowercase(Trim(DuckNameEdit.Text));
      StringChangeEx(S, '.duckdns.org', '', True);
      if not OnlyChars(S, 'abcdefghijklmnopqrstuvwxyz0123456789-') then begin MsgBox('Enter the DuckDNS name you added (letters, numbers and dashes).', mbError, MB_OK); Result := False; Exit; end;
      DuckNameEdit.Text := S;
      S := Trim(DuckTokenEdit.Text);
      if (S = '') and (InfoValue('prev', 'hasDuckdnsToken') = '1') then Exit;
      if not IsDuckToken(S) then
      begin
        MsgBox('That doesn''t look like a DuckDNS token (36 letters and numbers with dashes, shown at the top of duckdns.org once you''re signed in).', mbError, MB_OK); Result := False; Exit;
      end;
      if not DuckDnsAccepts(DuckNameEdit.Text, Lowercase(S)) then
      begin
        MsgBox('DuckDNS says "' + DuckNameEdit.Text + '.duckdns.org" isn''t yours with that token. Check you added that name on duckdns.org (press "add domain"), or copy the token again.', mbError, MB_OK); Result := False; Exit;
      end;
    end
    else
    begin
      S := Lowercase(Trim(DomainEdit.Text));
      StringChangeEx(S, 'https://', '', True);
      StringChangeEx(S, 'http://', '', True);
      if Pos('/', S) > 0 then S := Copy(S, 1, Pos('/', S) - 1);
      if not IsHostOrIp(S) or (Pos('.', Copy(S, Pos('.', S) + 1, 999)) = 0) then
      begin
        MsgBox('Enter a subdomain you own, like irl.yourname.com.', mbError, MB_OK); Result := False; Exit;
      end;
      DomainEdit.Text := S;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
var
  S: String;
begin
  if IsUpdate then S := 'Update IRL Homekit ' + InstalledVersion + ' to {#AppVersion}, keeping your settings.' + NewLine + NewLine
  else S := MemoDirInfo + NewLine + NewLine;
  if ChangingChannels then
  begin
    S := S + 'Channels:' + NewLine;
    if TwitchEdit.Text <> '' then S := S + Space + 'Twitch: ' + TwitchEdit.Text + NewLine;
    if KickEdit.Text <> '' then S := S + Space + 'Kick: ' + KickEdit.Text + NewLine;
    if YoutubeEdit.Text <> '' then S := S + Space + 'YouTube: ' + YoutubeEdit.Text + NewLine;
    if CustomServerEdit.Text <> '' then S := S + Space + 'Custom destination: ' + CustomNameEdit.Text + ' (' + CustomServerEdit.Text + ')' + NewLine;
    if (TwitchEdit.Text = '') and (KickEdit.Text = '') and (YoutubeEdit.Text = '') and (CustomServerEdit.Text = '') then
      S := S + Space + 'none yet (add them later by running Setup again)' + NewLine;
  end;
  if not IsUpdate then
  begin
    S := S + 'OBS:' + NewLine + Space + CollectionCombo.Text + NewLine + Space + ProfileCombo.Text + NewLine;
    if ImportObsCheck.Checked then S := S + Space + 'plus everything else from your regular OBS' + NewLine;
  end;
  if ChangingNetwork then
  begin
    S := S + 'Phone connection:' + NewLine + Space;
    if NetworkPage.SelectedValueIndex = 1 then S := S + 'relay server ' + RelayHostEdit.Text + ' (no port forwarding)'
    else S := S + 'home router (ports opened automatically)';
    S := S + NewLine + 'Remote dashboard:' + NewLine + Space;
    case RemotePage.SelectedValueIndex of
      0: S := S + 'https://' + DuckNameEdit.Text + '.duckdns.org';
      1: S := S + 'https://' + DomainEdit.Text;
    else
      S := S + 'only on this PC (http://localhost:8090)';
    end;
    S := S + NewLine;
  end;
  S := S + NewLine + 'Setup downloads OBS Studio (its own copy), go-irl, MediaMTX, NOALBS, Caddy and the multistream plugin' +
    ' (pinned versions, checksum-verified) and sets everything up. This takes a few minutes.';
  Result := S;
end;

// ------------------------------------------------------------------ install
function AnswersJson: String;
var
  I: Integer;
  S, Overlays: String;
begin
  S := '{';
  // Channels: empty = none (skipped), so an update can also remove one.
  if ChangingChannels then
  begin
    if TwitchEdit.Text = '' then S := S + '"TwitchChannel":"none"' else S := S + '"TwitchChannel":' + JsonStr(TwitchEdit.Text);
    if KickEdit.Text = '' then S := S + ',"KickChannel":"none"' else S := S + ',"KickChannel":' + JsonStr(KickEdit.Text);
    if YoutubeEdit.Text = '' then S := S + ',"YoutubeChannelId":"none"' else S := S + ',"YoutubeChannelId":' + JsonStr(YoutubeEdit.Text);
    if CustomServerEdit.Text <> '' then S := S + ',"CustomName":' + JsonStr(Trim(CustomNameEdit.Text)) + ',"CustomServer":' + JsonStr(CustomServerEdit.Text)
    else if InfoValue('prev', 'customServer') <> '' then S := S + ',"CustomServer":"off"';
  end;
  if not IsUpdate then
  begin
    if CollectionCombo.ItemIndex > 0 then S := S + ',"BaseCollection":' + JsonStr(CollectionCombo.Text);
    if ProfileCombo.ItemIndex > 0 then S := S + ',"BaseProfile":' + JsonStr(ProfileCombo.Text);
    if ImportObsCheck.Checked then S := S + ',"ImportObs":true' else S := S + ',"ImportObs":false';
    Overlays := '';
    if not ShouldSkipPage(OverlayPage.ID) then
      for I := 0 to OverlayPage.CheckListBox.Items.Count - 1 do
        if OverlayPage.Values[I] then
        begin
          if Overlays <> '' then Overlays := Overlays + ',';
          Overlays := Overlays + JsonStr(OverlayPage.CheckListBox.ItemCaption[I]);
        end;
    S := S + ',"OverlaySources":[' + Overlays + ']';
    if OptionsPage.Values[0] then S := S + ',"AutoStart":"On"' else S := S + ',"AutoStart":"Off"';
  end;
  if not ShouldSkipPage(LoginPage.ID) then
  begin
    if S <> '{' then S := S + ',';
    S := S + '"DashboardUser":' + JsonStr(Trim(LoginUser.Text));
  end;
  if ChangingNetwork then
  begin
    if S <> '{' then S := S + ',';
    if NetworkPage.SelectedValueIndex = 1 then S := S + '"RelayHost":' + JsonStr(RelayHostEdit.Text) else S := S + '"RelayHost":"off"';
    case RemotePage.SelectedValueIndex of
      0: S := S + ',"Domain":' + JsonStr(DuckNameEdit.Text + '.duckdns.org') + ',"DuckDnsName":' + JsonStr(DuckNameEdit.Text);
      1: S := S + ',"Domain":' + JsonStr(DomainEdit.Text) + ',"DuckDnsName":"off"';
    else
      S := S + ',"Domain":"off","DuckDnsName":"off"';
    end;
  end;
  Result := S + '}';
end;

procedure OnInstallOutput(const S: String; const Error, FirstLine: Boolean);
var
  Step: Integer;
begin
  // The saved log (logs\setup.log, the one people attach to bug reports) never gets the dashboard password.
  if Pos('Password ', TrimLeft(S)) <> 1 then InstallLog.Add(S) else InstallLog.Add('    Password   (not saved in this log)');
  InstallMemo.Lines.Add(S);
  SendMessage(InstallMemo.Handle, EM_LINESCROLL, 0, InstallMemo.Lines.Count);
  // install.ps1 announces each stage as "[n] ..."
  if (Length(S) > 3) and (S[1] = '[') and (S[3] = ']') and (S[2] >= '0') and (S[2] <= '9') then
  begin
    Step := Ord(S[2]) - Ord('0') + 1;
    WizardForm.ProgressGauge.Position := Step * 100 div TotalSteps;
    WizardForm.StatusLabel.Caption := Trim(Copy(S, 4, 200));
  end
  else if Trim(S) <> '' then
    WizardForm.FilenameLabel.Caption := Trim(S);
end;

procedure RunInstall;
var
  Code: Integer;
  Answers: TArrayOfString;
  Params, ResultFile, Dir: String;
begin
  Dir := RemoveBackslashUnlessRoot(WizardDirValue);
  SetArrayLength(Answers, 1);
  Answers[0] := AnswersJson;
  SaveStringsToUTF8File(ExpandConstant('{tmp}\answers.json'), Answers, False);
  ResultFile := ExpandConstant('{tmp}\result.txt');
  // Secrets go in the environment, never on the command line.
  if (not ShouldSkipPage(LoginPage.ID)) and (not LoginGenerate.Checked) then SetEnvironmentVariable('IRLHK_DASHBOARD_PASSWORD', LoginPass.Text);
  if ChangingNetwork and (RemotePage.SelectedValueIndex = 0) and (Trim(DuckTokenEdit.Text) <> '') then SetEnvironmentVariable('IRLHK_DUCKDNS_TOKEN', Trim(DuckTokenEdit.Text));
  SetEnvironmentVariable('IRLHK_RELAY_TOKEN', RelayToken);
  if ChangingChannels and (Trim(CustomKeyEdit.Text) <> '') then SetEnvironmentVariable('IRLHK_CUSTOM_KEY', Trim(CustomKeyEdit.Text));
  if ChangingChannels and TwitchSignedIn and FileExists(ExpandConstant('{tmp}\twitch-auth.json')) then
    SetEnvironmentVariable('IRLHK_TWITCH_AUTH', ExpandConstant('{tmp}\twitch-auth.json'));

  WizardForm.ProgressGauge.Min := 0;
  WizardForm.ProgressGauge.Max := 100;
  WizardForm.ProgressGauge.Position := 2;
  WizardForm.StatusLabel.Caption := 'Installing IRL Homekit...';
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\src\install.ps1') + '" -NonInteractive' +
    ' -InstallDir "' + Dir + '" -AnswersFile "' + ExpandConstant('{tmp}\answers.json') + '" -ResultFile "' + ResultFile + '"';
#ifdef TestInstallDir
  // Test builds: no scheduled tasks, shortcuts, firewall rules, Apps entry or relay tunnel; keep the answers to check.
  Params := Params + ' -SkipSystem';
  FileCopy(ExpandConstant('{tmp}\answers.json'), Dir + '-answers.json', False);
#endif
  InstallOk := ExecAndLogOutput(PowerShellExe, Params, ExpandConstant('{tmp}\src'), SW_HIDE, ewWaitUntilTerminated, Code, @OnInstallOutput) and (Code = 0);

  SetEnvironmentVariable('IRLHK_DASHBOARD_PASSWORD', '');
  SetEnvironmentVariable('IRLHK_DUCKDNS_TOKEN', '');
  SetEnvironmentVariable('IRLHK_RELAY_TOKEN', '');
  SetEnvironmentVariable('IRLHK_CUSTOM_KEY', '');
  // Keep the full output with the app's other logs.
  ForceDirectories(Dir + '\logs');
  InstallLog.SaveToFile(Dir + '\logs\setup.log');
  if InstallOk and FileExists(ResultFile) then ResultLines.LoadFromFile(ResultFile);
  WizardForm.ProgressGauge.Position := 100;
end;

function ResultValue(Key: String): String;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to ResultLines.Count - 1 do
    if Field(ResultLines[I], 0) = Key then begin Result := Field(ResultLines[I], 1); Exit; end;
end;

procedure ShowSummary;
var
  I: Integer;
  S, NL: String;
begin
  NL := #13#10;
  if not InstallOk then
  begin
    S := 'Setup couldn''t finish. Nothing you had before was lost: run Setup again once the problem below is fixed.' + NL + NL +
      'Full log: ' + RemoveBackslashUnlessRoot(WizardDirValue) + '\logs\setup.log' + NL +
      'Help: docs\TROUBLESHOOTING.md, or report it at https://github.com/CursedByJava/irl-homekit/issues (attach the log).' + NL + NL + 'Last lines:' + NL;
    for I := InstallLog.Count - 15 to InstallLog.Count - 1 do
      if I >= 0 then S := S + InstallLog[I] + NL;
    SummaryPage.RichEditViewer.Lines.Text := S;
    MsgBox('Setup couldn''t finish installing IRL Homekit. The next page shows what went wrong.', mbError, MB_OK);
    Exit;
  end;
  DashboardUrl := ResultValue('dashboardUrl');
  if Pos(' ', DashboardUrl) > 0 then DashboardUrl := Copy(DashboardUrl, 1, Pos(' ', DashboardUrl) - 1);
  GuidePath := ResultValue('guide');
  S := 'IRL Homekit ' + ResultValue('version') + ' is installed and opening now.' + NL + NL +
    'DASHBOARD (control the stream from your phone)' + NL +
    '  ' + ResultValue('dashboardUrl') + NL;
  if ResultValue('studioUrl') <> '' then S := S + '  Studio: ' + ResultValue('studioUrl') + NL;
  S := S + '  Username: ' + ResultValue('username') + NL;
  if ResultValue('password') <> '' then S := S + '  Password: ' + ResultValue('password') + '   (made for you: save it in your password manager)' + NL
  else S := S + '  Password: the one you chose' + NL;
  S := S + NL + 'PHONE (IRL Pro / Moblin / BELABOX)' + NL +
    '  Your settings are in ' + GuidePath + NL +
    '  and on the dashboard: Phone settings > Show.' + NL;
  if ResultValue('relayHost') <> '' then
  begin
    S := S + NL + 'RELAY SERVER' + NL + '  ' + ResultValue('relayHost');
    if ResultValue('relayConnected') = 'True' then S := S + ': connected' + NL
    else S := S + ': not connected yet (see below)' + NL;
  end
  else if ResultValue('portMapOk') = 'True' then
    S := S + NL + 'ROUTER' + NL + '  Ports opened automatically: no port forwarding needed.' + NL
  else
  begin
    S := S + NL + 'ROUTER' + NL;
    if (ResultValue('portMapProblem') = 'cgnat') or (ResultValue('portMapProblem') = 'double-nat') then
      S := S + '  Your internet connection can''t take an incoming phone stream as it is (see the note below).' + NL +
        '  The fix: run Setup again and choose the relay server.' + NL
    else
      S := S + '  NEXT: forward UDP 5000 and 8890 (and TCP 80/443 for the remote dashboard) on your router to this PC,' + NL +
        '  or turn on UPnP in the router''s settings. Router steps: docs\ROUTER.md.' + NL +
        '  No access to the router? Run Setup again and choose the relay server.' + NL;
  end;
  for I := 0 to ResultLines.Count - 1 do
    if Field(ResultLines[I], 0) = 'warning' then S := S + NL + 'NOTE: ' + Field(ResultLines[I], 1) + NL;
  S := S + NL + 'Opens by itself when you sign in to Windows: ' + ResultValue('autoStart') + NL +
    'All the tools (Status, Change login, Set up remote dashboard, ...) are in the Start menu under IRL Homekit.' + NL;
  SummaryPage.RichEditViewer.Lines.Text := S;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RunInstall;
    ShowSummary;
  end;
end;
