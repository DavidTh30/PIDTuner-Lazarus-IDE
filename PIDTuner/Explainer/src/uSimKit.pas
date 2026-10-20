{ PID Explainer - simulation helpers:
  TTrace  = a recorded step response with every PID term (for replay pages)
  THistory = ring buffer of live signals (for realtime pages) }
unit uSimKit;

{$mode objfpc}{$H+}

interface

uses
  Math, PIDCore;

type
  TTrace = record
    Duration: Double;
    N: Integer;
    R, Y, E, P, I, D, U: TDoubleArray;
  end;

  THistory = class
  private
    FData: array of TDoubleArray; // [channel][slot]
    FCap, FCount, FHead: Integer;
  public
    constructor Create(AChannels, ACapacity: Integer);
    procedure Clear;
    procedure Push(const Values: array of Double);
    { Channel values oldest -> newest }
    function Series(Ch: Integer): TDoubleArray;
    function Last(Ch: Integer): Double;
    property Count: Integer read FCount;
    property Capacity: Integer read FCap;
  end;

{ Unit step on the mass-spring-damper plant, sampled to N points.
  Noise adds a measurement error (sensor updated at 100 Hz). }
function BuildTrace(const G: TPIDGains; const Plant: TPlant; Duration: Double;
  N: Integer; Noise: Double = 0; Setpoint: Double = 1): TTrace;

implementation

function BuildTrace(const G: TPIDGains; const Plant: TPlant; Duration: Double;
  N: Integer; Noise: Double; Setpoint: Double): TTrace;
const
  Dt = 0.001;
var
  Pid: TPIDController;
  Pl: TPlant;
  Steps, S, K: Integer;
  Meas, NoiseVal, U, A: Double;
  Seed: LongWord;

  function Rnd: Double; // deterministic, -1..1
  begin
    Seed := Seed xor (Seed shl 13);
    Seed := Seed xor (Seed shr 17);
    Seed := Seed xor (Seed shl 5);
    Result := (Seed and $FFFFFF) / $7FFFFF - 1;
  end;

  procedure Rec(Idx: Integer);
  begin
    Result.R[Idx] := Setpoint;
    Result.Y[Idx] := Pl.X;
    Result.E[Idx] := Setpoint - Pl.X;
    Result.P[Idx] := Pid.LastP;
    Result.I[Idx] := Pid.LastI;
    Result.D[Idx] := Pid.LastD;
    Result.U[Idx] := U;
  end;

begin
  Result.Duration := Duration;
  Result.N := N;
  SetLength(Result.R, N);
  SetLength(Result.Y, N);
  SetLength(Result.E, N);
  SetLength(Result.P, N);
  SetLength(Result.I, N);
  SetLength(Result.D, N);
  SetLength(Result.U, N);
  Pl := Plant;
  Seed := 2463534242;
  NoiseVal := 0;
  U := 0;
  Steps := Round(Duration / Dt);
  Pid := TPIDController.Create(G);
  try
    Rec(0);
    K := 1;
    for S := 1 to Steps do
    begin
      if (Noise > 0) and (S mod 10 = 0) then
        NoiseVal := Noise * Rnd;
      Meas := Pl.X + NoiseVal;
      U := Pid.Update(Setpoint, Meas, Dt);
      A := (U - Pl.C * Pl.V - Pl.K * Pl.X) / Pl.M;
      Pl.V := Pl.V + A * Dt;
      Pl.X := EnsureRange(Pl.X + Pl.V * Dt, -50, 50);
      while (K < N) and (S >= Round(K * Steps / (N - 1))) do
      begin
        Rec(K);
        Inc(K);
      end;
    end;
    while K < N do
    begin
      Rec(K);
      Inc(K);
    end;
  finally
    Pid.Free;
  end;
end;

{ THistory }

constructor THistory.Create(AChannels, ACapacity: Integer);
var
  I: Integer;
begin
  inherited Create;
  FCap := ACapacity;
  SetLength(FData, AChannels);
  for I := 0 to AChannels - 1 do
    SetLength(FData[I], ACapacity);
end;

procedure THistory.Clear;
begin
  FCount := 0;
  FHead := 0;
end;

procedure THistory.Push(const Values: array of Double);
var
  I: Integer;
begin
  for I := 0 to Min(High(Values), High(FData)) do
    FData[I][FHead] := Values[I];
  FHead := (FHead + 1) mod FCap;
  if FCount < FCap then
    Inc(FCount);
end;

function THistory.Series(Ch: Integer): TDoubleArray;
var
  I, Start: Integer;
begin
  SetLength(Result, FCount);
  Start := (FHead - FCount + FCap) mod FCap;
  for I := 0 to FCount - 1 do
    Result[I] := FData[Ch][(Start + I) mod FCap];
end;

function THistory.Last(Ch: Integer): Double;
begin
  if FCount = 0 then
    Result := 0
  else
    Result := FData[Ch][(FHead - 1 + FCap) mod FCap];
end;

end.
