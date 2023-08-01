unit unitPingHermes;

{$mode objfpc}{$H+}

interface

uses
  {$IFDEF UNIX}
  cthreads,
  {$ENDIF}
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, ExtCtrls,
  LCLType, ActnList, Menus, RichMemo, LResources, pingsend,
  uplaysound,

  // FPC 3.0 fileinfo reads exe resources as long as you register the appropriate units
  fileinfo,
  winpeimagereader, {need this for reading exe info}
  elfreader, {needed for reading ELF executables}
  machoreader {needed for reading MACH-O executables};

type
  TPingThread = class(TThread)
  private
    myPingSend: TPINGSend;
    pResult: boolean;
    procedure updateStatus;
  protected
    procedure Execute; override;
  public
    p_id: integer;
    p_ip: string;
    p_timeout: integer;
    constructor Create(CreateSuspended: boolean);
  end;

type
  TPlayThread = class(TThread)
  protected
    procedure Execute; override;
  public
    audioFile: string;
    constructor Create(CreateSuspended: boolean);
  end;

type

  { TForm1 }

  TForm1 = class(TForm)
    actHelp: TAction;
    actAutoHide: TAction;
    actShowHide: TAction;
    actReReadConfig: TAction;
    actOpenConfigDir: TAction;
    actPing: TAction;
    actSnooze: TAction;
    actQuit: TAction;
    ActionList1: TActionList;
    Button1: TButton;
    mnuAutoHide: TMenuItem;
    Separator1: TMenuItem;
    mnuShowHide: TMenuItem;
    MenuItem10: TMenuItem;
    MenuItem2: TMenuItem;
    mnuShowHideSep: TMenuItem;
    Separator6: TMenuItem;
    Separator5: TMenuItem;
    mnuHearder: TMenuItem;
    MenuItem3: TMenuItem;
    MenuItem4: TMenuItem;
    MenuItem5: TMenuItem;
    MenuItem6: TMenuItem;
    MenuItem9: TMenuItem;
    PopupMenu1: TPopupMenu;
    tmrMute: TTimer;
    tmrLock: TTimer;
    tmrConfirm: TTimer;
    tout: TRichMemo;
    Timer1: TTimer;
    TrayIcon1: TTrayIcon;
    procedure actAutoHideExecute(Sender: TObject);
    procedure actHelpExecute(Sender: TObject);
    procedure actOpenConfigDirExecute(Sender: TObject);
    procedure actPingExecute(Sender: TObject);
    procedure actQuitExecute(Sender: TObject);
    procedure actReReadConfigExecute(Sender: TObject);
    procedure actShowHideExecute(Sender: TObject);
    procedure actSnoozeExecute(Sender: TObject);
    procedure FormClose(Sender: TObject; var CloseAction: TCloseAction);
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure FormMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure FormShow(Sender: TObject);
    procedure Timer1Timer(Sender: TObject);
    procedure tmrConfirmTimer(Sender: TObject);
    procedure tmrLockTimer(Sender: TObject);
    procedure tmrMuteTimer(Sender: TObject);
    procedure toutMouseUp(Sender: TObject; Button: TMouseButton;
      Shift: TShiftState; X, Y: integer);
    procedure TrayIcon1Click(Sender: TObject);
  private
    playsound: Tplaysound;
    can_close, is_lost, show_hide, deleteLockFile, CanMute, ApplicationError,
    PositionRead, AutoHide: boolean;
    lostCounter, entries: integer;
    timeout: integer;
    ConfigFile, ConfigTitle, audioFile, lockFile, help_file, AppConfigDir,
    ProductVersion, ProductName, Title, positionFile, DataDir: string;
    playThreadStarted: boolean;
    FileVerInfo: TFileVersionInfo;
    pingThread: TPingThread;
    playThread: TPlayThread;
    procedure ping;
    procedure CreateMyDir(aDir: string);
    function ExtractResource(rName: string; rFileName: string): boolean;
    procedure createResources(force: boolean);
    procedure getPaths(config: string);
    procedure playAlarm;
    procedure stopPlaying;
    procedure ReadConfig;
    procedure WriteConfig;
    procedure header;
    function ToIntWithCheck(Value: string; default_value, min_value: integer): integer;
    procedure printLine(msg: string; lcolor: TColor);
    function getTitle: string;
    procedure SetCaptions;
    procedure WritePosition;
  public
    ip: string;
    showed_auto: boolean;
    procedure Start(config: string; doCreateResources, hideAutomatically: boolean);
    procedure ReadPosition;
  end;

