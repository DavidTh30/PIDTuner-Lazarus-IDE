{ PID Tuning Explorer - main window: equation, Kp/Ki/Kd knobs, Kp x Kd heatmap
  (Ki fixed by its knob) and the step response of the current gains. }
unit uMainForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, StdCtrls, ExtCtrls, LCLType,
  BGRABitmap, BGRABitmapTypes,
  PIDCore, BGRAView, KnobControl, HeatmapView, PlotViews, FlatButton, CaptureKit;

const
  APP_NAME = 'PID Tuning Explorer';
  GridCols = 10;
  GridRows = 8;
  KpMin = 0.5;
  KpMax = 12.0;
  KiMin = 0.0;
  KiMax = 6.0;
  KdMin = 0.0;
  KdMax = 7.0;
  SimTime = 10.0;
  GifFps = 12;
  GifScale = 0.5;
  GifMaxSeconds = 60;

type

  { TMainForm }

  TMainForm = class(TForm)
  private
    FEquation: TEquationView;
    FKnobKp, FKnobKi, FKnobKd: TKnob;
    FHeat: THeatmap;
    FPlot: TResponsePlot;
    FStatus: TLabel;
    FCapInfo: TLabel;
    FBtnPng, FBtnGif: TFlatButton;
    FRecorder: TGifRecorder;
    FRecTimer: TTimer;
    FRecLast: QWord;
    FPlant: TPlant;
    FGrid: TScoreGrid;
    FUpdating: Boolean;
    function MakeKnob(const Sub: string; Accent: LongWord; AMin, AMax, AValue: Double): TKnob;
    function CellKp(Col: Integer): Double;
    function CellKd(Row: Integer): Double;
    procedure KnobChange(Sender: TObject);
    procedure HeatSelect(Sender: TObject; Col, Row: Integer);
    procedure HeatHover(Sender: TObject; Col, Row: Integer);
    procedure FormResize(Sender: TObject);
    procedure RecomputeGrid;
    procedure SyncSelection;
    procedure UpdateResponse;
    procedure BtnPngClick(Sender: TObject);
    procedure BtnGifClick(Sender: TObject);
    procedure RecTick(Sender: TObject);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure StopRecording;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
    procedure SetGains(Kp, Ki, Kd: Double);
    { Composite of every view (without the capture buttons) at full size }
    function RenderFrame: TBGRABitmap;
    procedure SaveSnapshot(const AFileName: string);
    procedure CapturePng;
    procedure StartRecording;
    { Headless demo: Ki sweeps 0 -> max -> 0, heatmap and response follow }
    procedure SaveDemoGif(const AFileName: string; Frames: Integer);
  end;

var
  MainForm: TMainForm;

implementation

const
  StatusHint = 'Drag a knob vertically (Shift = fine) or click the heatmap to pick Kp / Kd';
  CaptureHint = 'Ctrl+S = PNG    Ctrl+G = record GIF';

{ TMainForm }

constructor TMainForm.Create(TheOwner: TComponent);
begin
  { No .lfm: build the UI in code }
  inherited CreateNew(TheOwner);
  Caption := APP_NAME;
  Color := HexColor(ClrBackground);
  DoubleBuffered := True;
  Position := poScreenCenter;
  ClientWidth := 1000;
  ClientHeight := Min(880, Screen.WorkAreaHeight - 60);
  Constraints.MinWidth := 820;
  Constraints.MinHeight := 700;

  FPlant := DefaultPlant;

  FEquation := TEquationView.Create(Self);
  FEquation.Parent := Self;

  FKnobKp := MakeKnob('p', ClrKp, KpMin, KpMax, 4.0);
  FKnobKi := MakeKnob('i', ClrKi, KiMin, KiMax, 2.0);
  FKnobKd := MakeKnob('d', ClrKd, KdMin, KdMax, 3.0);

  FHeat := THeatmap.Create(Self);
  FHeat.Parent := Self;
  FHeat.OnSelect := @HeatSelect;
  FHeat.OnHover := @HeatHover;

  FPlot := TResponsePlot.Create(Self);
  FPlot.Parent := Self;

  FStatus := TLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.Font.Color := RGBToColor(150, 158, 170);
  FStatus.Font.Height := -14;
  FStatus.Caption := StatusHint;

  FCapInfo := TLabel.Create(Self);
  FCapInfo.Parent := Self;
  FCapInfo.AutoSize := False;
  FCapInfo.Alignment := taRightJustify;
  FCapInfo.Font.Color := RGBToColor(150, 158, 170);
  FCapInfo.Font.Height := -14;
  FCapInfo.Caption := CaptureHint;

  FBtnPng := TFlatButton.Create(Self);
  FBtnPng.Parent := Self;
  FBtnPng.Icon := biCamera;
  FBtnPng.Text := 'PNG';
  FBtnPng.Hint := 'Save a PNG of the window (Ctrl+S)';
  FBtnPng.ShowHint := True;
  FBtnPng.OnClick := @BtnPngClick;

  FBtnGif := TFlatButton.Create(Self);
  FBtnGif.Parent := Self;
  FBtnGif.Icon := biRecord;
  FBtnGif.Text := 'GIF';
  FBtnGif.Hint := 'Start / stop recording an animated GIF (Ctrl+G)';
  FBtnGif.ShowHint := True;
  FBtnGif.OnClick := @BtnGifClick;

  FRecTimer := TTimer.Create(Self);
  FRecTimer.Enabled := False;
  FRecTimer.Interval := 1000 div GifFps;
  FRecTimer.OnTimer := @RecTick;

  KeyPreview := True;
  OnKeyDown := @FormKeyDown;
  OnResize := @FormResize;
  RecomputeGrid;
  SyncSelection;
  UpdateResponse;
  FormResize(nil);
