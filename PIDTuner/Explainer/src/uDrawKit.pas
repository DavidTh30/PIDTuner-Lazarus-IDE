{ PID Explainer - drawing helpers on top of BGRABitmap:
  fonts, Thai-aware word wrap, rich paragraphs, panels, plots, sliders, gauges. }
unit uDrawKit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, contnrs, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore;

const
  CanvasW = 1280; // fixed design resolution, letterboxed to the window
  CanvasH = 760;
  UIFont = 'Leelawadee UI';
  CodeFont = 'Consolas';

  ClrBody  = $D5DBE3;
  ClrDim   = $8A94A3;
  ClrGrid  = $252C36;
  ClrGold  = $F5BE45;
  ClrCode  = $A8E6B8;
  ClrCodeBg = $0A0D12;
  ClrSky   = $16202C;

type
  TBox = record
    X1, Y1, X2, Y2: Single;
  end;

  TPlotBox = record
    R: TBox;
    X0, X1, Y0, Y1: Double;
  end;

  { Horizontal slider drawn into the frame; the owner forwards mouse events }
  TSlider = class
  public
    R: TBox;
    Symbol, Sub, Units: string;
    MinV, MaxV, Value: Double;
    Color: LongWord;
    Decimals: Integer;
    Dragging: Boolean;
    OnChange: TNotifyEvent;
    constructor Create(const ASymbol, ASub: string; AMin, AMax, AValue: Double;
      AColor: LongWord; ADecimals: Integer);
    procedure SetValue(V: Double);
    procedure Draw(B: TBGRABitmap);
    function MouseDown(X, Y: Single): Boolean;
    procedure MouseMove(X, Y: Single);
    procedure MouseUp;
  end;

function Box(X1, Y1, X2, Y2: Single): TBox;
function BoxW(const R: TBox): Single;
function BoxH(const R: TBox): Single;
function InBox(const R: TBox; X, Y: Single): Boolean;

{ Text drawn every frame goes through a sprite cache: each distinct
  (font, size, style, colour, text) is rendered once into a small transparent
  bitmap and blended afterwards. Returns the text width. }
function DrawTextCached(B: TBGRABitmap; X, Y: Single; const S, FontName: string;
  Size: Integer; Style: TFontStyles; C: TBGRAPixel; Align: TAlignment;
  DoDraw: Boolean = True): Single;
{ Cached version of BGRAView.DrawSymbol (K + subscript) }
function SymbolCached(B: TBGRABitmap; X, Y: Single; const Base, Sub: string;
  C: TBGRAPixel; Size: Integer; DoDraw: Boolean = True): Single;

{ HQ = fine antialiasing (slow, for cached layers, not sprite-cached);
  otherwise GDI antialiasing through the sprite cache }
procedure UseFont(B: TBGRABitmap; Size: Integer; Style: TFontStyles = [];
  const Name: string = UIFont; HQ: Boolean = False);
procedure Txt(B: TBGRABitmap; X, Y: Single; const S: string; C: LongWord;
  Size: Integer; Style: TFontStyles = []; Align: TAlignment = taLeftJustify;
  Alpha: Byte = 255; HQ: Boolean = False);
function TxtW(B: TBGRABitmap; const S: string; Size: Integer;
  Style: TFontStyles = []): Single;
function WrapLine(B: TBGRABitmap; const S: string; MaxW: Single): TStringArray;

// One item per line:  "## title"  "- bullet"  "> note"  "` code"  blank = gap.
// A colour tag p / i / d / g / w in braces at the start of a line colours it
// Kp / Ki / Kd / gold / white. Text wraps at spaces (Thai: put spaces
// between phrases). Returns the bottom Y.
function DrawRichText(B: TBGRABitmap; X, Y, W: Single; const Text: string;
  Size: Integer = 17): Single;

procedure Panel(B: TBGRABitmap; const R: TBox; Fill: LongWord = ClrPanel;
  Radius: Single = 10; Alpha: Byte = 255);