var
  Form1: TForm1;

implementation

{$R *.lfm}

{ TForm1 }

uses LazFileUtils, LazUTF8, LCLIntf;

procedure TForm1.FormCreate(Sender: TObject);
begin
  CanMute := True;
  deleteLockFile := False;
  FileVerInfo := TFileVersionInfo.Create(nil);
  ProductVersion := 'undefined!';
  try
    begin
      FileVerInfo.ReadFileInfo;
      //writeln('Company: ',FileVerInfo.VersionStrings.Values['CompanyName']);
      //writeln('File description: ',FileVerInfo.VersionStrings.Values['FileDescription']);
      //writeln('File version: ',FileVerInfo.VersionStrings.Values['FileVersion']);
      //writeln('Internal name: ',FileVerInfo.VersionStrings.Values['InternalName']);
      //writeln('Legal copyright: ',FileVerInfo.VersionStrings.Values['LegalCopyright']);
      //writeln('Original filename: ',FileVerInfo.VersionStrings.Values['OriginalFilename']);
      //writeln('Product name: ',FileVerInfo.VersionStrings.Values['ProductName']);
      //writeln('Product version: ',FileVerInfo.VersionStrings.Values['ProductVersion']);
      ProductName := FileVerInfo.VersionStrings.Values['ProductName'];
      ProductVersion := FileVerInfo.VersionStrings.Values['FileVersion'];
    end;
  finally
    FileVerInfo.Free;
  end;
  Title := getTitle;
  SetCaptions;
end;

procedure TForm1.Start(config: string; doCreateResources, hideAutomatically: boolean);
begin
  AutoHide := hideAutomatically;
  mnuAutoHide.Checked := hideAutomatically;
  actAutoHide.Checked := hideAutomatically;
  playsound := Tplaysound.Create(self);
  playsound.PlayStyle := psSync;
  lostCounter := 0;
  playThread := nil;
  playThreadStarted := False;
  getPaths(config);
  if ApplicationError then
    exit;
  ReadConfig;
  header;
  createResources(doCreateResources);
  if ApplicationError then
    exit;
  if not FileExists(ConfigFile) then
    writeConfig;
  showed_auto := False;
  {$IFDEF DARWIN}
  show_hide := True;
  {$ENDIF}
  if show_hide then
  begin
    mnuShowHide.Visible := True;
    mnuShowHideSep.Visible := True;
  end;
  //ReadPosition;
  actPing.Enabled := True;
  ping;
  SetCaptions;
  if (not hideAutomatically) then
    Show;
end;

procedure TForm1.ReadPosition;
var
  tfIn: TextFile;
  s: string;
  A: TStringArray;
  X, Y: integer;
begin
  if FileExists(positionFile) then
  begin
    AssignFile(tfIn, positionFile);
    try
      reset(tfIn);
      while not EOF(tfIn) do
      begin
        readln(tfIn, s);
        if s.IndexOf(',') > -1 then
        begin
          A := s.Split(',');
          try
            X := StrToInt(Trim(A[0]));
            Y := StrToInt(Trim(A[1]));
            if X < Screen.DesktopLeft then
              X := Screen.DesktopLeft + 20;
            if X > Screen.DesktopLeft + Screen.DesktopWidth - Width then
              X := Screen.DesktopLeft + Screen.DesktopWidth - Width - 20;
            if Y < Screen.DesktopTop then
              Y := Screen.DesktopTop + 20;
            if Y > Screen.DesktopTop + Screen.DesktopHeight - Height then
              Y := Screen.DesktopTop + Screen.DesktopHeight - Height - 80;
            Left := X;
            Top := Y;
          finally
          end;
        end;
      end;
    finally
      CloseFile(tfIn);
    end;
  end;
  PositionRead := True;
