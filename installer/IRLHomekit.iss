; IRL Homekit Setup: a normal Windows setup wizard around install.ps1.
;
; The wizard asks its questions on pages (channels, OBS, overlays, dashboard login, phone connection with the
; optional relay server, remote dashboard), then runs install.ps1 -NonInteractive with those answers and shows its
; progress live. Everything install.ps1 does stays the same, so Setup.exe, the .cmd and the built-in updater all
; install IRL Homekit the same way.
;
; Build (Inno Setup 6.3 or newer):  iscc installer\IRLHomekit.iss          -> installer\Output\IRL-Homekit-Setup-<version>.exe
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
DefaultDirName={code:GetDefaultDir}
DisableWelcomePage=no
DisableDirPage=no
DirExistsWarning=no
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
WizardStyle=modern
SetupIconFile=..\dashboard\public\icon.ico
OutputDir=Output
OutputBaseFilename=IRL-Homekit-Setup-{#AppVersion}
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
Source: "..\*"; Excludes: ".git,.github,\installer\Output,\docs\images"; DestDir: "{tmp}\src"; Flags: recursesubdirs createallsubdirs ignoreversion
; Needed before the pages are shown.
Source: "Get-SetupInfo.ps1"; Flags: dontcopy
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
  ChannelsPage: TInputQueryWizardPage;
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
  OptionsPage: TInputOptionWizardPage;
  InstallMemo: TNewMemo;
  SummaryPage: TOutputMsgMemoWizardPage;

function SetEnvironmentVariable(lpName, lpValue: String): Boolean;
  external 'SetEnvironmentVariableW@kernel32.dll stdcall';

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

// ------------------------------------------------------------------ install folder
function GetDefaultDir(Param: String): String;
begin
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

  ChannelsPage := CreateInputQueryPage(wpSelectDir, 'Your channels',
    'Where you stream.', 'Twitch is used for chat commands (!start, !stop) and the dashboard. Kick and YouTube are optional; you can add their stream keys in OBS later.');
  ChannelsPage.Add('Twitch channel name:', False);
  ChannelsPage.Add('Kick channel name (leave empty if you don''t stream on Kick):', False);
  ChannelsPage.Add('YouTube channel ID, starts with UC (optional):', False);

  // Your regular OBS: what to start from.
  ObsPage := CreateCustomPage(ChannelsPage.ID, 'Your OBS', 'IRL Homekit runs its own copy of OBS. Choose what it starts with.');
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
  NetworkPage.Add('Router port forwarding: I can forward ports on my home router (free, fastest; steps in PHONE-SETUP.md and docs\ROUTER.md)');
  NetworkPage.Add('No port forwarding: use a free relay server (Oracle Cloud, about 15 minutes to set up; also hides your home IP)');
  NetworkPage.SelectedValueIndex := 0;

  RelayPage := CreateCustomPage(NetworkPage.ID, 'Relay server', 'Set up your free relay on Oracle Cloud, then enter its address.');
  L := NewLabel(RelayPage, 0,
    '1. Create a free Oracle Cloud account and a VM: Ubuntu image, Always Free shape (step by step: the guide button).' + #13#10 +
    '2. Under Advanced options > Management > Initialization script, paste this setup script (it holds your relay password: keep it private).' + #13#10 +
    '3. In the VM''s security list, open UDP 5000, 8890, 7000 and TCP 1935, 7000, 80, 443.' + #13#10 +
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
  L.Caption := 'On duckdns.org: sign in (GitHub, Google, Reddit or X), type a name under "sub domain" and press "add domain". Then copy the token shown at the top of the page.';
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

function ShouldSkipPage(PageID: Integer): Boolean;
var
  I: Integer;
  HasOverlay: Boolean;
begin
  Result := False;
  if PageID = wpWelcome then Result := IsUpdate   // the update page says it all
  else if PageID = UpdatePage.ID then Result := not IsUpdate
  else if (PageID = wpSelectDir) or (PageID = ChannelsPage.ID) or (PageID = OptionsPage.ID) then Result := IsUpdate
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
    if LoginUser.Text = '' then LoginUser.Text := Lowercase(Trim(ChannelsPage.Values[0]));
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
    S := Trim(ChannelsPage.Values[0]);
    if not OnlyChars(Lowercase(S), 'abcdefghijklmnopqrstuvwxyz0123456789_') then
    begin
      MsgBox('Enter your Twitch channel name (letters, numbers and _ only, without twitch.tv/).', mbError, MB_OK); Result := False; Exit;
    end;
    S := Trim(ChannelsPage.Values[2]);
    if (S <> '') and ((Copy(S, 1, 2) <> 'UC') or (Length(S) <> 24)) then
    begin
      MsgBox('A YouTube channel ID starts with UC and is 24 characters long (YouTube Studio > Settings > Channel > Advanced settings). Or leave it empty.', mbError, MB_OK); Result := False; Exit;
    end;
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
      if (Length(S) <> 36) or not OnlyChars(Lowercase(S), '0123456789abcdef-') then
      begin
        MsgBox('That doesn''t look like a DuckDNS token (36 letters and numbers with dashes, shown at the top of duckdns.org once you''re signed in).', mbError, MB_OK); Result := False; Exit;
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
  else
  begin
    S := MemoDirInfo + NewLine + NewLine + 'Twitch:' + NewLine + Space + Trim(ChannelsPage.Values[0]) + NewLine;
    if Trim(ChannelsPage.Values[1]) <> '' then S := S + 'Kick:' + NewLine + Space + Trim(ChannelsPage.Values[1]) + NewLine;
    if Trim(ChannelsPage.Values[2]) <> '' then S := S + 'YouTube:' + NewLine + Space + Trim(ChannelsPage.Values[2]) + NewLine;
    S := S + 'OBS:' + NewLine + Space + CollectionCombo.Text + NewLine + Space + ProfileCombo.Text + NewLine;
    if ImportObsCheck.Checked then S := S + Space + 'plus everything else from your regular OBS' + NewLine;
  end;
  if ChangingNetwork then
  begin
    S := S + 'Phone connection:' + NewLine + Space;
    if NetworkPage.SelectedValueIndex = 1 then S := S + 'relay server ' + RelayHostEdit.Text + ' (no port forwarding)'
    else S := S + 'router port forwarding';
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
  if not IsUpdate then
  begin
    S := S + '"TwitchChannel":' + JsonStr(Trim(ChannelsPage.Values[0]));
    if Trim(ChannelsPage.Values[1]) = '' then S := S + ',"KickChannel":"none"' else S := S + ',"KickChannel":' + JsonStr(Trim(ChannelsPage.Values[1]));
    S := S + ',"YoutubeChannelId":' + JsonStr(Trim(ChannelsPage.Values[2]));
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

  WizardForm.ProgressGauge.Min := 0;
  WizardForm.ProgressGauge.Max := 100;
  WizardForm.ProgressGauge.Position := 2;
  WizardForm.StatusLabel.Caption := 'Installing IRL Homekit...';
  Params := '-NoProfile -ExecutionPolicy Bypass -File "' + ExpandConstant('{tmp}\src\install.ps1') + '" -NonInteractive' +
    ' -InstallDir "' + Dir + '" -AnswersFile "' + ExpandConstant('{tmp}\answers.json') + '" -ResultFile "' + ResultFile + '"';
  InstallOk := ExecAndLogOutput(PowerShellExe, Params, ExpandConstant('{tmp}\src'), SW_HIDE, ewWaitUntilTerminated, Code, @OnInstallOutput) and (Code = 0);

  SetEnvironmentVariable('IRLHK_DASHBOARD_PASSWORD', '');
  SetEnvironmentVariable('IRLHK_DUCKDNS_TOKEN', '');
  SetEnvironmentVariable('IRLHK_RELAY_TOKEN', '');
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
  else
    S := S + NL + 'NEXT: forward UDP 5000 and 8890 (and TCP 80/443 for the remote dashboard) on your router to this PC.' + NL +
      '  Router steps: docs\ROUTER.md. No access to the router? Run Setup again and choose the relay server.' + NL;
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