procedure Chip(B: TBGRABitmap; X, Y: Single; const S: string; C: LongWord;
  Size: Integer = 14; Filled: Boolean = False);
function Fmt(V: Double; Decimals: Integer = 2): string;

function MakePlot(const R: TBox; X0, X1, Y0, Y1: Double): TPlotBox;
function PX(const P: TPlotBox; V: Double): Single;
function PY(const P: TPlotBox; V: Double): Single;
procedure DrawPlotGrid(B: TBGRABitmap; const P: TPlotBox; YStep: Double;
  XStep: Double = 0; const XUnit: string = 's');
{ Series with uniform X spacing: Data[i] at X = XStart + i*XStep, first Count points }
procedure DrawSeries(B: TBGRABitmap; const P: TPlotBox; const Data: TDoubleArray;
  Count: Integer; XStart, XStep: Double; C: LongWord; W: Single; Alpha: Byte = 255);
procedure FillUnder(B: TBGRABitmap; const P: TPlotBox; const Data: TDoubleArray;
  Count: Integer; XStart, XStep, Base: Double; C: LongWord; Alpha: Byte);
procedure DashH(B: TBGRABitmap; const P: TPlotBox; V: Double; C: LongWord;
  Alpha: Byte = 150);

function ArcPts(CX, CY, R, StartDeg, SweepDeg, T0, T1: Single): ArrayOfTPointF;
{ 270 degree gauge in the knob style of PID Tuning Explorer }
procedure Gauge(B: TBGRABitmap; CX, CY, R: Single; Frac: Double; C: LongWord;
  const ValueText, Caption: string; MarkFrac: Double = -1);

implementation

function Box(X1, Y1, X2, Y2: Single): TBox;
begin
  Result.X1 := X1;
  Result.Y1 := Y1;
  Result.X2 := X2;
  Result.Y2 := Y2;
end;

function BoxW(const R: TBox): Single;
begin
  Result := R.X2 - R.X1;
end;

function BoxH(const R: TBox): Single;
begin
  Result := R.Y2 - R.Y1;
end;

function InBox(const R: TBox; X, Y: Single): Boolean;
begin
  Result := (X >= R.X1) and (X <= R.X2) and (Y >= R.Y1) and (Y <= R.Y2);
end;

procedure UseFont(B: TBGRABitmap; Size: Integer; Style: TFontStyles;
  const Name: string; HQ: Boolean);
begin
  B.FontName := Name;
  B.FontStyle := Style;
  B.FontHeight := Size;
  if HQ then
    B.FontQuality := fqFineAntialiasing
  else
    B.FontQuality := fqSystem;
end;

type
  TTextSprite = class
    Bmp: TBGRABitmap; // nil when there is nothing to draw
    W: Integer;       // advance width as TextSize reports it
    Pad: Integer;     // margin left and right for italic overhang
    destructor Destroy; override;
  end;

const
  MaxSprites = 3000;

var
  GSprites: TFPHashObjectList;
  GMeasure: TBGRABitmap;

destructor TTextSprite.Destroy;
begin
  Bmp.Free;
  inherited Destroy;
end;

function StyleCode(Style: TFontStyles): Integer;
begin
  Result := Ord(fsBold in Style) + 2 * Ord(fsItalic in Style) +
    4 * Ord(fsUnderline in Style);
end;

{ Measure-only sprites (WithBitmap = False) skip the rendering }
function GetSprite(const S, FontName: string; Size: Integer; Style: TFontStyles;
  C: TBGRAPixel; WithBitmap: Boolean): TTextSprite;
var
  Key: string;
  Sz: TSize;