end;

procedure TForm1.WritePosition;
var
  tfOut: TextFile;
begin
  AssignFile(tfOut, positionFile);
  try
    Rewrite(tfOut);
    writeln(tfOut, IntToStr(Left) + ',' + IntToStr(Top));
    CloseFile(tfOut);
  except
  end;
end;

procedure TForm1.SetCaptions;
begin
  Title := getTitle;
  if is_lost and actSnooze.Checked then
  begin
    Title := Title + '   [ Alarm Muted ]';
  end
  else
  begin
    if is_lost then
      Title := Title + '   [ Alarm ]'
    else
    begin
      if actSnooze.Checked then
        Title := Title + '   [ Muted ]';
    end;
  end;
  if (not AutoHide) then
  begin
    if pos(']', Title) > 0 then
      Title := StringReplace(Title, ']', '   Vis ]', [rfIgnoreCase])
    else
      Title := Title + '   [ Vis ]';
  end;
  Caption := Title;
  mnuHearder.Caption := Title;
  TrayIcon1.Hint := Title;
end;

procedure TForm1.header;
var
  msg: string;
  t_end: integer;
begin
  tout.Text := 'Init';
  tout.Clear;
  msg := ProductName + ' ' + ProductVersion + '   ( ' + ConfigTitle + ' )';
  tout.Lines.Insert(0, msg);
  t_end := Length(msg);
  tout.SetRangeColor(0, t_end, clGreen);
  msg := 'Updating every ' + IntToStr(Round(Timer1.Interval / 1000)) + ' seconds...';
  tout.Lines.Insert(0, msg);
  t_end := Length(msg);
  tout.SetRangeColor(0, t_end, clGreen);
end;

procedure TForm1.FormDestroy(Sender: TObject);
begin
  stopPlaying;
  playsound.Free;

end;

procedure TForm1.FormMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
begin
  toutMouseUp(Sender, Button, Shift, X, Y);
end;

procedure TForm1.FormShow(Sender: TObject);
begin
  if (not PositionRead) then
    ReadPosition;
end;

procedure TForm1.FormClose(Sender: TObject; var CloseAction: TCloseAction);
begin
  if (not AutoHide) then
  begin
    CloseAction := caNone;
    exit;
  end;
  if (not can_close) then
  begin
    TrayIcon1Click(self);
    CloseAction := caNone;
  end
  else
    showed_auto := False;
  WritePosition;
end;

procedure TForm1.stopPlaying;
begin                    
  playsound.StopSound;
  if playThreadStarted then
  begin
    playThread.Terminate;
    playThread.WaitFor;
    playThreadStarted := False;
    playThread := nil;
    SetCaptions;
  end;
  DeleteFile(lockFile);
  deleteLockFile := False;
  playsound.StopSound;
end;

procedure TForm1.ping;
begin
  if (not actPing.Enabled) then
    exit;
  actPing.Enabled := False;
  actReReadConfig.Enabled := False;
  Timer1.Enabled := False;
  pingThread := TPingThread.Create(True);
  pingThread.p_ip := ip;
  pingThread.p_timeout := timeout;
  pingThread.Start;
end;

procedure TForm1.CreateMyDir(aDir: string);
var
  msg: string;
begin
  if not DirectoryExists(aDir) then
  begin
    if not ForceDirectories(aDir) then
    begin
      ApplicationError := True;
      msg := 'Cannot create the directory' + sLineBreak + '        "' +
        aDir + '"' + sLineBreak + sLineBreak +
        'Please make sure that the disk is not full!' + sLineBreak +
        sLineBreak + 'In any case, you should log off or reboot your machine and try again!';
      Application.MessageBox(PChar(msg), PChar(ProductName + ' Error!!!'),
        MB_ICONERROR);
      Close;
      Application.Terminate;
    end;
  end;
