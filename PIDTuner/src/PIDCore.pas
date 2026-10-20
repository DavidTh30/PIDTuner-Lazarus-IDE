unit PIDCore;

{ PID Tuning Explorer - core math (no GUI dependency).
  u = Kp*e + Ki*Integral(e dt) + Kd*de/dt }

{$mode objfpc}{$H+}

interface

uses
  Math;

type
  TPIDGains = record
    Kp, Ki, Kd: Double;
  end;

  { PID with conditional-integration anti-windup and
    filtered derivative-on-measurement (no derivative kick). }
  TPIDController = class
  private
    FIntegral: Double;
    FPrevMeas: Double;
    FDeriv: Double;
    FFirst: Boolean;
    FLastP, FLastI, FLastD: Double;
  public
    Gains: TPIDGains;
    OutMin, OutMax: Double;
    DerivTau: Double; // derivative low-pass time constant [s]
    AntiWindup: Boolean;
    constructor Create(const AGains: TPIDGains);
    procedure Reset;
    function Update(Setpoint, Measured, Dt: Double): Double;
    // Contribution of each term in the last Update (before clamping)
    property LastP: Double read FLastP;
    property LastI: Double read FLastI;
    property LastD: Double read FLastD;
    property Integral: Double read FIntegral;
  end;

  { Mass-spring-damper plant: M*x'' + C*x' + K*x = u }
  TPlant = record
    M, C, K: Double;
    X, V: Double;
  end;

  TStepMetrics = record
    ITAE: Double;
    Overshoot: Double;     // fraction of setpoint
    SettlingTime: Double;  // 2% band [s]
    Stable: Boolean;
  end;

  TScoreGrid = array of array of Double; // [Col(Kp), Row(Kd)], 0..1
  TDoubleArray = array of Double;

function DefaultPlant: TPlant;
function Gains(Kp, Ki, Kd: Double): TPIDGains;
function SimulateStep(const G: TPIDGains; Plant: TPlant;
  Duration: Double = 10.0; Dt: Double = 0.001): TStepMetrics;
{ Plant output x(t) for a unit step, resampled to Samples points over Duration }
function StepResponse(const G: TPIDGains; Plant: TPlant; Duration: Double;
  Samples: Integer; Dt: Double = 0.001): TDoubleArray;
function MetricsScore(const M: TStepMetrics): Double;
function SweepKpKd(Ki, KpMin, KpMax, KdMin, KdMax: Double;
  Cols, Rows: Integer; const Plant: TPlant): TScoreGrid;
function HeatColor(Score: Double): LongWord; // $RRGGBB

const
  // Design tokens measured from the reference image ($RRGGBB)
  ClrBackground = $0E1117;
  ClrKp         = $F0A04B;
  ClrKi         = $4DA3F0;
  ClrKd         = $5AD27D;
  ClrText       = $FFFFFF;
  ClrKnobTrack  = $2A2F38;
  ClrKnobFace   = $111820;
  ClrPanel      = $151B23;
  ClrBad        = $E0525C;
  HeatStops: array[0..7] of LongWord = (
    $3D1E26, $1E5A5C, $2A9D9A, $2ED3C6, $6CD6A6, $B4CC74, $E3C557, $F5BE45);

implementation

{ TPIDController }

constructor TPIDController.Create(const AGains: TPIDGains);
begin
  inherited Create;
  Gains := AGains;
  OutMin := -100;
  OutMax := 100;
  DerivTau := 0.01;
  AntiWindup := True;
  Reset;
end;

procedure TPIDController.Reset;
begin
  FIntegral := 0;
  FPrevMeas := 0;
  FDeriv := 0;
  FFirst := True;
  FLastP := 0;
  FLastI := 0;
  FLastD := 0;
end;

function TPIDController.Update(Setpoint, Measured, Dt: Double): Double;
var
  E, D, NewIntegral, U: Double;
begin
  E := Setpoint - Measured;
  if FFirst then
  begin
    FPrevMeas := Measured;
    FFirst := False;
  end;

  D := -(Measured - FPrevMeas) / Dt;
  FDeriv := FDeriv + (D - FDeriv) * Dt / (DerivTau + Dt);
  FPrevMeas := Measured;

  NewIntegral := FIntegral + E * Dt;
  U := Gains.Kp * E + Gains.Ki * NewIntegral + Gains.Kd * FDeriv;

  // Anti-windup: only accept the integral step when not saturating further
  if AntiWindup and ((U > OutMax) and (E > 0) or (U < OutMin) and (E < 0)) then
    U := Gains.Kp * E + Gains.Ki * FIntegral + Gains.Kd * FDeriv
  else
    FIntegral := NewIntegral;

  FLastP := Gains.Kp * E;
  FLastI := Gains.Ki * FIntegral;
  FLastD := Gains.Kd * FDeriv;
  Result := EnsureRange(U, OutMin, OutMax);
end;

{ Helpers }

function DefaultPlant: TPlant;
begin
  Result.M := 1.0;
  Result.C := 0.5;
  Result.K := 1.0;
  Result.X := 0;
  Result.V := 0;
end;

function Gains(Kp, Ki, Kd: Double): TPIDGains;
begin
  Result.Kp := Kp;
  Result.Ki := Ki;
  Result.Kd := Kd;
end;

procedure StepPlant(var Plant: TPlant; U, Dt: Double);
var
  A: Double;
begin
  // Semi-implicit Euler
  A := (U - Plant.C * Plant.V - Plant.K * Plant.X) / Plant.M;
  Plant.V := Plant.V + A * Dt;
  Plant.X := Plant.X + Plant.V * Dt;
end;

function StepResponse(const G: TPIDGains; Plant: TPlant; Duration: Double;
  Samples: Integer; Dt: Double): TDoubleArray;
var
  Pid: TPIDController;
  I, K, Steps: Integer;
  X: Double;
begin
  SetLength(Result, Samples);
  if Samples = 0 then
    Exit;
  Result[0] := Plant.X;
  X := Plant.X;
  Steps := Round(Duration / Dt);
  K := 1;
  Pid := TPIDController.Create(G);
  try
    for I := 1 to Steps do
    begin
      StepPlant(Plant, Pid.Update(1.0, Plant.X, Dt), Dt);
      X := Plant.X;
      if IsNan(X) or (Abs(X) > 100) then
      begin
        if IsNan(X) then
          X := 100;
        X := EnsureRange(X, -100, 100);
        Break;
      end;
      while (K < Samples) and (I >= Round(K * Steps / Max(1, Samples - 1))) do
      begin
        Result[K] := X;
        Inc(K);
      end;
    end;
  finally
    Pid.Free;
  end;
  while K < Samples do
  begin
    Result[K] := X;
    Inc(K);
  end;
end;

function SimulateStep(const G: TPIDGains; Plant: TPlant;
  Duration: Double; Dt: Double): TStepMetrics;
const
  Setpoint = 1.0;
  Band = 0.02;
var
  Pid: TPIDController;
  T, E, MaxX: Double;
begin
  Result.ITAE := 0;
  Result.SettlingTime := 0;
  Result.Stable := True;
  MaxX := 0;
  Pid := TPIDController.Create(G);
  try
    T := 0;
    while T < Duration do
    begin
      StepPlant(Plant, Pid.Update(Setpoint, Plant.X, Dt), Dt);
      T := T + Dt;

      if IsNan(Plant.X) or (Abs(Plant.X) > 100) then
      begin
        Result.Stable := False;
        Break;
      end;

      E := Setpoint - Plant.X;
      Result.ITAE := Result.ITAE + T * Abs(E) * Dt;
      if Plant.X > MaxX then
        MaxX := Plant.X;
      if Abs(E) > Band * Setpoint then
        Result.SettlingTime := T;
    end;
    if Result.Stable and (Abs(Setpoint - Plant.X) > 5 * Band) then
      Result.Stable := False; // never converged
  finally
    Pid.Free;
  end;
  Result.Overshoot := Max(0, MaxX - Setpoint) / Setpoint;
end;

function MetricsScore(const M: TStepMetrics): Double;
begin
  if not M.Stable then
    Exit(0);
  // Lower ITAE and overshoot -> higher score (0..1)
  Result := 1 / (1 + M.ITAE + 2 * M.Overshoot);
end;

function SweepKpKd(Ki, KpMin, KpMax, KdMin, KdMax: Double;
  Cols, Rows: Integer; const Plant: TPlant): TScoreGrid;
var
  I, J: Integer;
  Kp, Kd, Best: Double;
begin
  SetLength(Result, Cols, Rows);
  Best := 0;
  for I := 0 to Cols - 1 do
    for J := 0 to Rows - 1 do
    begin
      Kp := KpMin + (KpMax - KpMin) * I / Max(1, Cols - 1);
      Kd := KdMin + (KdMax - KdMin) * J / Max(1, Rows - 1); // J=0 -> lowest Kd
      Result[I, J] := MetricsScore(SimulateStep(Gains(Kp, Ki, Kd), Plant));
      if Result[I, J] > Best then
        Best := Result[I, J];
    end;
  // Normalise so the best cell maps to the top (gold) colour
  if Best > 0 then
    for I := 0 to Cols - 1 do
      for J := 0 to Rows - 1 do
        Result[I, J] := Result[I, J] / Best;
end;

function HeatColor(Score: Double): LongWord;
var
  F, T: Double;
  Idx: Integer;
  C0, C1: LongWord;

  function Lerp(A, B: LongWord; Shift: Integer): LongWord;
  var
    VA, VB: Integer;
  begin
    VA := (A shr Shift) and $FF;
    VB := (B shr Shift) and $FF;
    Result := LongWord(Round(VA + (VB - VA) * T)) shl Shift;
  end;

begin
  F := EnsureRange(Score, 0, 1) * High(HeatStops);
  Idx := Min(Trunc(F), High(HeatStops) - 1);
  T := F - Idx;
  C0 := HeatStops[Idx];
  C1 := HeatStops[Idx + 1];
  Result := Lerp(C0, C1, 16) or Lerp(C0, C1, 8) or Lerp(C0, C1, 0);
end;

end.