begin
  if WithBitmap then
    Key := Format('d%.2x%.2x%.2x%.2x', [C.red, C.green, C.blue, C.alpha])
  else
    Key := 'm';
  Key := Key + FontName + #1 + IntToStr(Size) + #1 + IntToStr(StyleCode(Style)) + #1 + S;
  if Length(Key) > 255 then
    Exit(nil); // TFPHashObjectList names are short strings
  Result := TTextSprite(GSprites.Find(Key));
  if Result <> nil then
    Exit;
  if GSprites.Count >= MaxSprites then
    GSprites.Clear;

  if GMeasure = nil then
    GMeasure := TBGRABitmap.Create(1, 1);
  UseFont(GMeasure, Size, Style, FontName);
  Sz := GMeasure.TextSize(S);
  Result := TTextSprite.Create;
  Result.W := Sz.cx;
  Result.Pad := Max(2, Size div 4);
  if WithBitmap and (Sz.cx > 0) and (Sz.cy > 0) then
  begin
    Result.Bmp := TBGRABitmap.Create(Sz.cx + 2 * Result.Pad, Sz.cy);
    UseFont(Result.Bmp, Size, Style, FontName);
    Result.Bmp.TextOut(Result.Pad, 0, S, C);
  end;
  GSprites.Add(Key, Result);
end;

function DrawTextCached(B: TBGRABitmap; X, Y: Single; const S, FontName: string;
  Size: Integer; Style: TFontStyles; C: TBGRAPixel; Align: TAlignment;
  DoDraw: Boolean): Single;
var
  Sp: TTextSprite;
begin
  Result := 0;
  if S = '' then
    Exit;
  Sp := GetSprite(S, FontName, Size, Style, C, DoDraw);
  if Sp = nil then
  begin
    // too long for the cache: draw directly
    UseFont(B, Size, Style, FontName);
    Result := B.TextSize(S).cx;
    if DoDraw then
      B.TextOut(X, Y, S, C, Align);
    Exit;
  end;
  Result := Sp.W;
  if DoDraw and (Sp.Bmp <> nil) then
  begin
    case Align of
      taCenter: X := X - Sp.W / 2;
      taRightJustify: X := X - Sp.W;
    end;
    B.PutImage(Round(X) - Sp.Pad, Round(Y), Sp.Bmp, dmDrawWithTransparency);
  end;
end;

function SymbolCached(B: TBGRABitmap; X, Y: Single; const Base, Sub: string;
  C: TBGRAPixel; Size: Integer; DoDraw: Boolean): Single;
begin
  Result := DrawTextCached(B, X, Y, Base, MathFont, Size, [fsItalic], C,
    taLeftJustify, DoDraw);
  if Sub <> '' then
    Result := Result + DrawTextCached(B, X + Result, Y + Size * 0.45, Sub, MathFont,
      Round(Size * 0.62), [fsItalic], C, taLeftJustify, DoDraw);
end;

procedure Txt(B: TBGRABitmap; X, Y: Single; const S: string; C: LongWord;
  Size: Integer; Style: TFontStyles; Align: TAlignment; Alpha: Byte; HQ: Boolean);
begin
  if HQ then
  begin
    UseFont(B, Size, Style, UIFont, True);
    B.TextOut(X, Y, S, HexPixel(C, Alpha), Align);
  end
  else
    DrawTextCached(B, X, Y, S, UIFont, Size, Style, HexPixel(C, Alpha), Align);
end;

function TxtW(B: TBGRABitmap; const S: string; Size: Integer; Style: TFontStyles): Single;
begin
  Result := DrawTextCached(B, 0, 0, S, UIFont, Size, Style, BGRAWhite,
    taLeftJustify, False);
end;

function Fmt(V: Double; Decimals: Integer): string;
begin
  Result := FloatToStrF(V, ffFixed, 15, Decimals);
end;

{ Thai above/below marks must stay attached to their base consonant }
function IsCombining(const S: string; I: Integer): Boolean;
var
  CP: Integer;
begin
  Result := False;
  if (I + 2 > Length(S)) or (Ord(S[I]) <> $E0) then
    Exit;
  CP := ((Ord(S[I]) and $0F) shl 12) or ((Ord(S[I + 1]) and $3F) shl 6) or
    (Ord(S[I + 2]) and $3F);
  Result := (CP = $0E31) or ((CP >= $0E34) and (CP <= $0E3A)) or
    ((CP >= $0E47) and (CP <= $0E4E));