end;

function TForm1.getTitle: string;
begin
  Result := ProductName + '   ( ' + ConfigTitle + ' )';
end;

procedure TForm1.getPaths(config: string);
var
  msg: string;
  msgError: integer;
begin
  { Create app config dir }
  AppConfigDir := GetAppConfigDir(False);
  CreateMyDir(AppConfigDir);
  if ApplicationError then
    exit;
  if not AppConfigDir.EndsWith(DirectorySeparator) then
    AppConfigDir := AppConfigDir + DirectorySeparator;
  CreateMyDir(AppConfigDir + 'data');
  CreateMyDir(AppConfigDir + 'help');

  { handle config file }
  ConfigFile := '';
  ConfigTitle := '';
  msg := '';
  msgError := 0;
  if config <> '' then
  begin
    if pos(DirectorySeparator, config) > 0 then
    begin
      msg := 'The configuration file you have specified:' + sLineBreak +
        '        "' + config + '"' + sLineBreak + ' is invalid.' +
        sLineBreak + sLineBreak +
        'Please keep in mind that you only have to specify the filename of an existing or non existing file, without the extension.'
        + sLineBreak + sLineBreak +
        'If the file does not exist, it will be created and populated with default values.'
        + sLineBreak + sLineBreak +
        'Once the program starts, press Ctrl-O to get to the Configuration Directory and edit the file as needed.';
      msgError := 1;
    end;
    ConfigFile := AppConfigDir + config + '.conf';
    ConfigTitle := config;
  end;
  if ConfigFile = '' then
    ConfigFile := AppConfigDir + 'pingHermes.conf';
  DataDir := AppConfigDir + 'data' + DirectorySeparator;
  audioFile := DataDir + 'alarm.wav';
  lockFile := DataDir + '.player.lock';
  help_file := AppConfigDir + 'help' + DirectorySeparator + 'help.html';
  if ConfigTitle = '' then
    ConfigTitle := ExtractFileNameOnly(ConfigFile);
  positionFile := DataDir + '.' + ConfigTitle + '-pos.lock';
  Title := getTitle;
  SetCaptions;
  playsound.SoundFile := audioFile;
  if msgError > 0 then
    if msgError = 1 then
    begin
      ApplicationError := True;
      Application.MessageBox(PChar(msg), PChar(ProductName + ' Error!!!'),
        MB_ICONERROR);
      actOpenConfigDir.Execute;
      Close;
      Application.Terminate;
    end;
end;

procedure TForm1.actQuitExecute(Sender: TObject);
begin
  { prevent new play thread to start }
  actSnooze.Checked := True;
  { stop counters }
  tmrLock.Enabled := False;
  Timer1.Enabled := False;
  tmrConfirm.Enabled := False;

  actPing.Enabled := False;
  can_close := True;
  AutoHide := True;
  Hide;
  stopPlaying;
  Close;
  //Application.Terminate;
end;

procedure TForm1.actReReadConfigExecute(Sender: TObject);
begin
  Timer1.Enabled := False;
  tmrConfirm.Enabled := False;
  stopPlaying;
  is_lost := False;
  lostCounter := 0;
  SetCaptions;
  actSnooze.Checked := False;
  //getPaths(ConfigFile);
  ReadConfig;
  header;
  ping;
  Timer1.Enabled := True;
end;

procedure TForm1.actShowHideExecute(Sender: TObject);
begin
  if Visible then
  begin
    if is_lost = False then
      if (not actAutoHide.Checked) then
        Hide;
  end
  else
  begin
    Show;
    showed_auto := False;
  end;
end;

procedure TForm1.actPingExecute(Sender: TObject);
begin
  can_close := False;
  ping;
end;

procedure TForm1.actOpenConfigDirExecute(Sender: TObject);
begin
  OpenDocument(AppConfigDir);
