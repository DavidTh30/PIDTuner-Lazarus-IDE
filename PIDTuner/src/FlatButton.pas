unit FlatButton;

{ TFlatButton - small dark rounded button drawn with BGRABitmap,
  with an optional icon: biCamera (PNG) or biRecord (GIF, red dot / stop square). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore;

type
  TButtonIcon = (biNone, biCamera, biRecord);

  TFlatButton = class(TBGRAView)
  private
    FHot: Boolean;
    FActive: Boolean;
    FIcon: TButtonIcon;
    FText: string;
    procedure SetActive(AValue: Boolean);
    procedure SetText(const AValue: string);
  protected
    procedure MouseEnter; override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure Render(ABmp: TBGRABitmap); override;
    property Icon: TButtonIcon read FIcon write FIcon;
    property Text: string read FText write SetText;
    property Active: Boolean read FActive write SetActive; // recording
  end;

implementation

constructor TFlatButton.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  Cursor := crHandPoint;
end;

procedure TFlatButton.SetActive(AValue: Boolean);
begin
  if FActive = AValue then
    Exit;
  FActive := AValue;
  Invalidate;
end;

procedure TFlatButton.SetText(const AValue: string);
begin
  if FText = AValue then
    Exit;
  FText := AValue;
  Invalidate;
end;

procedure TFlatButton.MouseEnter;
begin
  inherited MouseEnter;
  FHot := True;
  Invalidate;
end;

procedure TFlatButton.MouseLeave;
begin
  inherited MouseLeave;
  FHot := False;
  Invalidate;
end;

procedure TFlatButton.Render(ABmp: TBGRABitmap);
var
  W, H, CX, CY, TX: Single;
  Border: TBGRAPixel;
begin
  W := ABmp.Width;
  H := ABmp.Height;
  if FActive then
    Border := HexPixel(ClrBad)
  else if FHot then
    Border := HexPixel(HeatStops[High(HeatStops)])
  else
    Border := HexPixel(ClrKnobTrack);
  ABmp.FillRoundRectAntialias(1, 1, W - 2, H - 2, 8, 8, HexPixel(ClrPanel));
  ABmp.RoundRectAntialias(1, 1, W - 2, H - 2, 8, 8, Border, 1.5);

  CX := 18;
  CY := H / 2;
  case FIcon of
    biCamera:
      begin
        ABmp.FillRoundRectAntialias(CX - 9, CY - 6, CX + 9, CY + 7, 2, 2, HexPixel(ClrText));
        ABmp.FillRectAntialias(CX - 4, CY - 9, CX + 3, CY - 5, HexPixel(ClrText));
        ABmp.FillEllipseAntialias(CX, CY + 0.5, 4, 4, HexPixel(ClrPanel));
        ABmp.FillEllipseAntialias(CX, CY + 0.5, 2, 2, HexPixel(ClrText));
      end;
    biRecord:
      if FActive then
        ABmp.FillRoundRectAntialias(CX - 6, CY - 6, CX + 6, CY + 6, 2, 2, HexPixel(ClrBad))
      else
        ABmp.FillEllipseAntialias(CX, CY, 6.5, 6.5, HexPixel(ClrBad));
  end;
  if FIcon = biNone then
    TX := W / 2
  else
    TX := (W + 30) / 2;
  ABmp.FontName := 'Segoe UI';
  ABmp.FontStyle := [fsBold];
  ABmp.FontHeight := 15;
  ABmp.FontQuality := fqFineAntialiasing;
  ABmp.TextOut(TX, CY - 10, FText, HexPixel(ClrText), taCenter);
end;

end.