end;

function CPLen(C: Char): Integer;
begin
  case Ord(C) of
    $00..$7F: Result := 1;
    $C0..$DF: Result := 2;
    $E0..$EF: Result := 3;
    $F0..$F7: Result := 4;
  else
    Result := 1;
  end;
end;

{ Longest prefix (in bytes) of S that fits MaxW, cut only between clusters }
function FitPrefix(B: TBGRABitmap; const S: string; MaxW: Single): Integer;
var
  I, Next: Integer;
begin
  Result := 0;
  I := 1;
  while I <= Length(S) do
  begin
    Next := I + CPLen(S[I]);
    while (Next <= Length(S)) and IsCombining(S, Next) do
      Inc(Next, CPLen(S[Next]));
    if (Result > 0) and (B.TextSize(Copy(S, 1, Next - 1)).cx > MaxW) then
      Exit;
    Result := Next - 1;
    I := Next;
  end;
end;

function WrapLine(B: TBGRABitmap; const S: string; MaxW: Single): TStringArray;
var
  Words: TStringArray;
  Cur, Test: string;
  I, N, Cut: Integer;

  procedure Add(const L: string);
  begin
    SetLength(Result, N + 1);
    Result[N] := L;
    Inc(N);
  end;

begin
  Result := nil;
  N := 0;
  Words := S.Split([' ']);
  Cur := '';
  for I := 0 to High(Words) do
  begin
    if Cur = '' then
      Test := Words[I]
    else
      Test := Cur + ' ' + Words[I];
    if B.TextSize(Test).cx <= MaxW then
      Cur := Test
    else
    begin
      if Cur <> '' then
        Add(Cur);
      Cur := Words[I];
      while (Cur <> '') and (B.TextSize(Cur).cx > MaxW) do
      begin
        Cut := FitPrefix(B, Cur, MaxW);
        Add(Copy(Cur, 1, Cut));
        Delete(Cur, 1, Cut);
      end;
    end;
  end;
  if Cur <> '' then
    Add(Cur);
end;

function DrawRichText(B: TBGRABitmap; X, Y, W: Single; const Text: string;
  Size: Integer): Single;
var
  Lines: TStringList;
  Parts: TStringArray;
  I, J, Sz: Integer;
  L: string;
  C: LongWord;
  Style: TFontStyles;
  FontName: string;
  Indent, LineH, Y0: Single;
  Kind: Char;