end;

procedure TForm1.actHelpExecute(Sender: TObject);
begin
  OpenDocument(help_file);
end;

procedure TForm1.actAutoHideExecute(Sender: TObject);
begin
  AutoHide := not AutoHide;
  showed_auto := True;
  mnuAutoHide.Checked := AutoHide;
  actAutoHide.Checked := AutoHide;
  if AutoHide then
    if is_lost then
      Show
    else
      Hide
  else
  begin
    can_close := False;
    Show;
  end;
  SetCaptions;
end;

procedure TForm1.actSnoozeExecute(Sender: TObject);
var
  P: TPoint;
begin
  if (not CanMute) then
    exit;
  actSnooze.Checked := not actSnooze.Checked;
  actSnooze.Enabled := False;
  CanMute := False;
  if actSnooze.Checked then
  begin
    stopPlaying;
    SetCaptions;
    if is_lost then
      printLine('Sound Muted!', clRed)
    else
      printLine('Sound Muted!', clGreen);
  end
  else
  begin
    SetCaptions;
    if is_lost then
    begin
      printLine('Sound Unmuted!', clRed);
      playAlarm;
    end
    else
    begin
      printLine('Sound Unmuted!', clGreen);
    end;
  end;
  P.X := 0;
  P.Y := 0;
  tout.CaretPos := P;
  tmrMute.Enabled := True;
end;

procedure TForm1.Timer1Timer(Sender: TObject);
begin
  can_close := False;
  ping;
end;

procedure TForm1.tmrConfirmTimer(Sender: TObject);
begin
  can_close := False;
  tmrConfirm.Enabled := False;
  ping;
end;

procedure TForm1.tmrLockTimer(Sender: TObject);
begin
  if (not FileExists(lockFile)) then
  begin
    tmrLock.Enabled := False;
    if (not actSnooze.Checked) then
      playAlarm;
  end;
end;

procedure TForm1.tmrMuteTimer(Sender: TObject);
begin
  tmrMute.Enabled := False;
  CanMute := True;
  actSnooze.Enabled := True;
end;

procedure TForm1.toutMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: integer);
var
  P: TPoint;
begin
  if (Button = mbMiddle) and (Shift * [ssShift, ssAlt, ssModifier] = []) then
  begin
    //PopupMenu1.PopUp(Left+X, Top+Y);
    //PopupMenu1.PopUp(Left+TRichMemo(Sender).left+X, Top+TRichMemo(Sender).left+Y);
    P := Mouse.CursorPos;
    PopupMenu1.PopUp(P.X, P.Y);
  end;
end;

procedure TForm1.TrayIcon1Click(Sender: TObject);
begin
  if Visible then
  begin
    if not is_lost then
      if AutoHide then
        Hide;
  end
  else
    Show;
  showed_auto := False;
end;

procedure TForm1.printLine(msg: string; lcolor: TColor);
var
  MyTime: TDateTime;
  t_end: integer;
  dmsg: string;
begin
  MyTime := Now;
  dmsg := FormatDateTime('hh:nn:ss.zzz : ', MyTime) + msg;
  Form1.tout.Lines.Insert(0, dmsg);
  t_end := Length(dmsg);
  Form1.tout.SetRangeColor(0, t_end, lcolor);
end;

procedure TForm1.ReadConfig;
var
  tfIn: TextFile;
  s: string;
  A: TStringArray;
  use_default: boolean;
