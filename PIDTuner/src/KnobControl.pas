unit KnobControl;

{ TKnob - 270 degree rotary dial in the style of the reference video:
  grey track + coloured value arc, dark face with coloured rim, white needle.
  Drag vertically to change (Shift = fine), mouse wheel steps 1%. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore;

type
  TKnob = class(TBGRAView)
  private
    FMinValue, FMaxValue, FValue: Double;
    FAccent: LongWord;
    FSymbol, FSubSymbol: string;
    FDecimals: Integer;
    FDragging: Boolean;
    FDragY: Integer;
    FDragValue: Double;
    FOnChange: TNotifyEvent;
    function GetPosition: Double;
    procedure SetValue(AValue: Double);
    procedure SetAccent(AValue: LongWord);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetRange(AMin, AMax: Double);
    procedure Render(ABmp: TBGRABitmap); override;
    property MinValue: Double read FMinValue;
    property MaxValue: Double read FMaxValue;
    property Value: Double read FValue write SetValue;
    property Position: Double read GetPosition; // 0..1
    property Accent: LongWord read FAccent write SetAccent;
    property Symbol: string read FSymbol write FSymbol;
    property SubSymbol: string read FSubSymbol write FSubSymbol;
    property Decimals: Integer read FDecimals write FDecimals;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
  end;

implementation

const
  StartDeg = 225; // bottom-left, value 0
  SweepDeg = 270; // clockwise to bottom-right
  LabelH = 26;

function ArcPoints(CX, CY, R, T0, T1: Single): ArrayOfTPointF;
var
  I, N: Integer;
  A: Single;
begin
  N := Max(2, Round(96 * (T1 - T0)) + 1);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    A := DegToRad(StartDeg - SweepDeg * (T0 + (T1 - T0) * I / (N - 1)));
    Result[I] := PointF(CX + R * Cos(A), CY - R * Sin(A));
  end;
end;

{ TKnob }

constructor TKnob.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse];
  Cursor := crSizeNS;
  FMinValue := 0;
  FMaxValue := 1;
  FAccent := ClrKp;
  FDecimals := 2;
end;

function TKnob.GetPosition: Double;
begin
  if FMaxValue > FMinValue then
    Result := (FValue - FMinValue) / (FMaxValue - FMinValue)
  else
    Result := 0;
end;

procedure TKnob.SetValue(AValue: Double);
begin
  AValue := EnsureRange(AValue, FMinValue, FMaxValue);
  if AValue = FValue then
    Exit;
  FValue := AValue;
  Invalidate;
  if Assigned(FOnChange) then
    FOnChange(Self);
end;

procedure TKnob.SetAccent(AValue: LongWord);
begin
  FAccent := AValue;
  Invalidate;
end;

procedure TKnob.SetRange(AMin, AMax: Double);
begin
  FMinValue := AMin;
  FMaxValue := AMax;
  FValue := EnsureRange(FValue, AMin, AMax);
  Invalidate;
end;

procedure TKnob.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    FDragging := True;
    FDragY := Y;
    FDragValue := FValue;
  end;
end;

procedure TKnob.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  PixelsPerRange: Double;
begin
  inherited MouseMove(Shift, X, Y);
  if not FDragging then
    Exit;
  if ssShift in Shift then
    PixelsPerRange := 1000
  else
    PixelsPerRange := 200;
  Value := FDragValue + (FDragY - Y) / PixelsPerRange * (FMaxValue - FMinValue);
end;

procedure TKnob.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
    FDragging := False;
end;

function TKnob.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if not Result then
  begin
    Value := FValue + Sign(WheelDelta) * (FMaxValue - FMinValue) * 0.01;
    Result := True;
  end;
end;

procedure TKnob.Render(ABmp: TBGRABitmap);
var
  CX, CY, R, TrackW, RTrack, RFace, A, W1, W2, X: Single;
  Pos: Double;
  AccentPx: TBGRAPixel;
  ValueText: string;
begin
  CX := ABmp.Width / 2;
  CY := (ABmp.Height - LabelH) / 2;
  R := Min(ABmp.Width, ABmp.Height - LabelH) / 2 - 4;
  if R <= 4 then
    Exit;
  Pos := Position;
  AccentPx := HexPixel(FAccent);
  TrackW := R * 0.09;
  RTrack := R - TrackW / 2;

  ABmp.LineCap := pecRound;
  ABmp.DrawPolyLineAntialias(ArcPoints(CX, CY, RTrack, 0, 1), HexPixel(ClrKnobTrack), TrackW);
  if Pos > 0.002 then
    ABmp.DrawPolyLineAntialias(ArcPoints(CX, CY, RTrack, 0, Pos), AccentPx, TrackW);

  RFace := R * 0.74;
  ABmp.FillEllipseAntialias(CX, CY, RFace, RFace, HexPixel(ClrKnobFace));
  ABmp.EllipseAntialias(CX, CY, RFace, RFace, AccentPx, R * 0.045);

  A := DegToRad(StartDeg - SweepDeg * Pos);
  ABmp.DrawLineAntialias(CX, CY, CX + RFace * 0.78 * Cos(A), CY - RFace * 0.78 * Sin(A),
    HexPixel(ClrText), R * 0.06);
  ABmp.FillEllipseAntialias(CX, CY, R * 0.1, R * 0.1, HexPixel(ClrText));

  // Caption: "K_p = 1.23" centred under the dial
  ValueText := ' = ' + FloatToStrF(FValue, ffFixed, 15, FDecimals);
  W1 := DrawSymbol(ABmp, 0, 0, FSymbol, FSubSymbol, AccentPx, 20, False);
  SetMathFont(ABmp, 20, []);
  W2 := ABmp.TextSize(ValueText).cx;
  X := CX - (W1 + W2) / 2;
  DrawSymbol(ABmp, X, ABmp.Height - LabelH, FSymbol, FSubSymbol, AccentPx, 20);
  SetMathFont(ABmp, 20, []);
  ABmp.TextOut(X + W1, ABmp.Height - LabelH, ValueText, AccentPx);
end;

end.
