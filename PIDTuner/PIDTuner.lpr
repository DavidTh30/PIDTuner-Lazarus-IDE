program PIDTuner;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, SysUtils,
  PIDCore, BGRAView, KnobControl, HeatmapView, PlotViews, FlatButton, CaptureKit,
  uMainForm;

{$R *.res}

{ Headless render of the whole window:
    PIDTuner.exe --snapshot out.png [Kp Ki Kd]
    PIDTuner.exe --gif out.gif [frames]      Ki sweep demo, 100 ms per frame }

function HeadlessSnapshot: Boolean;
var
  F: TMainForm;
begin
  Result := (ParamCount >= 2) and ((ParamStr(1) = '--snapshot') or (ParamStr(1) = '--gif'));
  if not Result then
    Exit;
  F := TMainForm.Create(nil);
  try
    if ParamStr(1) = '--gif' then
      F.SaveDemoGif(ParamStr(2), StrToIntDef(ParamStr(3), 40))
    else
    begin
      if ParamCount >= 5 then
        F.SetGains(StrToFloat(ParamStr(3)), StrToFloat(ParamStr(4)), StrToFloat(ParamStr(5)));
      F.SaveSnapshot(ParamStr(2));
    end;
  finally
    F.Free;
  end;
end;

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := APP_NAME;
  Application.Initialize;
  if HeadlessSnapshot then
    Exit;
  Application.CreateForm(TMainForm, MainForm);
  Application.Run;
end.