begin
  use_default := True;
  if FileExists(ConfigFile) then
  begin
    use_default := False;
    AssignFile(tfIn, ConfigFile);
    try
      reset(tfIn);
      while not EOF(tfIn) do
      begin
        readln(tfIn, s);
        if not s.StartsWith('#') then
        begin
          if s.IndexOf('=') > -1 then
          begin
            A := s.Split('=');
            A[0] := Trim(A[0]);
            A[1] := Trim(A[1]);
            case A[0] of
              'IP': ip := A[1];
              'Interval': Timer1.Interval := ToIntWithCheck(A[1], 10, 10) * 1000;
              'Timeout': timeout := ToIntWithCheck(A[1], 1, 1) * 1000;
              'Entries': entries := ToIntWithCheck(A[1], 100, 100);
              else
              begin
              end;
            end;
          end;
        end;
      end;
      CloseFile(tfIn);
    except
      use_default := True;
    end;
  end;
  if use_default then
  begin
    ip := '192.168.130.71';
    Timer1.Interval := 600000;
    timeout := 1000;
    entries := 100;

  end;
end;

function TForm1.ToIntWithCheck(Value: string;
  default_value, min_value: integer): integer;
begin
  try
    Result := StrToInt(Value);
  except
    Result := default_value;
  end;
  if Result < min_value then
    Result := default_value;
end;

procedure TForm1.WriteConfig;
var
  tfOut: TextFile;
begin
  AssignFile(tfOut, ConfigFile);
  try
    Rewrite(tfOut);
    writeln(tfOut, '# The IP to ping');
    writeln(tfOut, 'IP=' + ip);
    writeln(tfOut, '');
    writeln(tfOut, '# The interval in seconds');
    writeln(tfOut, '# ping IP every <Interval> seconds');
    writeln(tfOut, '# Minimum value is 10 seconds');
    writeln(tfOut, 'Interval=' + IntToStr(Round(Int(Timer1.Interval / 1000))));
    writeln(tfOut, '');
    writeln(tfOut, '# ping timeout in seconds');
    writeln(tfOut, '# if ping does not get a reply in <Timeout> seconds,');
    writeln(tfOut, '# the server will be considered down');
    writeln(tfOut, '# Minimum value is 1 second');
    writeln(tfOut, 'Timeout=' + IntToStr(Round(Int(timeout / 1000))));
    writeln(tfOut, '');
    writeln(tfOut, '# number of entries in report list');
    writeln(tfOut, 'Entries=' + IntToStr(entries));
    CloseFile(tfOut);
  except
  end;
end;

function TForm1.ExtractResource(rName: string; rFileName: string): boolean;
var
  Stream1: TLazarusResourceStream;
begin
  Result := False;
  Stream1 := nil;
  try
    Stream1 := TLazarusResourceStream.Create(rName, nil);
    Stream1.SaveToFile(rFileName);
  finally
    Stream1.Free;
  end;
  if FileExists(rFileName) then
    Result := True;
end;

procedure TForm1.createResources(force: boolean);
var
  i: integer;
  msg: string;
  res: boolean;
  files: array [0 .. 11] of string;
begin
  {audio file}
  files[0] := 'HERMES-IS-OFFLINE';
  files[1] := audioFile;
  files[2] := '';
  { help file }
  files[3] := 'help';
  files[4] := help_file;
  files[5] := '';
  { first jpg }
  files[6] := 'pingHermes';
  files[7] := AppConfigDir + 'help' + DirectorySeparator + 'pingHermes.jpg';
  files[8] := '';
  { second jpg }
  files[9] := 'menu';
  files[10] := AppConfigDir + 'help' + DirectorySeparator + 'menu.jpg';
  files[11] := '';
  i := 0;
  while i < Length(files) do
  begin
    if force or (not FileExists(files[i + 1])) then
    begin
      res := ExtractResource(files[i], files[i + 1]);
      if (not res) then
      begin
        ApplicationError := True;
        msg := 'Cannot create the file' + sLineBreak + '        "' +
          files[i + 1] + '"' + sLineBreak + sLineBreak +
          'Please close all opened programs and make sure that the disk is not full!' +
          sLineBreak + sLineBreak +
          'If nothing else works, you should log off or reboot your machine and try again!';
        Application.MessageBox(PChar(msg), PChar(ProductName + ' Error!!!'),
          MB_ICONERROR);
        Close;
        Application.Terminate;
        exit;
      end;
    end;
    i := i + 3;
  end;
end;