begin
  Lines := TStringList.Create;
  try
    Lines.Text := Text;
    for I := 0 to Lines.Count - 1 do
    begin
      L := Lines[I];
      if L = '`' then
        L := '` ';
      if Trim(L) = '' then
      begin
        Y := Y + Size * 0.55;
        Continue;
      end;
      Kind := ' ';
      Sz := Size;
      Style := [];
      FontName := UIFont;
      C := ClrBody;
      Indent := 0;
      if Copy(L, 1, 3) = '## ' then
      begin
        Kind := '#';
        Delete(L, 1, 3);
        Sz := Size + 5;
        Style := [fsBold];
        C := ClrText;
        Y := Y + 4;
      end
      else if Copy(L, 1, 2) = '- ' then
      begin
        Kind := '-';
        Delete(L, 1, 2);
        Indent := 22;
      end
      else if Copy(L, 1, 2) = '> ' then
      begin
        Kind := '>';
        Delete(L, 1, 2);
        Indent := 16;
        C := ClrDim;
      end
      else if Copy(L, 1, 2) = '` ' then
      begin
        Kind := '`';
        Delete(L, 1, 2);
        Sz := Size - 3;
        FontName := CodeFont;
        C := ClrCode;
        Indent := 12;
      end;
      if (Length(L) >= 3) and (L[1] = '{') and (L[3] = '}') then
      begin
        case L[2] of
          'p': C := ClrKp;
          'i': C := ClrKi;
          'd': C := ClrKd;
          'g': C := ClrGold;
          'w': C := ClrText;
        end;
        Delete(L, 1, 3);
      end;

      UseFont(B, Sz, Style, FontName, True);
      if Kind = '`' then
      begin
        LineH := Sz * 1.3;
        B.FillRectAntialias(X, Y - 1, X + W, Y + LineH, HexPixel(ClrCodeBg));
        B.TextOut(X + Indent, Y + 1, L, HexPixel(C));
        Y := Y + LineH;
        Continue;
      end;

      LineH := Sz * 1.5;
      Parts := WrapLine(B, L, W - Indent);
      Y0 := Y;
      if Kind = '-' then
        B.FillEllipseAntialias(X + 8, Y + Sz * 0.62, 3, 3, HexPixel(C));
      for J := 0 to High(Parts) do
      begin
        B.TextOut(X + Indent, Y, Parts[J], HexPixel(C));
        Y := Y + LineH;
      end;
      if Kind = '>' then
        B.FillRectAntialias(X + 2, Y0 + 3, X + 5, Y - Sz * 0.3, HexPixel(ClrGold, 180));
      if Kind = '#' then
        Y := Y + 2;
    end;
  finally
    Lines.Free;
  end;
  Result := Y;
end;

procedure Panel(B: TBGRABitmap; const R: TBox; Fill: LongWord; Radius: Single; Alpha: Byte);
begin
  B.FillRoundRectAntialias(R.X1, R.Y1, R.X2, R.Y2, Radius, Radius, HexPixel(Fill, Alpha));
end;

procedure Chip(B: TBGRABitmap; X, Y: Single; const S: string; C: LongWord;
  Size: Integer; Filled: Boolean);
var
  W: Single;
begin
  W := TxtW(B, S, Size);
  if Filled then
    B.FillRoundRectAntialias(X, Y, X + W + 18, Y + Size + 10, (Size + 10) / 2,
      (Size + 10) / 2, HexPixel(C, 60));
  B.RoundRectAntialias(X, Y, X + W + 18, Y + Size + 10, (Size + 10) / 2,
    (Size + 10) / 2, HexPixel(C, 200), 1.2);
  Txt(B, X + 9, Y + 4, S, C, Size);
end;

{ Plots }

function MakePlot(const R: TBox; X0, X1, Y0, Y1: Double): TPlotBox;
begin
  Result.R := R;
  Result.X0 := X0;
  Result.X1 := X1;
  Result.Y0 := Y0;
  Result.Y1 := Y1;
end;

function PX(const P: TPlotBox; V: Double): Single;
begin
  Result := P.R.X1 + (V - P.X0) / (P.X1 - P.X0) * BoxW(P.R);
end;

function PY(const P: TPlotBox; V: Double): Single;
begin
  V := EnsureRange(V, P.Y0 - (P.Y1 - P.Y0) * 0.05, P.Y1 + (P.Y1 - P.Y0) * 0.05);
  Result := P.R.Y2 - (V - P.Y0) / (P.Y1 - P.Y0) * BoxH(P.R);
end;

procedure DrawPlotGrid(B: TBGRABitmap; const P: TPlotBox; YStep, XStep: Double;
  const XUnit: string);
var
  V: Double;
  Y, X: Single;
  Dec: Integer;
