{ PID Explainer - real-world examples driven by TPIDController in real time:
  cruise control (car on hills), oven temperature (dead time + saturation),
  drone altitude hold (gravity -> needs Ki). Each draws its own scene. }
unit uScenarios;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore, uDrawKit, uSimKit;

type
  TScenario = class
  protected
    FAcc: Double;     // sim time not yet recorded into History
    FSimDt: Double;   // fixed physics step [s]
    procedure StepPlant(AU, Dt: Double); virtual; abstract;
  public
    Pid: TPIDController;
    Setpoint: Double;
    TimeScale: Double; // sim seconds per real second
    Time: Double;      // sim time [s]
    U: Double;         // last controller output
    History: THistory; // 0 = setpoint, 1 = output, 2 = u
    Span: Double;      // seconds shown in the history plot
    YMin, YMax, YStep: Double;
    OutLabel, OutUnit: string;
    constructor Create(const G: TPIDGains; ASpan: Double);
    destructor Destroy; override;
    procedure Reset; virtual;
    procedure Advance(RealDt: Double);
    procedure Disturb; virtual;
    function Output: Double; virtual; abstract;
    { Converts an internal value to the unit shown on screen }
    function Display(V: Double): Double; virtual;
    procedure DrawScene(B: TBGRABitmap; const R: TBox); virtual; abstract;
  end;

  TCruiseScenario = class(TScenario)
  private
    FX, FV, FGust: Double;
    function Grade(X: Double): Double;
    function Height(X: Double): Double;
  protected
    procedure StepPlant(AU, Dt: Double); override;
  public
    constructor Create;
    procedure Reset; override;
    procedure Disturb; override;
    function Output: Double; override;
    function Display(V: Double): Double; override;
    procedure DrawScene(B: TBGRABitmap; const R: TBox); override;
  end;

  TOvenScenario = class(TScenario)
  private
    FTemp: Double;
    FDelay: TDoubleArray; // heater power travelling through the dead time
    FDelayPos: Integer;
    FHeat: Double;        // power that reaches the oven now
  protected
    procedure StepPlant(AU, Dt: Double); override;
  public
    constructor Create;
    procedure Reset; override;
    procedure Disturb; override;
    function Output: Double; override;
    procedure DrawScene(B: TBGRABitmap; const R: TBox); override;
  end;

  TDroneScenario = class(TScenario)
  private
    FH, FV, FWind: Double;
  protected
    procedure StepPlant(AU, Dt: Double); override;
  public
    constructor Create;
    procedure Reset; override;
    procedure Disturb; override;
    function Output: Double; override;
    procedure DrawScene(B: TBGRABitmap; const R: TBox); override;
  end;

implementation

const
  HistorySlots = 600;

{ TScenario }

constructor TScenario.Create(const G: TPIDGains; ASpan: Double);
begin
  inherited Create;
  Pid := TPIDController.Create(G);
  History := THistory.Create(3, HistorySlots);
  Span := ASpan;
  TimeScale := 1;
  FSimDt := 0.002;
end;

destructor TScenario.Destroy;
begin
  History.Free;
  Pid.Free;
  inherited Destroy;
end;

procedure TScenario.Reset;
begin
  Pid.Reset;
  History.Clear;
  Time := 0;
  U := 0;
  FAcc := 0;
end;

procedure TScenario.Advance(RealDt: Double);
var
  Remaining, Slot: Double;
begin
  Remaining := RealDt * TimeScale;
  Slot := Span / HistorySlots;
  while Remaining > 1e-9 do
  begin
    U := Pid.Update(Setpoint, Output, FSimDt);
    StepPlant(U, FSimDt);
    Time := Time + FSimDt;
    Remaining := Remaining - FSimDt;
    FAcc := FAcc + FSimDt;
    if FAcc >= Slot then
    begin
      FAcc := FAcc - Slot;
      History.Push([Setpoint, Output, U]);
    end;
  end;
end;