procedure TForm1.playAlarm;
var
  tfOut: TextFile;
begin
  SetCaptions;
  if FileExists(lockFile) and (not deleteLockFile) then
  begin
    // someone else is playing the alarm!
    if (not tmrLock.Enabled) then
      tmrLock.Enabled := True;
    exit;
  end;
  if (not playThreadStarted) and (not actSnooze.Checked) then
  begin
    playThread := TPlayThread.Create(True);
    playThread.audioFile := audioFile;
    playThread.Start;
    playThreadStarted := True;
    try
      AssignFile(tfOut, lockFile);
      Rewrite(tfOut);
      CloseFile(tfOut);
      deleteLockFile := True;
    finally
    end;
  end;
end;


constructor TPlayThread.Create(CreateSuspended: boolean);
begin                             
  FreeOnTerminate := True;
  inherited Create(CreateSuspended);
  FreeOnTerminate := True;
end;

procedure TPlayThread.Execute;
var
  i, Count: integer;
begin
  Count := 1;
  while (not Terminated) do
  begin
    if FileExists(audioFile) then
      sleep(200);
    if Terminated then
      exit;
    if Count > 3 then
    begin
      Count := 1;
      for i := 1 to 8 do
      begin
        sleep(200);
        if Terminated then
          exit;
      end;
    end;
    if Terminated then
      exit;
    Synchronize(@Form1.playsound.Execute);
    if Terminated then
      exit;
    Count := Count + 1;
  end;
  if Terminated then
    exit;
end;

constructor TPingThread.Create(CreateSuspended: boolean);
begin
  FreeOnTerminate := True;
  inherited Create(CreateSuspended);
  FreeOnTerminate := True;
end;

procedure TPingThread.updateStatus;
var
  msg: string;
  X: TPoint;
begin
  X.X := 0;
  X.Y := 0;
  Form1.tout.Lines.BeginUpdate;
  try
    if pResult then
    begin
      Form1.is_lost := False;
      msg := Form1.ip + ' - Ping OK';
      if Form1.actSnooze.Checked then
        msg := msg + ' [M]';
      Form1.printLine(msg, clGreen);
      if (not Form1.AutoHide) then
        Form1.Show
      else
      if Form1.showed_auto then
        if (not Form1.actAutoHide.Checked) then
          Form1.Hide;
      Form1.stopPlaying;
      Form1.actSnooze.Checked := False;
      Form1.lostCounter := 0;
    end
    else
    begin
      Form1.is_lost := True;
      msg := Form1.ip + ' - Ping NOT OK';
      if Form1.actSnooze.Checked then
        msg := msg + ' [M]';
      Form1.printLine(msg, clRed);
      if not Form1.Visible then
      begin
        if not Form1.actSnooze.Checked then
          Form1.Show;
        Form1.showed_auto := True;
      end;
      Form1.lostCounter := Form1.lostCounter + 1;
      if Form1.lostCounter = 1 then
      begin
        if Form1.Timer1.Interval > 10000 then
          Form1.tmrConfirm.Enabled := True;
      end
      else
      begin
        if Form1.lostCounter >= 2 then
          Form1.playAlarm;
      end;
    end;
  finally
    //myPingSend.Free;
  end;
  Form1.SetCaptions;
  Form1.Timer1.Enabled := True;
  if Form1.tout.Lines.Count >= Form1.entries then
    Form1.tout.Lines.Delete(Form1.entries);
  Form1.tout.Lines.EndUpdate;
  Form1.tout.Repaint;
  Form1.tout.CaretPos := X;
  Form1.actPing.Enabled := True;
  Form1.actReReadConfig.Enabled := True;
end;

procedure TPingThread.Execute;
begin
  myPingSend := TPINGSend.Create;
  myPingSend.Timeout := p_timeout;
  try
    pResult := myPingSend.Ping(p_ip);
  except
    pResult := False;
  end;
  Synchronize(@updateStatus);
  myPingSend.Free;
end;

initialization
{$I Res.lrs}

end.