begin
  Dec := Max(0, Ceil(-Log10(YStep) - 1e-9));
  V := Ceil(P.Y0 / YStep - 1e-9) * YStep;
  while V <= P.Y1 + 1e-9 do
  begin
    Y := PY(P, V);
    if Abs(V) < 1e-9 then
      B.DrawLineAntialias(P.R.X1, Y, P.R.X2, Y, HexPixel(ClrDim, 90), 1)
    else
      B.DrawLineAntialias(P.R.X1, Y, P.R.X2, Y, HexPixel(ClrGrid), 1);
    Txt(B, P.R.X1 - 6, Y - 8, Fmt(V, Dec), ClrDim, 12, [], taRightJustify);
    V := V + YStep;
  end;
  if XStep > 0 then
  begin
    V := Ceil(P.X0 / XStep - 1e-9) * XStep;
    while V <= P.X1 + 1e-9 do
    begin
      X := PX(P, V);
      Txt(B, X, P.R.Y2 + 4, Fmt(V, 0) + XUnit, ClrDim, 12, [], taCenter);
      V := V + XStep;
    end;
  end;
end;

procedure DrawSeries(B: TBGRABitmap; const P: TPlotBox; const Data: TDoubleArray;
  Count: Integer; XStart, XStep: Double; C: LongWord; W: Single; Alpha: Byte);
var
  Pts: ArrayOfTPointF;
  I: Integer;
begin
  Count := Min(Count, Length(Data));
  if Count < 2 then
    Exit;
  SetLength(Pts, Count);
  for I := 0 to Count - 1 do
    Pts[I] := PointF(PX(P, XStart + I * XStep), PY(P, Data[I]));
  // dense smooth curves: bevel joins look the same as round ones but avoid
  // an arc at every one of the hundreds of vertices
  B.LineCap := pecRound;
  B.JoinStyle := pjsBevel;
  B.DrawPolyLineAntialias(Pts, HexPixel(C, Alpha), W);
end;

procedure FillUnder(B: TBGRABitmap; const P: TPlotBox; const Data: TDoubleArray;
  Count: Integer; XStart, XStep, Base: Double; C: LongWord; Alpha: Byte);
var
  Pts: ArrayOfTPointF;
  I: Integer;
begin
  Count := Min(Count, Length(Data));
  if Count < 2 then
    Exit;
  SetLength(Pts, Count + 2);
  for I := 0 to Count - 1 do
    Pts[I] := PointF(PX(P, XStart + I * XStep), PY(P, Data[I]));
  Pts[Count] := PointF(PX(P, XStart + (Count - 1) * XStep), PY(P, Base));
  Pts[Count + 1] := PointF(PX(P, XStart), PY(P, Base));
  B.FillPolyAntialias(Pts, HexPixel(C, Alpha));
end;

procedure DashH(B: TBGRABitmap; const P: TPlotBox; V: Double; C: LongWord; Alpha: Byte);
begin
  B.PenStyle := psDash;
  B.DrawLineAntialias(P.R.X1, PY(P, V), P.R.X2, PY(P, V), HexPixel(C, Alpha), 1.3);
  B.PenStyle := psSolid;
end;

function ArcPts(CX, CY, R, StartDeg, SweepDeg, T0, T1: Single): ArrayOfTPointF;
var
  I, N: Integer;
  A: Single;
begin
  N := Max(2, Round(96 * Abs(T1 - T0)) + 1);
  SetLength(Result, N);
  for I := 0 to N - 1 do
  begin
    A := DegToRad(StartDeg - SweepDeg * (T0 + (T1 - T0) * I / (N - 1)));
    Result[I] := PointF(CX + R * Cos(A), CY - R * Sin(A));
  end;
end;

procedure Gauge(B: TBGRABitmap; CX, CY, R: Single; Frac: Double; C: LongWord;
  const ValueText, Caption: string; MarkFrac: Double);
var
  A, TW: Single;
