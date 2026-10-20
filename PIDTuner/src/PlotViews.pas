unit PlotViews;

{ TEquationView - the colour-coded PID equation from the reference image.
  TResponsePlot - step response x(t) of the current gains with metrics. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore;

type
  TEquationView = class(TBGRAView)
  private
    FTermX: array[0..2] of Single; // centre of each term, relative to equation start
    function Layout(ABmp: TBGRABitmap; X0, Y0: Single; DoDraw: Boolean): Single;
  public
    { X centre of term 0 = Kp, 1 = Ki, 2 = Kd in control coordinates;
      used to place the knobs under their terms }
    function TermCenter(Index: Integer): Single;
    procedure Render(ABmp: TBGRABitmap); override;
  end;

  TResponsePlot = class(TBGRAView)
  private
    FData: TDoubleArray;
    FDuration: Double;
    FMetrics: TStepMetrics;
  public
    procedure SetResponse(const AData: TDoubleArray; ADuration: Double;
      const AMetrics: TStepMetrics);
    procedure Render(ABmp: TBGRABitmap); override;
  end;

implementation

const
  IntegralSign = #$E2#$88#$AB; // U+222B in UTF-8

{ TEquationView }

function TEquationView.Layout(ABmp: TBGRABitmap; X0, Y0: Single; DoDraw: Boolean): Single;
var
  X, Start, Wd, LineY: Single;
  Sz: Integer;
  White, Orange, Blue, Green: TBGRAPixel;

  procedure Txt(const S: string; C: TBGRAPixel; ASize: Integer;
    AStyle: TFontStyles; DY: Single);
  begin
    SetMathFont(ABmp, ASize, AStyle);
    if DoDraw then
      ABmp.TextOut(X, Y0 + DY, S, C);
    X := X + ABmp.TextSize(S).cx;
  end;

  procedure Sym(const Base, Sub: string; C: TBGRAPixel);
  begin
    X := X + DrawSymbol(ABmp, X, Y0, Base, Sub, C, Sz, DoDraw);
  end;

begin
  Sz := Round(Height * 0.42);
  White := HexPixel(ClrText);
  Orange := HexPixel(ClrKp);
  Blue := HexPixel(ClrKi);
  Green := HexPixel(ClrKd);
  X := X0;

  Txt('u', White, Sz, [fsItalic], 0);
  Txt(' = ', White, Sz, [], 0);

  Start := X;
  Sym('K', 'p', Orange);
  Txt('e', Orange, Sz, [fsItalic], 0);
  FTermX[0] := (Start + X) / 2 - X0;

  Txt(' + ', White, Sz, [], 0);

  Start := X;
  Sym('K', 'i', Blue);
  Txt(' ', Blue, Sz, [], 0);
  Txt(IntegralSign, Blue, Round(Sz * 1.6), [], -Sz * 0.38);
  Txt(' e dt', Blue, Sz, [fsItalic], 0);
  FTermX[1] := (Start + X) / 2 - X0;

  Txt(' + ', White, Sz, [], 0);

  Start := X;
  Sym('K', 'd', Green);
  SetMathFont(ABmp, Round(Sz * 0.8), [fsItalic]);
  Wd := Max(ABmp.TextSize('de').cx, ABmp.TextSize('dt').cx) + Sz * 0.1;
  if DoDraw then
  begin
    LineY := Y0 + Sz * 0.55;
    ABmp.TextOut(X + Wd / 2, LineY - Sz * 0.85, 'de', Green, taCenter);
    ABmp.DrawLineAntialias(X, LineY, X + Wd, LineY, Green, Max(2, Sz * 0.04));
    ABmp.TextOut(X + Wd / 2, LineY + Sz * 0.02, 'dt', Green, taCenter);
  end;
  X := X + Wd;
  FTermX[2] := (Start + X) / 2 - X0;

  Result := X - X0;
end;

function TEquationView.TermCenter(Index: Integer): Single;
var
  Bmp: TBGRABitmap;
  W: Single;
begin
  Bmp := TBGRABitmap.Create(1, 1);
  try
    W := Layout(Bmp, 0, 0, False);
  finally
    Bmp.Free;
  end;
  Result := (Width - W) / 2 + FTermX[EnsureRange(Index, 0, 2)];
end;

procedure TEquationView.Render(ABmp: TBGRABitmap);
var
  W: Single;
begin
  W := Layout(ABmp, 0, 0, False);
  Layout(ABmp, (ABmp.Width - W) / 2, ABmp.Height * 0.5 - Height * 0.25, True);
end;

{ TResponsePlot }

procedure TResponsePlot.SetResponse(const AData: TDoubleArray; ADuration: Double;
  const AMetrics: TStepMetrics);
begin
  FData := AData;
  FDuration := ADuration;
  FMetrics := AMetrics;
  Invalidate;
end;

procedure TResponsePlot.Render(ABmp: TBGRABitmap);
const
  PadL = 40;
  PadR = 14;
  PadT = 62;
  PadB = 30;
  YMin = -0.2;
  YMax = 1.8;
var
  L, T, R, B: Single;
  I: Integer;
  Pts: ArrayOfTPointF;
  Faint, Dim, Curve: TBGRAPixel;
  Info: string;

  function MapY(V: Double): Single;
  begin
    Result := B - (EnsureRange(V, YMin, YMax) - YMin) / (YMax - YMin) * (B - T);
  end;

  procedure HLine(V: Double; C: TBGRAPixel; const LabelText: string);
  begin
    ABmp.DrawLineAntialias(L, MapY(V), R, MapY(V), C, 1);
    ABmp.TextOut(L - 6, MapY(V) - 8, LabelText, Dim, taRightJustify);
  end;

begin
  ABmp.FillRoundRectAntialias(0, 0, ABmp.Width - 1, ABmp.Height - 1, 10, 10, HexPixel(ClrPanel));
  L := PadL;
  T := PadT;
  R := ABmp.Width - PadR;
  B := ABmp.Height - PadB;
  Faint := BGRA(255, 255, 255, 28);
  Dim := BGRA(255, 255, 255, 120);
  Curve := HexPixel(HeatStops[High(HeatStops)]);

  SetMathFont(ABmp, 22, []);
  ABmp.TextOut(14, 10, 'Step response', HexPixel(ClrText));
  if not FMetrics.Stable then
    Info := 'unstable / not settled'
  else
    Info := Format('ITAE %.2f   overshoot %.0f%%   settle %.1f s',
      [FMetrics.ITAE, FMetrics.Overshoot * 100, FMetrics.SettlingTime]);
  SetMathFont(ABmp, 15, []);
  if FMetrics.Stable then
    ABmp.TextOut(14, 36, Info, Dim)
  else
    ABmp.TextOut(14, 36, Info, HexPixel(ClrBad));

  SetMathFont(ABmp, 13, []);
  HLine(0, Faint, '0');
  HLine(0.5, Faint, '0.5');
  HLine(1.5, Faint, '1.5');
  ABmp.PenStyle := psDash;
  HLine(1.0, Dim, '1');
  ABmp.PenStyle := psSolid;
  ABmp.TextOut(L, B + 6, '0', Dim);
  ABmp.TextOut(R, B + 6, FloatToStrF(FDuration, ffFixed, 15, 0) + ' s', Dim, taRightJustify);
  ABmp.TextOut((L + R) / 2, B + 6, 't', Dim, taCenter);

  if Length(FData) < 2 then
    Exit;
  SetLength(Pts, Length(FData));
  for I := 0 to High(FData) do
    Pts[I] := PointF(L + (R - L) * I / High(FData), MapY(FData[I]));
  ABmp.LineCap := pecRound;
  ABmp.JoinStyle := pjsRound;
  ABmp.DrawPolyLineAntialias(Pts, Curve, 2.5);
end;

end.
