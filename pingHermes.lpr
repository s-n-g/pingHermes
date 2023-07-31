program pingHermes;

{$mode objfpc}{$H+}

uses {$IFDEF UNIX}
  cthreads, {$ENDIF} {$IFDEF HASAMIGA}
  athreads, {$ENDIF}
  Interfaces, // this includes the LCL widgetset
  Forms,
  unitPingHermes,
  uplaysound { you can add units after this };

{$R *.res}

var
  i: integer;
  config: string;
  hideAutomatically, crResources: boolean;
begin
  i := 1;
  config := '';
  crResources := False;
  hideAutomatically := True;
  while i <= ParamCount do
  begin
    if (ParamStr(i) = '-cr') or (ParamStr(i) = '--create-resources') then
    begin
      crResources := True;
    end
    else if (ParamStr(i) = '-c') or (ParamStr(i) = '--config') then
    begin
      Inc(i);
      config := ParamStr(i);
    end
    else if (ParamStr(i) = '-a') or (ParamStr(i) = '--always-on') then
    begin
      hideAutomatically := False;
    end;
    Inc(i);
  end;
  RequireDerivedFormResource := True;
  Application.Scaled := True;
  Application.Initialize;
  Application.ShowMainForm := False;
  Application.CreateForm(TForm1, Form1);       
  Form1.Start(config, crResources, hideAutomatically);
  //if (not Form1.ApplicationError) then
  Application.Run;
end.