begin
  Frac := EnsureRange(Frac, 0, 1);
  TW := R * 0.1;
  B.LineCap := pecRound;
  B.DrawPolyLineAntialias(ArcPts(CX, CY, R, 225, 270, 0, 1), HexPixel(ClrKnobTrack), TW);
  if Frac > 0.002 then
    B.DrawPolyLineAntialias(ArcPts(CX, CY, R, 225, 270, 0, Frac), HexPixel(C), TW);
  B.FillEllipseAntialias(CX, CY, R * 0.74, R * 0.74, HexPixel(ClrKnobFace));
  B.EllipseAntialias(CX, CY, R * 0.74, R * 0.74, HexPixel(C), R * 0.04);
  if MarkFrac >= 0 then
  begin
    A := DegToRad(225 - 270 * EnsureRange(MarkFrac, 0, 1));
    B.DrawLineAntialias(CX + R * 0.82 * Cos(A), CY - R * 0.82 * Sin(A),
      CX + R * 1.18 * Cos(A), CY - R * 1.18 * Sin(A), BGRAWhite, 2.5);
  end;
  A := DegToRad(225 - 270 * Frac);
  B.DrawLineAntialias(CX, CY, CX + R * 0.6 * Cos(A), CY - R * 0.6 * Sin(A),
    BGRAWhite, R * 0.05);
  B.FillEllipseAntialias(CX, CY, R * 0.08, R * 0.08, BGRAWhite);
  Txt(B, CX, CY + R * 0.22, ValueText, ClrText, Round(R * 0.26), [fsBold], taCenter);
  Txt(B, CX, CY + R * 0.78, Caption, ClrDim, Round(R * 0.17), [], taCenter);
end;

{ TSlider }

constructor TSlider.Create(const ASymbol, ASub: string; AMin, AMax, AValue: Double;
  AColor: LongWord; ADecimals: Integer);
begin
  inherited Create;
  Symbol := ASymbol;
  Sub := ASub;
  MinV := AMin;
  MaxV := AMax;
  Value := EnsureRange(AValue, AMin, AMax);
  Color := AColor;
  Decimals := ADecimals;
end;

procedure TSlider.SetValue(V: Double);
begin
  V := EnsureRange(V, MinV, MaxV);
  if V = Value then
    Exit;
  Value := V;
  if Assigned(OnChange) then
    OnChange(Self);
end;

procedure TSlider.Draw(B: TBGRABitmap);
var
  TX1, TX2, CY, KX, F: Single;
begin
  CY := (R.Y1 + R.Y2) / 2;
  if Sub <> '' then
    SymbolCached(B, R.X1, CY - 13, Symbol, Sub, HexPixel(Color), 24)
  else
    Txt(B, R.X1, CY - 11, Symbol, Color, 16, [fsBold]);
  TX1 := R.X1 + 92;
  TX2 := R.X2 - 96;
  F := (Value - MinV) / Max(1e-12, MaxV - MinV);
  KX := TX1 + (TX2 - TX1) * F;
  B.LineCap := pecRound;
  B.DrawLineAntialias(TX1, CY, TX2, CY, HexPixel(ClrKnobTrack), 6);
  B.DrawLineAntialias(TX1, CY, KX, CY, HexPixel(Color), 6);
  if Dragging then
    B.FillEllipseAntialias(KX, CY, 12, 12, HexPixel(Color, 70));
  B.FillEllipseAntialias(KX, CY, 8, 8, HexPixel(ClrKnobFace));
  B.EllipseAntialias(KX, CY, 8, 8, HexPixel(Color), 2.5);
  Txt(B, R.X2, CY - 11, Fmt(Value, Decimals) + Units, Color, 17, [fsBold], taRightJustify);
end;

function TSlider.MouseDown(X, Y: Single): Boolean;
begin
  Result := InBox(R, X, Y);
  if Result then
  begin
    Dragging := True;
    MouseMove(X, Y);
  end;
end;

procedure TSlider.MouseMove(X, Y: Single);
var
  TX1, TX2: Single;
begin
  if not Dragging then
    Exit;
  TX1 := R.X1 + 92;
  TX2 := R.X2 - 96;
  SetValue(MinV + (MaxV - MinV) * EnsureRange((X - TX1) / (TX2 - TX1), 0, 1));
end;

procedure TSlider.MouseUp;
begin
  Dragging := False;
end;

initialization
  GSprites := TFPHashObjectList.Create(True);

finalization
  GSprites.Free;
  GMeasure.Free;

end.