end;

destructor TMainForm.Destroy;
begin
  FRecorder.Free;
  inherited Destroy;
end;

function TMainForm.MakeKnob(const Sub: string; Accent: LongWord;
  AMin, AMax, AValue: Double): TKnob;
begin
  Result := TKnob.Create(Self);
  Result.Parent := Self;
  Result.Symbol := 'K';
  Result.SubSymbol := Sub;
  Result.Accent := Accent;
  Result.SetRange(AMin, AMax);
  Result.Value := AValue;
  Result.OnChange := @KnobChange;
end;

function TMainForm.CellKp(Col: Integer): Double;
begin
  Result := KpMin + (KpMax - KpMin) * Col / (GridCols - 1);
end;

function TMainForm.CellKd(Row: Integer): Double;
begin
  Result := KdMin + (KdMax - KdMin) * Row / (GridRows - 1);
end;

procedure TMainForm.FormResize(Sender: TObject);
const
  M = 16;
  EqH = 130;
  KS = 150;
  KLabel = 26;
var
  Y, H, HW: Integer;

  procedure PlaceKnob(K: TKnob; Term: Integer);
  begin
    K.SetBounds(Round(FEquation.TermCenter(Term) - KS / 2), EqH + 4, KS, KS + KLabel);
  end;

begin
  FEquation.SetBounds(0, 8, ClientWidth, EqH);
  PlaceKnob(FKnobKp, 0);
  PlaceKnob(FKnobKi, 1);
  PlaceKnob(FKnobKd, 2);
  Y := EqH + 4 + KS + KLabel + 16;
  H := ClientHeight - Y - 36;
  HW := Round((ClientWidth - 3 * M) * 0.6);
  FHeat.SetBounds(M, Y, HW, H);
  FPlot.SetBounds(2 * M + HW, Y, ClientWidth - 3 * M - HW, H);
  FStatus.SetBounds(M, ClientHeight - 26, ClientWidth - 2 * M - 360, 20);
  FCapInfo.SetBounds(ClientWidth - M - 420, ClientHeight - 26, 420, 20);
  FBtnGif.SetBounds(ClientWidth - M - 96, 12, 96, 34);
  FBtnPng.SetBounds(ClientWidth - M - 96 - 8 - 96, 12, 96, 34);
end;

procedure TMainForm.RecomputeGrid;
begin
  FGrid := SweepKpKd(FKnobKi.Value, KpMin, KpMax, KdMin, KdMax,
    GridCols, GridRows, FPlant);
  FHeat.SetGrid(FGrid);
end;

procedure TMainForm.SyncSelection;
begin
  FHeat.Select(
    Round((FKnobKp.Value - KpMin) / (KpMax - KpMin) * (GridCols - 1)),
    Round((FKnobKd.Value - KdMin) / (KdMax - KdMin) * (GridRows - 1)));
end;

procedure TMainForm.UpdateResponse;
var
  G: TPIDGains;
begin
  G := Gains(FKnobKp.Value, FKnobKi.Value, FKnobKd.Value);
  FPlot.SetResponse(StepResponse(G, FPlant, SimTime, 400), SimTime,
    SimulateStep(G, FPlant, SimTime));
end;

procedure TMainForm.KnobChange(Sender: TObject);
begin
  if FUpdating then
    Exit;
  if Sender = FKnobKi then
    RecomputeGrid;
  SyncSelection;
  UpdateResponse;
end;

procedure TMainForm.HeatSelect(Sender: TObject; Col, Row: Integer);
begin
  FUpdating := True;
  try
    FKnobKp.Value := CellKp(Col);
    FKnobKd.Value := CellKd(Row);
  finally
    FUpdating := False;
  end;
  UpdateResponse;
end;

procedure TMainForm.HeatHover(Sender: TObject; Col, Row: Integer);
begin
  if (Col < 0) or (Row < 0) then
    FStatus.Caption := StatusHint
  else
    FStatus.Caption := Format('Kp = %.2f    Kd = %.2f    Ki = %.2f    score = %.0f%%',
      [CellKp(Col), CellKd(Row), FKnobKi.Value, FGrid[Col, Row] * 100]);
