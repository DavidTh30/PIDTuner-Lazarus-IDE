unit HeatmapView;

{ THeatmap - Kp x Kd score grid. Column = Kp (left to right), Row = Kd
  (Row 0 at the bottom). Click or drag to select a cell; hover reports it. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Controls, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore;

type
  TCellEvent = procedure(Sender: TObject; Col, Row: Integer) of object;

  TCellBox = record
    X1, Y1, X2, Y2: Single;
  end;

  THeatmap = class(TBGRAView)
  private
    FGrid: TScoreGrid;
    FCols, FRows: Integer;
    FSelCol, FSelRow: Integer;
    FHotCol, FHotRow: Integer;
    FOnSelect, FOnHover: TCellEvent;
    function PlotBox: TCellBox;
    function CellBox(Col, Row: Integer): TCellBox;
    function CellAt(X, Y: Integer; out Col, Row: Integer): Boolean;
    procedure SetHot(Col, Row: Integer);
    procedure PickAt(X, Y: Integer);
  protected
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
  public
    constructor Create(AOwner: TComponent); override;
    procedure SetGrid(const AGrid: TScoreGrid);
    procedure Select(Col, Row: Integer); // no OnSelect
    procedure Render(ABmp: TBGRABitmap); override;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property SelCol: Integer read FSelCol;
    property SelRow: Integer read FSelRow;
    property OnSelect: TCellEvent read FOnSelect write FOnSelect;
    property OnHover: TCellEvent read FOnHover write FOnHover;
  end;

implementation

const
  MarginL = 48;
  MarginR = 8;
  MarginT = 8;
  MarginB = 40;
  LabelSize = 26;

{ THeatmap }

constructor THeatmap.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csCaptureMouse];
  Cursor := crHandPoint;
  FCols := 10;
  FRows := 8;
  FSelCol := -1;
  FSelRow := -1;
  FHotCol := -1;
  FHotRow := -1;
end;

procedure THeatmap.SetGrid(const AGrid: TScoreGrid);
begin
  FGrid := AGrid;
  FCols := Length(AGrid);
  if FCols > 0 then
    FRows := Length(AGrid[0])
  else
    FRows := 0;
  Invalidate;
end;

procedure THeatmap.Select(Col, Row: Integer);
begin
  if (Col = FSelCol) and (Row = FSelRow) then
    Exit;
  FSelCol := Col;
  FSelRow := Row;
  Invalidate;
end;

function THeatmap.PlotBox: TCellBox;
begin
  Result.X1 := MarginL;
  Result.Y1 := MarginT;
  Result.X2 := Width - MarginR;
  Result.Y2 := Height - MarginB;
end;

function THeatmap.CellBox(Col, Row: Integer): TCellBox;
var
  P: TCellBox;
  CW, CH, Gap: Single;
  ScreenRow: Integer;
begin
  P := PlotBox;
  CW := (P.X2 - P.X1) / Max(1, FCols);
  CH := (P.Y2 - P.Y1) / Max(1, FRows);
  Gap := Min(CW, CH) * 0.09;
  ScreenRow := FRows - 1 - Row;
  Result.X1 := P.X1 + Col * CW + Gap / 2;
  Result.X2 := P.X1 + (Col + 1) * CW - Gap / 2;
  Result.Y1 := P.Y1 + ScreenRow * CH + Gap / 2;
  Result.Y2 := P.Y1 + (ScreenRow + 1) * CH - Gap / 2;
end;

function THeatmap.CellAt(X, Y: Integer; out Col, Row: Integer): Boolean;
var
  P: TCellBox;
begin
  P := PlotBox;
  Result := (FCols > 0) and (FRows > 0) and (X >= P.X1) and (X < P.X2)
    and (Y >= P.Y1) and (Y < P.Y2);
  if not Result then
  begin
    Col := -1;
    Row := -1;
    Exit;
  end;
  Col := EnsureRange(Trunc((X - P.X1) / (P.X2 - P.X1) * FCols), 0, FCols - 1);
  Row := FRows - 1 - EnsureRange(Trunc((Y - P.Y1) / (P.Y2 - P.Y1) * FRows), 0, FRows - 1);
end;

procedure THeatmap.SetHot(Col, Row: Integer);
begin
  if (Col = FHotCol) and (Row = FHotRow) then
    Exit;
  FHotCol := Col;
  FHotRow := Row;
  Invalidate;
  if Assigned(FOnHover) then
    FOnHover(Self, Col, Row);
end;

procedure THeatmap.PickAt(X, Y: Integer);
var
  C, R: Integer;
begin
  if not CellAt(X, Y, C, R) or ((C = FSelCol) and (R = FSelRow)) then
    Exit;
  Select(C, R);
  if Assigned(FOnSelect) then
    FOnSelect(Self, C, R);
end;

procedure THeatmap.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
    PickAt(X, Y);
end;

procedure THeatmap.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  C, R: Integer;
begin
  inherited MouseMove(Shift, X, Y);
  CellAt(X, Y, C, R);
  SetHot(C, R);
  if ssLeft in Shift then
    PickAt(X, Y);
end;

procedure THeatmap.MouseLeave;
begin
  inherited MouseLeave;
  SetHot(-1, -1);
end;

procedure THeatmap.Render(ABmp: TBGRABitmap);
var
  Col, Row: Integer;
  B, P: TCellBox;
  Score, W: Single;
  Gold: TBGRAPixel;
begin
  for Col := 0 to FCols - 1 do
    for Row := 0 to FRows - 1 do
    begin
      B := CellBox(Col, Row);
      if Col < Length(FGrid) then
        Score := FGrid[Col, Row]
      else
        Score := 0;
      ABmp.FillRoundRectAntialias(B.X1, B.Y1, B.X2, B.Y2, 3, 3, HexPixel(HeatColor(Score)));
      if (Col = FHotCol) and (Row = FHotRow) then
        ABmp.RoundRectAntialias(B.X1, B.Y1, B.X2, B.Y2, 3, 3, BGRA(255, 255, 255, 130), 1.5);
    end;

  if (FSelCol >= 0) and (FSelRow >= 0) and (FSelCol < FCols) and (FSelRow < FRows) then
  begin
    B := CellBox(FSelCol, FSelRow);
    Gold := HexPixel(HeatStops[High(HeatStops)]);
    ABmp.RoundRectAntialias(B.X1 - 3, B.Y1 - 3, B.X2 + 3, B.Y2 + 3, 5, 5, Gold, 6);
    ABmp.RoundRectAntialias(B.X1 + 5, B.Y1 + 5, B.X2 - 5, B.Y2 - 5, 2, 2, HexPixel(ClrText), 2.5);
  end;

  // Axis labels: K_d on the left, K_p underneath
  P := PlotBox;
  W := DrawSymbol(ABmp, 0, 0, 'K', 'd', HexPixel(ClrKd), LabelSize, False);
  DrawSymbol(ABmp, (MarginL - W) / 2, (P.Y1 + P.Y2) / 2 - LabelSize / 2, 'K', 'd',
    HexPixel(ClrKd), LabelSize);
  W := DrawSymbol(ABmp, 0, 0, 'K', 'p', HexPixel(ClrKp), LabelSize, False);
  DrawSymbol(ABmp, (P.X1 + P.X2 - W) / 2, P.Y2 + 4, 'K', 'p', HexPixel(ClrKp), LabelSize);
end;

end.
