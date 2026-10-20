program PIDExplainer;

{$mode objfpc}{$H+}

uses
  {$IFDEF UNIX}cthreads,{$ENDIF}
  Interfaces, Forms, Classes, SysUtils, BGRABitmap, BGRABitmapTypes,
  PIDCore, BGRAView, PlotViews, HeatmapView, CaptureKit,
  uPlatform, uDrawKit, uSimKit, uScenarios, uLessons, uExplainer, uExplainerForm;

{$R *.res}

{ Headless render of every page (no OpenGL needed):
    PIDExplainer.exe --snapshot <folder> [seconds]
  Each page is simulated for [seconds] (default 8) at 60 fps, then saved
  as page_01.png ... page_12.png
  Headless GIF of one page:
    PIDExplainer.exe --gif <file.gif> <page 1..12> [seconds] }

{ Frame cost per page, written to a text file:
    PIDExplainer.exe --bench <file.txt> }
function HeadlessBench: Boolean;
const
  Warm = 60;
  Frames = 180;
var
  Ex: TExplainer;
  Bmp: TBGRABitmap;
  Log: TStringList;
  I, F: Integer;
  T0, TUpd, TRen: Double;
begin
  Result := (ParamCount >= 2) and (ParamStr(1) = '--bench');
  if not Result then
    Exit;
  Ex := TExplainer.Create;
  Bmp := TBGRABitmap.Create(CanvasW, CanvasH);
  Log := TStringList.Create;
  try
    Ex.ShowFps := False;
    Log.Add('page  update  render   [ms per frame, 16.7 ms = one 60 Hz frame]');
    for I := 0 to Ex.PageCount - 1 do
    begin
      Ex.SetPage(I);
      for F := 1 to Warm do
      begin
        Ex.Update(1 / 60);
        Ex.Render(Bmp);
      end;
      TUpd := 0;
      TRen := 0;
      for F := 1 to Frames do
      begin
        T0 := NowSeconds;
        Ex.Update(1 / 60);
        TUpd := TUpd + NowSeconds - T0;
        T0 := NowSeconds;
        Ex.Render(Bmp);
        TRen := TRen + NowSeconds - T0;
      end;
      Log.Add(Format('%4d  %6.2f  %6.2f',
        [I + 1, TUpd / Frames * 1000, TRen / Frames * 1000]));
    end;
    Log.SaveToFile(ParamStr(2));
  finally
    Log.Free;
    Bmp.Free;
    Ex.Free;
  end;
end;

function HeadlessGif: Boolean;
var
  Ex: TExplainer;
  Bmp: TBGRABitmap;
  Rec: TGifRecorder;
  F, Frames: Integer;
begin
  Result := (ParamCount >= 3) and (ParamStr(1) = '--gif');
  if not Result then
    Exit;
  Frames := Round(StrToFloatDef(ParamStr(4), 6) * 60);
  Ex := TExplainer.Create;
  Bmp := TBGRABitmap.Create(CanvasW, CanvasH);
  Rec := TGifRecorder.Create(ParamStr(2), GifScale, 3600);
  Rec.Realtime := False; // offline: never merge frames
  try
    Ex.ShowFps := False;
    Ex.SetPage(StrToIntDef(ParamStr(3), 1) - 1);
    for F := 0 to Frames - 1 do
    begin
      Ex.Update(1 / 60);
      if F mod (60 div GifFps) = 0 then
      begin
        Ex.Render(Bmp);
        Rec.AddFrame(Bmp, 1000 div GifFps);
      end;
    end;
    Rec.Finish;
  finally
    Rec.Free;
    Bmp.Free;
    Ex.Free;
  end;
end;

function HeadlessSnapshot: Boolean;
var
  Ex: TExplainer;
  Bmp: TBGRABitmap;
  Dir: string;
  Seconds: Double;
  I, F: Integer;
begin
  Result := (ParamCount >= 2) and (ParamStr(1) = '--snapshot');
  if not Result then
    Exit;
  Dir := IncludeTrailingPathDelimiter(ParamStr(2));
  ForceDirectories(Dir);
  Seconds := 8;
  if ParamCount >= 3 then
    Seconds := StrToFloatDef(ParamStr(3), 8);
  Ex := TExplainer.Create;
  Bmp := TBGRABitmap.Create(CanvasW, CanvasH);
  try
    Ex.ShowFps := False;
    for I := 0 to Ex.PageCount - 1 do
    begin
      Ex.SetPage(I);
      for F := 1 to Round(Seconds * 60) do
        Ex.Update(1 / 60);
      Ex.Render(Bmp);
      Bmp.SaveToFile(Dir + Format('page_%.2d.png', [I + 1]));
    end;
  finally
    Bmp.Free;
    Ex.Free;
  end;
end;

begin
  RequireDerivedFormResource := False;
  Application.Scaled := True;
  Application.Title := APP_NAME;
  Application.Initialize;
  if HeadlessSnapshot or HeadlessGif or HeadlessBench then
    Exit;
  Application.CreateForm(TExplainerForm, ExplainerForm);
  Application.Run;
end.