end;

procedure TMainForm.SetGains(Kp, Ki, Kd: Double);
begin
  FUpdating := True;
  try
    FKnobKp.Value := Kp;
    FKnobKi.Value := Ki;
    FKnobKd.Value := Kd;
  finally
    FUpdating := False;
  end;
  RecomputeGrid;
  SyncSelection;
  UpdateResponse;
end;

function TMainForm.RenderFrame: TBGRABitmap;
var
  Part: TBGRABitmap;
  I: Integer;
  C: TControl;
begin
  Result := TBGRABitmap.Create(ClientWidth, ClientHeight, HexPixel(ClrBackground));
  for I := 0 to ControlCount - 1 do
    if (Controls[I] is TBGRAView) and not (Controls[I] is TFlatButton) then
    begin
      C := Controls[I];
      Part := TBGRABitmap.Create(C.Width, C.Height, HexPixel(ClrBackground));
      try
        TBGRAView(C).Render(Part);
        Result.PutImage(C.Left, C.Top, Part, dmSet);
      finally
        Part.Free;
      end;
    end;
end;

procedure TMainForm.SaveSnapshot(const AFileName: string);
var
  Bmp: TBGRABitmap;
begin
  FormResize(nil);
  Bmp := RenderFrame;
  try
    Bmp.SaveToFile(AFileName);
  finally
    Bmp.Free;
  end;
end;

procedure TMainForm.CapturePng;
var
  FileName: string;
begin
  FileName := CaptureFileName('.png');
  SaveSnapshot(FileName);
  FCapInfo.Caption := 'Saved ' + ExtractFileName(FileName);
end;

procedure TMainForm.StartRecording;
begin
  if FRecorder <> nil then
    Exit;
  FRecorder := TGifRecorder.Create(CaptureFileName('.gif'), GifScale, GifMaxSeconds);
  FRecLast := GetTickCount64;
  FBtnGif.Active := True;
  FBtnGif.Text := 'Stop';
  FRecTimer.Enabled := True;
  RecTick(nil);
end;

procedure TMainForm.RecTick(Sender: TObject);
var
  Bmp: TBGRABitmap;
  Now64: QWord;
begin
  if FRecorder = nil then
    Exit;
  Now64 := GetTickCount64;
  Bmp := RenderFrame;
  try
    // the delay of a frame is the time until the next one is taken
    FRecorder.AddFrame(Bmp, Max(1, Integer(Now64 - FRecLast)));
  finally
    Bmp.Free;
  end;
  FRecLast := Now64;
  FCapInfo.Caption := Format('REC %.1f / %d s   (%d frames)   Ctrl+G = stop',
    [FRecorder.Seconds, GifMaxSeconds, FRecorder.FrameCount]);
  if FRecorder.Full or FRecorder.Failed then
    StopRecording;
end;

procedure TMainForm.StopRecording;
var
  N: Integer;
begin
  if FRecorder = nil then
    Exit;
  FRecTimer.Enabled := False;
  FBtnGif.Active := False;
  FBtnGif.Text := 'GIF';
  try
    try
      N := FRecorder.Finish;
      FCapInfo.Caption := Format('Saved %s  (%d frames, %.1f s)',
        [ExtractFileName(FRecorder.FileName), N, FRecorder.Seconds]);
    except
      on E: Exception do
        FCapInfo.Caption := 'GIF failed: ' + E.Message;
    end;
  finally
    FreeAndNil(FRecorder);
  end;
end;

procedure TMainForm.BtnPngClick(Sender: TObject);
begin
  CapturePng;
end;

procedure TMainForm.BtnGifClick(Sender: TObject);
begin
  if FRecorder = nil then
    StartRecording
  else
    StopRecording;
end;

procedure TMainForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if not (ssCtrl in Shift) then
    Exit;
  case Key of
    VK_S: CapturePng;
    VK_G: BtnGifClick(nil);
  else
    Exit;
  end;
  Key := 0;
end;

procedure TMainForm.SaveDemoGif(const AFileName: string; Frames: Integer);
var
  Rec: TGifRecorder;
  Bmp: TBGRABitmap;
  I: Integer;
  Kp, Kd: Double;
begin
  FormResize(nil);
  Kp := FKnobKp.Value;
  Kd := FKnobKd.Value;
  Rec := TGifRecorder.Create(AFileName, GifScale, 3600);
  Rec.Realtime := False; // offline: never merge frames
  try
    for I := 0 to Frames - 1 do
    begin
      SetGains(Kp, KiMax * Sin(Pi * I / Max(1, Frames - 1)), Kd);
      Bmp := RenderFrame;
      try
        Rec.AddFrame(Bmp, 100);
      finally
        Bmp.Free;
      end;
    end;
    Rec.Finish;
  finally
    Rec.Free;
  end;
end;

end.
