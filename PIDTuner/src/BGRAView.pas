unit BGRAView;

{ Base class for controls that render themselves into a TBGRABitmap,
  plus shared drawing helpers (theme colours, subscripted math symbols). }

{$mode objfpc}{$H+}

interface

uses
  Classes, Controls, Graphics, BGRABitmap, BGRABitmapTypes;

const
  MathFont = 'Cambria';

type
  { Render is separate from Paint so views can also be drawn off-screen
    (see TMainForm.SaveSnapshot). }
  TBGRAView = class(TGraphicControl)
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Render(ABmp: TBGRABitmap); virtual; abstract;
  end;

function HexPixel(C: LongWord; Alpha: Byte = 255): TBGRAPixel;
function HexColor(C: LongWord): TColor;
procedure SetMathFont(ABmp: TBGRABitmap; Size: Integer; Style: TFontStyles);

{ Draws Base with a subscript (e.g. K + p) with its top-left at X,Y.
  Returns the total width; with DoDraw = False it only measures. }
function DrawSymbol(ABmp: TBGRABitmap; X, Y: Single; const Base, Sub: string;
  C: TBGRAPixel; Size: Integer; DoDraw: Boolean = True): Single;

implementation

uses
  PIDCore;

function HexPixel(C: LongWord; Alpha: Byte): TBGRAPixel;
begin
  Result := BGRA((C shr 16) and $FF, (C shr 8) and $FF, C and $FF, Alpha);
end;

function HexColor(C: LongWord): TColor;
begin
  Result := RGBToColor((C shr 16) and $FF, (C shr 8) and $FF, C and $FF);
end;

procedure SetMathFont(ABmp: TBGRABitmap; Size: Integer; Style: TFontStyles);
begin
  ABmp.FontName := MathFont;
  ABmp.FontStyle := Style;
  ABmp.FontHeight := Size;
  ABmp.FontQuality := fqFineAntialiasing;
end;

function DrawSymbol(ABmp: TBGRABitmap; X, Y: Single; const Base, Sub: string;
  C: TBGRAPixel; Size: Integer; DoDraw: Boolean): Single;
begin
  SetMathFont(ABmp, Size, [fsItalic]);
  Result := ABmp.TextSize(Base).cx;
  if DoDraw then
    ABmp.TextOut(X, Y, Base, C);
  if Sub <> '' then
  begin
    SetMathFont(ABmp, Round(Size * 0.62), [fsItalic]);
    if DoDraw then
      ABmp.TextOut(X + Result, Y + Size * 0.45, Sub, C);
    Result := Result + ABmp.TextSize(Sub).cx;
  end;
end;

{ TBGRAView }

constructor TBGRAView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque];
end;

procedure TBGRAView.Paint;
var
  Bmp: TBGRABitmap;
begin
  if (ClientWidth <= 0) or (ClientHeight <= 0) then
    Exit;
  Bmp := TBGRABitmap.Create(ClientWidth, ClientHeight, HexPixel(ClrBackground));
  try
    Render(Bmp);
    Bmp.Draw(Canvas, 0, 0, True);
  finally
    Bmp.Free;
  end;
end;

end.