procedure TScenario.Disturb;
begin
end;

function TScenario.Display(V: Double): Double;
begin
  Result := V;
end;

{ TCruiseScenario - m*v' = u*Fmax - b*v - m*g*grade(x) - gust }

const
  CarMass = 1200;
  CarDrag = 40;
  CarFMax = 6000;

constructor TCruiseScenario.Create;
begin
  inherited Create(Gains(0.25, 0.05, 0.02), 40);
  Pid.OutMin := -0.6; // brake
  Pid.OutMax := 1.0;  // full throttle
  Setpoint := 80 / 3.6;
  YMin := 40;
  YMax := 120;
  YStep := 20;
  OutLabel := 'ความเร็ว';
  OutUnit := ' km/h';
  Reset;
end;

procedure TCruiseScenario.Reset;
begin
  inherited Reset;
  FX := 0;
  FV := 60 / 3.6;
  FGust := 0;
end;

procedure TCruiseScenario.Disturb;
begin
  FGust := 3000; // strong headwind
end;

function TCruiseScenario.Grade(X: Double): Double;
begin
  Result := 0.07 * Sin(X / 180) + 0.03 * Sin(X / 53 + 1);
end;

function TCruiseScenario.Height(X: Double): Double;
begin
  // integral of Grade
  Result := -0.07 * 180 * Cos(X / 180) - 0.03 * 53 * Cos(X / 53 + 1);
end;

procedure TCruiseScenario.StepPlant(AU, Dt: Double);
var
  F: Double;
begin
  F := AU * CarFMax - CarDrag * FV - CarMass * 9.81 * Grade(FX) - FGust;
  FV := Max(0, FV + F / CarMass * Dt);
  FX := FX + FV * Dt;
  FGust := FGust * Exp(-Dt / 2.5);
end;

function TCruiseScenario.Output: Double;
begin
  Result := FV;
end;

function TCruiseScenario.Display(V: Double): Double;
begin
  Result := V * 3.6;
end;

procedure TCruiseScenario.DrawScene(B: TBGRABitmap; const R: TBox);
const
  VScale = 3.0; // vertical exaggeration of the hills
var
  Pts: ArrayOfTPointF;
  I, N: Integer;
  CarSX, BaseY, WX, SX, SY, Ang, CA, SA, WheelA, Pole: Single;
  Body: array[0..7] of TPointF;
  Cab: array[0..3] of TPointF;

  function GroundY(WorldX: Double): Single;
  begin
    Result := BaseY - (Height(WorldX) - Height(FX)) * VScale;
  end;

  function Rot(LX, LY: Single): TPointF; // car-local -> screen
  begin
    Result := PointF(CarSX + LX * CA - LY * SA, GroundY(FX) + LX * SA + LY * CA);
  end;

  procedure Wheel(LX: Single);
  var
    C: TPointF;
    K: Integer;
    A: Single;
  begin
    C := Rot(LX, -9);
    B.FillEllipseAntialias(C.X, C.Y, 11, 11, BGRA(20, 22, 26));
    B.EllipseAntialias(C.X, C.Y, 11, 11, BGRA(120, 128, 140), 2);
    for K := 0 to 2 do
    begin
      A := WheelA + K * Pi / 3;
      B.DrawLineAntialias(C.X - 8 * Cos(A), C.Y - 8 * Sin(A), C.X + 8 * Cos(A),
        C.Y + 8 * Sin(A), BGRA(150, 158, 170), 1.5);
    end;
  end;

begin
  B.ClipRect := Rect(Round(R.X1), Round(R.Y1), Round(R.X2), Round(R.Y2));
  try
    Panel(B, R, ClrSky, 10);
    BaseY := R.Y1 + BoxH(R) * 0.68;
    CarSX := R.X1 + BoxW(R) * 0.32;

    // roadside poles every 40 m give a sense of speed
    Pole := Floor((FX - (CarSX - R.X1)) / 40) * 40;
    while Pole < FX + (R.X2 - CarSX) do
    begin
      SX := CarSX + (Pole - FX);
      SY := GroundY(Pole);
      B.DrawLineAntialias(SX, SY, SX, SY - 34, BGRA(80, 90, 104), 2);
      B.FillEllipseAntialias(SX, SY - 36, 3, 3, BGRA(245, 190, 69, 200));
      Pole := Pole + 40;
    end;

    // ground polygon
    N := Round(BoxW(R) / 6) + 1;
    SetLength(Pts, N + 2);
    for I := 0 to N - 1 do
    begin
      SX := R.X1 + I * 6;
      Pts[I] := PointF(SX, GroundY(FX + (SX - CarSX)));
    end;
    Pts[N] := PointF(R.X2, R.Y2);
    Pts[N + 1] := PointF(R.X1, R.Y2);
    B.FillPolyAntialias(Pts, BGRA(30, 40, 46));
    SetLength(Pts, N);
    B.DrawPolyLineAntialias(Pts, BGRA(110, 120, 132), 3);

    // moving lane marks
    WX := Floor((FX - (CarSX - R.X1)) / 24) * 24;
    while WX < FX + (R.X2 - CarSX) do
    begin
      SX := CarSX + (WX - FX);
      B.DrawLineAntialias(SX, GroundY(WX) + 7, SX + 10, GroundY(WX + 10) + 7,
        BGRA(245, 190, 69, 160), 2);
      WX := WX + 24;
    end;

    // car, tilted with the (exaggerated) slope
    Ang := ArcTan(Grade(FX) * VScale);
    CA := Cos(-Ang);
    SA := Sin(-Ang);
    Body[0] := Rot(-44, -10);
    Body[1] := Rot(-44, -26);
    Body[2] := Rot(-30, -30);
    Body[3] := Rot(30, -30);
    Body[4] := Rot(46, -24);
    Body[5] := Rot(46, -10);
    Body[6] := Rot(30, -8);
    Body[7] := Rot(-30, -8);
    B.FillPolyAntialias(Body, HexPixel(ClrKi));
    Cab[0] := Rot(-24, -30);
    Cab[1] := Rot(-14, -44);
    Cab[2] := Rot(16, -44);
    Cab[3] := Rot(28, -30);
    B.FillPolyAntialias(Cab, BGRA(120, 190, 250, 220));
    WheelA := FX / 0.33;
    Wheel(-26);
    Wheel(28);
    if FGust > 200 then
      for I := 0 to 5 do
      begin
        SY := R.Y1 + 40 + I * 22;
        SX := R.X2 - Frac(Time * 1.7 + I * 0.37) * BoxW(R);
        B.DrawLineAntialias(SX, SY, SX + 40, SY, BGRA(200, 220, 255, Round(Min(1, FGust / 3000) * 150)), 2);
      end;

    // speedometer + throttle/brake bar
    Gauge(B, R.X2 - 90, R.Y1 + 88, 62, FV * 3.6 / 160, ClrKi,
      Fmt(FV * 3.6, 0), 'km/h', Setpoint * 3.6 / 160);
    SX := R.X2 - 186;
    B.FillRoundRectAntialias(SX, R.Y1 + 30, SX + 14, R.Y1 + 150, 4, 4, HexPixel(ClrKnobTrack));
    SY := R.Y1 + 150 - 120 * (U - Pid.OutMin) / (Pid.OutMax - Pid.OutMin);
    if U >= 0 then
      B.FillRectAntialias(SX + 2, SY, SX + 12, R.Y1 + 150 - 120 * (-Pid.OutMin) /
        (Pid.OutMax - Pid.OutMin), HexPixel(ClrKd))
    else
      B.FillRectAntialias(SX + 2, R.Y1 + 150 - 120 * (-Pid.OutMin) /
        (Pid.OutMax - Pid.OutMin), SX + 12, SY, HexPixel(ClrBad));
    Txt(B, SX + 7, R.Y1 + 156, 'u', ClrDim, 13, [], taCenter);
    Txt(B, R.X1 + 14, R.Y1 + 10, Format('ความชัน %.1f%%', [Grade(FX) * 100]), ClrDim, 14);
  finally
    B.NoClip;
  end;
end;

{ TOvenScenario - tau*T' = Pmax*u(t - deadtime) - (T - Tamb) }

const
  OvenTamb = 25;
  OvenPMax = 300; // steady rise at 100 % heater [C]
  OvenTau = 40;   // [s]
  OvenDead = 4;   // [s]

constructor TOvenScenario.Create;
begin
  inherited Create(Gains(0.015, 0.0008, 0.02), 240);
  Pid.OutMin := 0;
  Pid.OutMax := 1;
  FSimDt := 0.01;
  TimeScale := 6;
  Setpoint := 180;
  YMin := 0;
  YMax := 260;
  YStep := 50;
  OutLabel := 'อุณหภูมิ';
  OutUnit := ' °C';
  SetLength(FDelay, Round(OvenDead / FSimDt));
  Reset;
end;

procedure TOvenScenario.Reset;
var
  I: Integer;
begin
  inherited Reset;
  FTemp := OvenTamb;
  FHeat := 0;
  FDelayPos := 0;
  for I := 0 to High(FDelay) do
    FDelay[I] := 0;
end;

procedure TOvenScenario.Disturb;
begin
  FTemp := FTemp - 30; // door opened
end;

procedure TOvenScenario.StepPlant(AU, Dt: Double);
begin
  FHeat := FDelay[FDelayPos];
  FDelay[FDelayPos] := AU;
  FDelayPos := (FDelayPos + 1) mod Length(FDelay);
  FTemp := FTemp + (OvenPMax * FHeat - (FTemp - OvenTamb)) / OvenTau * Dt;
end;

function TOvenScenario.Output: Double;
begin
  Result := FTemp;
end;

procedure TOvenScenario.DrawScene(B: TBGRABitmap; const R: TBox);
var
  OX1, OY1, OX2, OY2, WX1, WY1, WX2, WY2, X, Y, TX, TBot, TTop, F: Single;
  I, K: Integer;
  Glow: Byte;
  Pts: ArrayOfTPointF;
begin
  Panel(B, R, ClrSky, 10);
  OX1 := R.X1 + 40;
  OY1 := R.Y1 + 36;
  OX2 := R.X1 + BoxW(R) * 0.62;
  OY2 := R.Y2 - 30;
  B.FillRoundRectAntialias(OX1, OY1, OX2, OY2, 14, 14, BGRA(58, 64, 74));
  B.FillRoundRectAntialias(OX1 + 6, OY1 + 6, OX2 - 6, OY1 + 34, 8, 8, BGRA(40, 45, 54));
  for I := 0 to 2 do
    B.FillEllipseAntialias(OX2 - 30 - I * 30, OY1 + 20, 8, 8, BGRA(90, 98, 110));
  // window glows with the heat that actually arrives (after the dead time)
  WX1 := OX1 + 22;
  WY1 := OY1 + 50;
  WX2 := OX2 - 22;
  WY2 := OY2 - 22;
  Glow := Round(EnsureRange((FTemp - OvenTamb) / 250, 0, 1) * 150);
  B.FillRoundRectAntialias(WX1, WY1, WX2, WY2, 8, 8, BGRA(20, 16, 14));
  B.FillRoundRectAntialias(WX1, WY1, WX2, WY2, 8, 8, BGRA(255, 120, 40, Glow));
  // heating element, brightness = current heater power
  SetLength(Pts, 13);
  for K := 0 to 1 do
  begin
    if K = 0 then
      Y := WY2 - 16
    else
      Y := WY1 + 16;
    for I := 0 to 12 do
      Pts[I] := PointF(WX1 + 12 + I * (WX2 - WX1 - 24) / 12, Y + IfThen(Odd(I), -7, 7));
    B.DrawPolyLineAntialias(Pts, BGRA(255, Round(70 + 150 * FHeat), 40,
      Round(80 + 175 * FHeat)), 3);
  end;
  // rising heat waves
  for I := 0 to 3 do
  begin
    X := WX1 + 30 + I * (WX2 - WX1 - 60) / 3;
    F := Frac(Time * 0.15 + I * 0.25);
    Y := WY2 - 30 - F * (WY2 - WY1 - 60);
    B.DrawLineAntialias(X, Y, X + 6, Y - 12, BGRA(255, 200, 120, Round((1 - F) * Glow)), 2);
  end;

  // thermometer 0..300 C with setpoint mark
  TX := R.X1 + BoxW(R) * 0.78;
  TTop := R.Y1 + 40;
  TBot := R.Y2 - 60;
  B.FillRoundRectAntialias(TX - 10, TTop, TX + 10, TBot, 10, 10, HexPixel(ClrKnobTrack));
  F := EnsureRange(FTemp / 300, 0, 1);
  B.FillRoundRectAntialias(TX - 5, TBot - (TBot - TTop - 8) * F, TX + 5, TBot, 5, 5, HexPixel(ClrBad));
  B.FillEllipseAntialias(TX, TBot + 12, 18, 18, HexPixel(ClrBad));
  Y := TBot - (TBot - TTop - 8) * Setpoint / 300;
  B.DrawLineAntialias(TX - 18, Y, TX + 18, Y, BGRAWhite, 2);
  Txt(B, TX - 24, Y - 9, 'r = ' + Fmt(Setpoint, 0) + '°', ClrText, 14, [], taRightJustify);
  Txt(B, TX + 24, TBot - (TBot - TTop - 8) * F - 9, Fmt(FTemp, 1) + '°C', ClrBad, 16, [fsBold]);

  Txt(B, OX1, OY2 + 4, Format('heater u = %.0f%%    ความร้อนที่ถึงเตาตอนนี้ = %.0f%%',
    [U * 100, FHeat * 100]), ClrDim, 13);
  Txt(B, R.X2 - 12, R.Y1 + 10, 'เวลาจำลอง ×' + Fmt(TimeScale, 0), ClrDim, 13, [], taRightJustify);
end;

{ TDroneScenario - m*h'' = u*Tmax - m*g - c*h' + wind }

const
  DroneMass = 1.0;
  DroneG = 9.81;
  DroneTMax = 2 * DroneMass * DroneG; // hover at u = 0.5
  DroneDrag = 0.4;

constructor TDroneScenario.Create;
begin
  inherited Create(Gains(0.25, 0.1, 0.25), 30);
  Pid.OutMin := 0;
  Pid.OutMax := 1;
  Setpoint := 5;
  YMin := 0;
  YMax := 10;
  YStep := 2;
  OutLabel := 'ความสูง';
  OutUnit := ' m';
  Reset;
end;

procedure TDroneScenario.Reset;
begin
  inherited Reset;
  FH := 0;
  FV := 0;
  FWind := 0;
end;

procedure TDroneScenario.Disturb;
begin
  FWind := -9; // down-draft [N]
end;

procedure TDroneScenario.StepPlant(AU, Dt: Double);
var
  F: Double;
begin
  F := AU * DroneTMax - DroneMass * DroneG - DroneDrag * FV + FWind
    + 0.4 * Sin(Time * 1.3) * Sin(Time * 0.31);
  FV := FV + F / DroneMass * Dt;
  FH := FH + FV * Dt;
  if FH <= 0 then
  begin
    FH := 0;
    FV := Max(0, FV);
  end;
  FWind := FWind * Exp(-Dt / 0.8);
end;

function TDroneScenario.Output: Double;
begin
  Result := FH;
end;

procedure TDroneScenario.DrawScene(B: TBGRABitmap; const R: TBox);
var
  GroundY, Top, CX, CY, Y, Blur, Thrust, X: Single;
  I: Integer;

  function MapH(H: Double): Single;
  begin
    Result := GroundY - (GroundY - Top) * H / 10;
  end;

  procedure Prop(PX: Single);
  begin
    B.DrawLineAntialias(PX, CY - 4, PX, CY - 12, BGRA(150, 158, 170), 3);
    B.FillEllipseAntialias(PX, CY - 13, 28, 4, BGRA(200, 210, 225, Round(60 + 120 * Blur)));
    B.DrawLineAntialias(PX - 26 * Cos(Time * 40), CY - 13, PX + 26 * Cos(Time * 40),
      CY - 13, BGRA(230, 235, 245, 180), 2);
  end;

begin
  Panel(B, R, ClrSky, 10);
  GroundY := R.Y2 - 30;
  Top := R.Y1 + 30;
  B.FillRectAntialias(R.X1 + 1, GroundY, R.X2 - 1, R.Y2 - 1, BGRA(30, 40, 46));
  B.DrawLineAntialias(R.X1, GroundY, R.X2, GroundY, BGRA(110, 120, 132), 2);

  // altitude ruler
  for I := 0 to 10 do
  begin
    Y := MapH(I);
    B.DrawLineAntialias(R.X1 + 40, Y, R.X1 + 50 - IfThen(Odd(I), 4, 0), Y, BGRA(140, 150, 162), 1);
    if not Odd(I) then
      Txt(B, R.X1 + 34, Y - 8, IntToStr(I) + ' m', ClrDim, 12, [], taRightJustify);
  end;
  // setpoint line
  Y := MapH(Setpoint);
  B.PenStyle := psDash;
  B.DrawLineAntialias(R.X1 + 56, Y, R.X2 - 20, Y, BGRA(255, 255, 255, 150), 1.5);
  B.PenStyle := psSolid;
  Txt(B, R.X1 + 60, Y - 22, 'r = ' + Fmt(Setpoint, 1) + ' m', ClrText, 14);

  // drone
  CX := (R.X1 + R.X2) / 2 - 40;
  CY := MapH(FH) - 14;
  Blur := EnsureRange(U, 0, 1);
  Thrust := U * 60;
  for I := 0 to 1 do
  begin
    X := CX + IfThen(I = 0, -46, 46);
    B.FillPolyAntialias([PointF(X - 10, CY + 4), PointF(X + 10, CY + 4),
      PointF(X, CY + 4 + Thrust)], BGRA(100, 180, 255, 70));
  end;
  B.DrawLineAntialias(CX - 46, CY, CX + 46, CY, BGRA(150, 158, 170), 4);
  B.FillRoundRectAntialias(CX - 22, CY - 8, CX + 22, CY + 10, 6, 6, HexPixel(ClrKd));
  B.FillEllipseAntialias(CX, CY + 1, 5, 5, BGRA(10, 20, 14));
  Prop(CX - 46);
  Prop(CX + 46);
  // shadow
  B.FillEllipseAntialias(CX, GroundY + 6, Max(10, 50 - FH * 3), 5,
    BGRA(0, 0, 0, Round(Max(20, 140 - FH * 10))));

  if FWind < -0.5 then
    for I := 0 to 6 do
    begin
      X := R.X1 + 80 + I * (BoxW(R) - 140) / 6;
      Y := Top + Frac(Time * 1.5 + I * 0.31) * (GroundY - Top);
      B.DrawLineAntialias(X, Y, X, Y + 30, BGRA(200, 220, 255, Round(Min(1, -FWind / 9) * 160)), 2);
    end;

  Gauge(B, R.X2 - 80, R.Y1 + 160, 52, U, ClrKd, Fmt(U * 100, 0) + '%', 'thrust u',
    DroneMass * DroneG / DroneTMax);
  Txt(B, R.X1 + 60, R.Y1 + 8, 'h = ' + Fmt(FH, 2) + ' m', ClrKd, 16, [fsBold]);
end;

end.
