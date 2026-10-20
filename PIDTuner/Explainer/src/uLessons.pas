{ PID Explainer - lesson pages. Each page draws a cached static layer
  (explanation text, panels) and a dynamic layer (animation, plots, sliders)
  every frame. }
unit uLessons;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LCLType, Graphics, BGRABitmap, BGRABitmapTypes,
  PIDCore, BGRAView, PlotViews, HeatmapView, uDrawKit, uSimKit, uScenarios;

const
  LeftX = 32;
  LeftW = 540;
  RightX1 = 600;
  RightX2 = 1248;
  ContentY = 92;
  ContentY2 = 700;

type
  TLesson = class
  protected
    FSliders: TFPList;
    FTime: Double;
    FText: string;
    FTextSize: Integer;
    function AddSlider(const ASym, ASub: string; AMin, AMax, AValue: Double;
      AColor: LongWord; ADecimals, Slot, Slots: Integer): TSlider;
    function Slider(I: Integer): TSlider;
    procedure SliderChanged(Sender: TObject); virtual;
  public
    Title, TabName, Hints: string;
    constructor Create; virtual;
    destructor Destroy; override;
    procedure Enter; virtual;
    procedure Update(Dt: Double); virtual;
    procedure DrawStatic(B: TBGRABitmap); virtual;
    procedure DrawDynamic(B: TBGRABitmap); virtual;
    function MouseDown(X, Y: Single): Boolean; virtual;
    procedure MouseMove(X, Y: Single); virtual;
    procedure MouseUp; virtual;
    function KeyDown(Key: Word): Boolean; virtual;
  end;

  TLessonList = array of TLesson;

function CreateAllLessons: TLessonList;

implementation

const
  ReplaySpeed = 2.0;  // sim seconds per real second on replay pages
  ReplayTime = 10.0;
  ReplayN = 501;

function Lines(const A: array of string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 0 to High(A) do
  begin
    if I > 0 then
      Result := Result + LineEnding;
    Result := Result + A[I];
  end;
end;

function TopPanel: TBox;
begin
  Result := Box(RightX1, ContentY - 4, RightX2, 380);
end;

function BotPanel: TBox;
begin
  Result := Box(RightX1, 392, RightX2, ContentY2);
end;

function Inner(const R: TBox): TBox;
begin
  Result := Box(R.X1 + 50, R.Y1 + 40, R.X2 - 18, R.Y2 - 28);
end;

procedure PlotPanel(B: TBGRABitmap; const R: TBox; const Title: string);
begin
  Panel(B, R);
  UseFont(B, 16, [fsBold], UIFont, True);
  B.TextOut(R.X1 + 14, R.Y1 + 9, Title, HexPixel(ClrText));
end;

function NiceStep(Range: Double): Double;
var
  P, M: Double;
begin
  if Range <= 0 then
    Exit(1);
  P := Power(10, Floor(Log10(Range)));
  M := Range / P;
  if M < 1.5 then
    Result := P
  else if M < 3 then
    Result := 2 * P
  else if M < 7 then
    Result := 5 * P
  else
    Result := 10 * P;
end;

{ Plot box whose Y range covers all the given series (plus zero) }
function AutoPlot(const R: TBox; X0, X1: Double; const S: array of TDoubleArray;
  out Step: Double): TPlotBox;
var
  I, J: Integer;
  Lo, Hi, Pad: Double;
begin
  Lo := 0;
  Hi := 0.1;
  for I := 0 to High(S) do
    for J := 0 to High(S[I]) do
    begin
      Lo := Min(Lo, S[I][J]);
      Hi := Max(Hi, S[I][J]);
    end;
  Pad := (Hi - Lo) * 0.08;
  Step := NiceStep((Hi - Lo) / 4);
  Result := MakePlot(R, X0, X1, Floor((Lo - Pad) / Step) * Step, Ceil((Hi + Pad) / Step) * Step);
end;

procedure CursorDot(B: TBGRABitmap; const P: TPlotBox; X, Y: Double; C: LongWord);
begin
  B.DrawLineAntialias(PX(P, X), P.R.Y1, PX(P, X), P.R.Y2, BGRA(255, 255, 255, 40), 1);
  B.FillEllipseAntialias(PX(P, X), PY(P, Y), 9, 9, HexPixel(C, 60));
  B.FillEllipseAntialias(PX(P, X), PY(P, Y), 4.5, 4.5, HexPixel(C));
end;

procedure Legend(B: TBGRABitmap; X, Y: Single; const Items: array of string;
  const Colors: array of LongWord);
var
  I: Integer;
begin
  for I := 0 to High(Items) do
  begin
    B.DrawLineAntialias(X, Y + 9, X + 18, Y + 9, HexPixel(Colors[I]), 3);
    Txt(B, X + 24, Y, Items[I], Colors[I], 14);
    X := X + 34 + TxtW(B, Items[I], 14);
  end;
end;

{ Shared readout line: "name = value" pairs }
procedure Readout(B: TBGRABitmap; X, Y: Single; const Names: array of string;
  const Values: array of Double; const Colors: array of LongWord; Decimals: Integer = 2);
var
  I: Integer;
  S: string;
begin
  for I := 0 to High(Names) do
  begin
    S := Names[I] + ' = ' + Fmt(Values[I], Decimals);
    Txt(B, X, Y, S, Colors[I], 15, [fsBold]);
    X := X + TxtW(B, S, 15, [fsBold]) + 22;
  end;
end;

{ TLesson }

constructor TLesson.Create;
begin
  inherited Create;
  FSliders := TFPList.Create;
  FTextSize := 17;
end;

destructor TLesson.Destroy;
var
  I: Integer;
begin
  for I := 0 to FSliders.Count - 1 do
    TSlider(FSliders[I]).Free;
  FSliders.Free;
  inherited Destroy;
end;

function TLesson.AddSlider(const ASym, ASub: string; AMin, AMax, AValue: Double;
  AColor: LongWord; ADecimals, Slot, Slots: Integer): TSlider;
var
  Y: Single;
begin
  Result := TSlider.Create(ASym, ASub, AMin, AMax, AValue, AColor, ADecimals);
  Y := ContentY2 - 14 - (Slots - 1 - Slot) * 38;
  Result.R := Box(LeftX, Y - 17, LeftX + LeftW, Y + 17);
  Result.OnChange := @SliderChanged;
  FSliders.Add(Result);
end;

function TLesson.Slider(I: Integer): TSlider;
begin
  Result := TSlider(FSliders[I]);
end;

procedure TLesson.SliderChanged(Sender: TObject);
begin
end;

procedure TLesson.Enter;
begin
  FTime := 0;
end;

procedure TLesson.Update(Dt: Double);
begin
  FTime := FTime + Dt;
end;

procedure TLesson.DrawStatic(B: TBGRABitmap);
begin
  if FText <> '' then
    DrawRichText(B, LeftX, ContentY, LeftW, FText, FTextSize);
end;

procedure TLesson.DrawDynamic(B: TBGRABitmap);
var
  I: Integer;
begin
  for I := 0 to FSliders.Count - 1 do
    Slider(I).Draw(B);
end;

function TLesson.MouseDown(X, Y: Single): Boolean;
var
  I: Integer;
begin
  Result := False;
  for I := 0 to FSliders.Count - 1 do
    if Slider(I).MouseDown(X, Y) then
      Exit(True);
end;

procedure TLesson.MouseMove(X, Y: Single);
var
  I: Integer;
begin
  for I := 0 to FSliders.Count - 1 do
    Slider(I).MouseMove(X, Y);
end;

procedure TLesson.MouseUp;
var
  I: Integer;
begin
  for I := 0 to FSliders.Count - 1 do
    Slider(I).MouseUp;
end;

function TLesson.KeyDown(Key: Word): Boolean;
begin
  Result := False;
end;

{ ---------------------------------------------------------------------------
  TLiveLoop - closed loop on the mass-spring plant, setpoint toggles every 4 s }

type
  TLiveLoop = class
  private
    FAcc: Double;
  public
    Plant: TPlant;
    Pid: TPIDController;
    Time, R, U: Double;
    History: THistory; // 0 r, 1 y, 2 e, 3 u
    constructor Create(const G: TPIDGains);
    destructor Destroy; override;
    procedure Reset;
    procedure Advance(Dt: Double);
  end;

const
  LoopSpan = 12.0;
  LoopSlots = 480;

constructor TLiveLoop.Create(const G: TPIDGains);
begin
  inherited Create;
  Pid := TPIDController.Create(G);
  History := THistory.Create(4, LoopSlots);
  Reset;
end;

destructor TLiveLoop.Destroy;
begin
  History.Free;
  Pid.Free;
  inherited Destroy;
end;

procedure TLiveLoop.Reset;
begin
  Plant := DefaultPlant;
  Pid.Reset;
  History.Clear;
  Time := 0;
  U := 0;
  R := 1;
  FAcc := 0;
end;

procedure TLiveLoop.Advance(Dt: Double);
const
  H = 0.001;
var
  N, I: Integer;
  A: Double;
begin
  N := Round(Dt / H);
  for I := 1 to N do
  begin
    if Frac(Time / 8) < 0.5 then
      R := 1.0
    else
      R := 0.3;
    U := Pid.Update(R, Plant.X, H);
    A := (U - Plant.C * Plant.V - Plant.K * Plant.X) / Plant.M;
    Plant.V := Plant.V + A * H;
    Plant.X := Plant.X + Plant.V * H;
    Time := Time + H;
    FAcc := FAcc + H;
    if FAcc >= LoopSpan / LoopSlots then
    begin
      FAcc := FAcc - LoopSpan / LoopSlots;
      History.Push([R, Plant.X, R - Plant.X, U]);
    end;
  end;
end;

{ ---------------------------------------------------------------------------
  Page 1 - overview: equation, block diagram with flowing signals }

type
  TOverviewLesson = class(TLesson)
  private
    FLoop: TLiveLoop;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Enter; override;
    procedure Update(Dt: Double); override;
    procedure DrawStatic(B: TBGRABitmap); override;
    procedure DrawDynamic(B: TBGRABitmap); override;
  end;

constructor TOverviewLesson.Create;
begin
  inherited Create;
  Title := 'PID คืออะไร — ภาพรวมของวงควบคุมป้อนกลับ';
  TabName := 'ภาพรวม';
  Hints := '← → เปลี่ยนหน้า   1–9, 0 ไปหน้าที่ต้องการ   Space หยุด   F11 เต็มจอ';
  FLoop := TLiveLoop.Create(Gains(6, 3, 2.5));
  FText := Lines([
    '## PID Controller',
    'PID ย่อมาจาก Proportional – Integral – Derivative เป็นตัวควบคุมแบบป้อนกลับ (feedback) ที่ใช้มากที่สุดในโลก ' +
    'พบได้ใน เตาอบ แอร์ รถยนต์ มอเตอร์ หุ่นยนต์ โดรน และ เครื่องจักรในโรงงาน',
    '',
    '## หลักการทำงาน (ทำซ้ำทุก dt วินาที)',
    '- วัดค่าจริง y จากเซนเซอร์',
    '- เทียบกับค่าเป้าหมาย r ได้ค่าความผิดพลาด e = r − y',
    '- คำนวณสัญญาณควบคุม u จาก 3 เทอม: ปัจจุบัน (P) อดีต (I) และ แนวโน้มอนาคต (D)',
    '- ส่ง u ไปยังตัวขับ (actuator) ระบบเปลี่ยนไป แล้ววัดใหม่',
    '',
    '## ตัวแปรทั้งหมดในสมการ',
    '{w}r  ค่าเป้าหมาย (setpoint)',
    '{g}y  ค่าที่วัดได้ (process variable)',
    '{w}e  ค่าความผิดพลาด = r − y',
    '{w}u  สัญญาณควบคุมที่ส่งออก (control output)',
    '{p}Kp  เกนสัดส่วน — ตอบสนองต่อ error ตอนนี้',
    '{i}Ki  เกนปริพันธ์ — สะสม error ในอดีต',
    '{d}Kd  เกนอนุพันธ์ — ตอบสนองต่ออัตราการเปลี่ยนของ error',
    '{w}t, dt  เวลา และ ช่วงเวลาระหว่างการคำนวณแต่ละรอบ',
    '',
    '> แต่ละหน้าถัดไปอธิบายตัวแปรทีละตัว พร้อมการจำลองที่ปรับค่าได้ ' +
    'และ ตัวอย่างการใช้งานจริง 3 แบบ: รถยนต์ เตาอบ โดรน'
    ]);
  FTextSize := 16;
end;

destructor TOverviewLesson.Destroy;
begin
  FLoop.Free;
  inherited Destroy;
end;

procedure TOverviewLesson.Enter;
begin
  inherited Enter;
  FLoop.Reset;
end;

procedure TOverviewLesson.Update(Dt: Double);
begin
  inherited Update(Dt);
  FLoop.Advance(Dt);
end;

procedure TOverviewLesson.DrawStatic(B: TBGRABitmap);
var
  Eq: TEquationView;
  Part: TBGRABitmap;
begin
  inherited DrawStatic(B);
  Eq := TEquationView.Create(nil);
  Part := TBGRABitmap.Create(RightX2 - RightX1, 110, HexPixel(ClrBackground));
  try
    Eq.SetBounds(0, 0, Part.Width, Part.Height);
    Eq.Render(Part);
    B.PutImage(RightX1, ContentY - 6, Part, dmSet);
  finally
    Part.Free;
    Eq.Free;
  end;
  PlotPanel(B, Box(RightX1, 208, RightX2, 452), 'การไหลของสัญญาณในวงควบคุม');
  PlotPanel(B, Box(RightX1, 464, RightX2, ContentY2), 'r และ y จริงจากการจำลอง (Kp = 6, Ki = 3, Kd = 2.5)');
end;

procedure TOverviewLesson.DrawDynamic(B: TBGRABitmap);
const
  LineY = 318;
  BackY = 412;
  SumX = 690;
  PidX1 = 764;
  PidX2 = 924;
  PlX1 = 1000;
  PlX2 = 1150;
  OutX = 1200;
var
  Phase: Single;
  P: TPlotBox;
  Step: Double;
  Slot: Double;
  N: Integer;

  procedure Flow(X1, Y1, X2, Y2: Single; C: LongWord; Arrow: Boolean);
  var
    L, D, DX, DY: Single;
  begin
    B.DrawLineAntialias(X1, Y1, X2, Y2, HexPixel(C, 150), 2);
    L := Sqrt(Sqr(X2 - X1) + Sqr(Y2 - Y1));
    if L < 1 then
      Exit;
    DX := (X2 - X1) / L;
    DY := (Y2 - Y1) / L;
    D := Phase * 26;
    while D < L do
    begin
      B.FillEllipseAntialias(X1 + DX * D, Y1 + DY * D, 3, 3, HexPixel(C));
      D := D + 26;
    end;
    if Arrow then
      B.FillPolyAntialias([PointF(X2, Y2), PointF(X2 - DX * 10 - DY * 6, Y2 - DY * 10 + DX * 6),
        PointF(X2 - DX * 10 + DY * 6, Y2 - DY * 10 - DX * 6)], HexPixel(C));
  end;

  procedure Block(X1, X2: Single; const Name, Caption: string; C: LongWord);
  begin
    B.FillRoundRectAntialias(X1, LineY - 36, X2, LineY + 36, 10, 10, HexPixel(ClrKnobFace));
    B.RoundRectAntialias(X1, LineY - 36, X2, LineY + 36, 10, 10, HexPixel(C), 2);
    Txt(B, (X1 + X2) / 2, LineY - 26, Name, C, 20, [fsBold], taCenter);
    Txt(B, (X1 + X2) / 2, LineY + 2, Caption, ClrDim, 13, [], taCenter);
  end;

  procedure Sig(X, Y: Single; const Name: string; V: Double; C: LongWord);
  begin
    Txt(B, X, Y, Name + ' = ' + Fmt(V, 2), C, 15, [fsBold], taCenter);
  end;

begin
  Phase := Frac(FTime * 1.4);
  Flow(RightX1 + 20, LineY, SumX - 18, LineY, ClrText, True);
  Flow(SumX + 18, LineY, PidX1, LineY, ClrBad, True);
  Flow(PidX2, LineY, PlX1, LineY, ClrText, True);
  Flow(PlX2, LineY, OutX, LineY, ClrGold, False);
  Flow(OutX, LineY, OutX, BackY, ClrGold, False);
  Flow(OutX, BackY, SumX, BackY, ClrGold, False);
  Flow(SumX, BackY, SumX, LineY + 18, ClrGold, True);
  Flow(OutX, LineY, RightX2 - 16, LineY, ClrGold, True);

  B.FillEllipseAntialias(SumX, LineY, 18, 18, HexPixel(ClrKnobFace));
  B.EllipseAntialias(SumX, LineY, 18, 18, HexPixel(ClrText), 2);
  Txt(B, SumX, LineY - 12, 'Σ', ClrText, 18, [fsBold], taCenter);
  Txt(B, SumX - 28, LineY + 2, '+', ClrText, 16, [fsBold], taCenter);
  Txt(B, SumX + 14, LineY + 18, '−', ClrText, 18, [fsBold], taCenter);
  Block(PidX1, PidX2, 'PID', 'u = P + I + D', ClrKi);
  Block(PlX1, PlX2, 'Plant', 'ระบบที่ถูกควบคุม', ClrKd);

  Sig(RightX1 + 44, LineY - 44, 'r', FLoop.R, ClrText);
  Sig((SumX + PidX1) / 2 + 4, LineY - 44, 'e', FLoop.R - FLoop.Plant.X, ClrBad);
  Sig((PidX2 + PlX1) / 2, LineY - 44, 'u', FLoop.U, ClrText);
  Sig(OutX - 8, LineY - 44, 'y', FLoop.Plant.X, ClrGold);
  Txt(B, (SumX + OutX) / 2, BackY + 6, 'ป้อนกลับ (feedback): เซนเซอร์ส่ง y กลับมาเทียบกับ r',
    ClrDim, 13, [], taCenter);

  N := FLoop.History.Count;
  Slot := LoopSpan / LoopSlots;
  P := MakePlot(Inner(Box(RightX1, 464, RightX2, ContentY2)), -LoopSpan, 0, -0.1, 1.5);
  Step := 0.5;
  DrawPlotGrid(B, P, Step, 4, ' s');
  DrawSeries(B, P, FLoop.History.Series(0), N, -(N - 1) * Slot, Slot, ClrText, 1.5, 160);
  DrawSeries(B, P, FLoop.History.Series(1), N, -(N - 1) * Slot, Slot, ClrGold, 2.5);
  Legend(B, RightX2 - 170, 472, ['r', 'y'], [ClrText, ClrGold]);
  inherited DrawDynamic(B);
end;

{ ---------------------------------------------------------------------------
  Page 2 - r, y, e }

type
  TErrorLesson = class(TLesson)
  private
    FLoop: TLiveLoop;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Enter; override;
    procedure Update(Dt: Double); override;
    procedure DrawStatic(B: TBGRABitmap); override;
    procedure DrawDynamic(B: TBGRABitmap); override;
  end;

constructor TErrorLesson.Create;
begin
  inherited Create;
  Title := 'r, y และ e — เป้าหมาย ค่าจริง และ ความผิดพลาด';
  TabName := 'r  y  e';
  Hints := 'setpoint สลับ 1.0 ↔ 0.3 ทุก 4 วินาที   พื้นที่สีแดง = e';
  FLoop := TLiveLoop.Create(Gains(6, 3, 2.5));
  FText := Lines([
    '## r — Setpoint (ค่าเป้าหมาย)',
    'ค่าที่เราต้องการให้ระบบเป็น เช่น อุณหภูมิ 180 °C ความเร็ว 80 km/h ความสูง 5 m ' +
    'ผู้ใช้หรือโปรแกรมระดับบนเป็นผู้กำหนด และ เปลี่ยนได้ตลอดเวลา',
    '',
    '## y — Process Variable (ค่าที่วัดได้)',
    'ค่าจริงที่อ่านจากเซนเซอร์ ณ เวลานั้น เช่น เทอร์โมคัปเปิล เอนโค้ดเดอร์ บารอมิเตอร์ ' +
    'ในงานจริง y มี noise และ อาจมาช้ากว่าความเป็นจริง (delay)',
    '',
    '## e — Error (ค่าความผิดพลาด)',
    '{w}e(t) = r(t) − y(t)',
    '- e > 0  ค่าจริงยังต่ำกว่าเป้า → ต้องเพิ่ม u',
    '- e < 0  ค่าจริงเกินเป้า → ต้องลด u',
    '- e = 0  ตรงเป้าพอดี (เป้าหมายของตัวควบคุม)',
    '',
    'e คือ "อินพุตเดียว" ของ PID ทั้ง 3 เทอมคำนวณจาก e: ' +
    'P ใช้ค่า e ตอนนี้, I ใช้ผลรวม e ในอดีต, D ใช้ความชันของ e',
    '',
    '> เครื่องหมายสำคัญมาก ถ้าเขียนกลับเป็น y − r ระบบจะผลักตัวเองออกห่างเป้าหมาย ' +
    '(positive feedback) และ ค่าจะพุ่งจนสุดขีด'
    ]);
end;

destructor TErrorLesson.Destroy;
begin
  FLoop.Free;
  inherited Destroy;
end;

procedure TErrorLesson.Enter;
begin
  inherited Enter;
  FLoop.Reset;
end;

procedure TErrorLesson.Update(Dt: Double);
begin
  inherited Update(Dt);
  FLoop.Advance(Dt);
end;

procedure TErrorLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'r(t) และ y(t)   — ช่องว่างระหว่างเส้นคือ e');
  PlotPanel(B, BotPanel, 'e(t) = r − y');
end;

procedure TErrorLesson.DrawDynamic(B: TBGRABitmap);
var
  P: TPlotBox;
  RS, YS, ES: TDoubleArray;
  Pts: ArrayOfTPointF;
  I, N: Integer;
  Slot, X0, R, Y, E: Double;
  MX, MY1, MY2, Scale: Single;
begin
  N := FLoop.History.Count;
  Slot := LoopSpan / LoopSlots;
  X0 := -(N - 1) * Slot;
  RS := FLoop.History.Series(0);
  YS := FLoop.History.Series(1);
  ES := FLoop.History.Series(2);

  P := MakePlot(Inner(TopPanel), -LoopSpan, 0, -0.1, 1.5);
  DrawPlotGrid(B, P, 0.5, 4, ' s');
  if N >= 2 then
  begin
    SetLength(Pts, 2 * N);
    for I := 0 to N - 1 do
    begin
      Pts[I] := PointF(PX(P, X0 + I * Slot), PY(P, RS[I]));
      Pts[2 * N - 1 - I] := PointF(PX(P, X0 + I * Slot), PY(P, YS[I]));
    end;
    B.FillPolyAntialias(Pts, HexPixel(ClrBad, 60));
  end;
  DrawSeries(B, P, RS, N, X0, Slot, ClrText, 1.5, 180);
  DrawSeries(B, P, YS, N, X0, Slot, ClrGold, 2.5);
  Legend(B, RightX2 - 220, TopPanel.Y1 + 10, ['r', 'y', 'e'], [ClrText, ClrGold, ClrBad]);

  P := MakePlot(Box(BotPanel.X1 + 50, BotPanel.Y1 + 40, 1060, BotPanel.Y2 - 28),
    -LoopSpan, 0, -0.8, 1.0);
  DrawPlotGrid(B, P, 0.4, 4, ' s');
  FillUnder(B, P, ES, N, X0, Slot, 0, ClrBad, 70);
  DrawSeries(B, P, ES, N, X0, Slot, ClrBad, 2.5);

  // live meter: where r and y are right now, e is the gap
  R := FLoop.R;
  Y := FLoop.Plant.X;
  E := R - Y;
  MX := 1150;
  MY1 := BotPanel.Y1 + 50;
  MY2 := BotPanel.Y2 - 40;
  Scale := (MY2 - MY1) / 1.4;
  B.DrawLineAntialias(MX, MY1, MX, MY2, HexPixel(ClrKnobTrack), 6);
  B.DrawLineAntialias(MX - 30, MY2 - (R + 0.1) * Scale, MX + 30, MY2 - (R + 0.1) * Scale, BGRAWhite, 3);
  B.FillEllipseAntialias(MX, MY2 - (Y + 0.1) * Scale, 9, 9, HexPixel(ClrGold));
  B.DrawLineAntialias(MX + 40, MY2 - (R + 0.1) * Scale, MX + 40, MY2 - (Y + 0.1) * Scale,
    HexPixel(ClrBad), 3);
  Txt(B, MX - 36, MY2 - (R + 0.1) * Scale - 10, 'r', ClrText, 15, [fsBold], taRightJustify);
  Txt(B, MX - 16, MY2 - (Y + 0.1) * Scale - 10, 'y', ClrGold, 15, [fsBold], taRightJustify);
  Txt(B, MX + 48, (MY2 - (R + 0.1) * Scale + MY2 - (Y + 0.1) * Scale) / 2 - 10, 'e',
    ClrBad, 15, [fsBold]);
  Readout(B, BotPanel.X1 + 260, BotPanel.Y1 + 10, ['r', 'y', 'e'], [R, Y, E],
    [ClrText, ClrGold, ClrBad]);
  inherited DrawDynamic(B);
end;

{ ---------------------------------------------------------------------------
  Replay pages - a 10 s step response recorded with every PID term,
  played back with a moving cursor }

type
  { Drawing is split in two: DrawStill (grids, labels, comparison and faint
    full curves - everything that depends only on the trace) is rendered into
    a cached layer that is rebuilt only when the trace changes; DrawMoving
    (growing curve, cursor, readouts) is drawn every frame on top. }
  TReplayLesson = class(TLesson)
  protected
    FTrace: TTrace;
    FDirty: Boolean;
    FNoise: Double;
    FLayer: TBGRABitmap;
    FLayerDirty: Boolean;
    FBot: TPlotBox; // bottom plot, set by DrawStill
    function TraceGains: TPIDGains; virtual; abstract;
    procedure SliderChanged(Sender: TObject); override;
    procedure EnsureTrace;
    function CursorIdx: Integer;
    function SampleDt: Double;
    function TopPlot: TPlotBox;
    procedure DrawStill(B: TBGRABitmap); virtual;
    procedure DrawMoving(B: TBGRABitmap; C: Integer); virtual;
  public
    constructor Create; override;
    destructor Destroy; override;
    procedure Update(Dt: Double); override;
    procedure DrawDynamic(B: TBGRABitmap); override;
  end;

constructor TReplayLesson.Create;
begin
  inherited Create;
  FDirty := True;
end;

destructor TReplayLesson.Destroy;
begin
  FLayer.Free;
  inherited Destroy;
end;

procedure TReplayLesson.SliderChanged(Sender: TObject);
begin
  FDirty := True;
end;

procedure TReplayLesson.EnsureTrace;
begin
  if not FDirty then
    Exit;
  FTrace := BuildTrace(TraceGains, DefaultPlant, ReplayTime, ReplayN, FNoise);
  FDirty := False;
  FLayerDirty := True;
end;

procedure TReplayLesson.DrawDynamic(B: TBGRABitmap);
begin
  EnsureTrace;
  if FLayerDirty or (FLayer = nil) then
  begin
    if FLayer = nil then
      FLayer := TBGRABitmap.Create(CanvasW, CanvasH);
    FLayer.PutImage(0, 0, B, dmSet); // B holds just the static page here
    DrawStill(FLayer);
    FLayerDirty := False;
  end;
  B.PutImage(0, 0, FLayer, dmSet);
  DrawMoving(B, CursorIdx);
  inherited DrawDynamic(B);
end;

procedure TReplayLesson.Update(Dt: Double);
begin
  inherited Update(Dt);
  EnsureTrace;
end;

function TReplayLesson.SampleDt: Double;
begin
  Result := ReplayTime / (ReplayN - 1);
end;

function TReplayLesson.CursorIdx: Integer;
var
  Cycle, L: Double;
begin
  Cycle := ReplayTime / ReplaySpeed + 1.2;
  L := FTime - Floor(FTime / Cycle) * Cycle;
  Result := Round(Min(ReplayTime, L * ReplaySpeed) / ReplayTime * (ReplayN - 1));
end;

function TReplayLesson.TopPlot: TPlotBox;
begin
  Result := MakePlot(Inner(TopPanel), 0, ReplayTime, -0.2, 1.8);
end;

procedure TReplayLesson.DrawStill(B: TBGRABitmap);
var
  P: TPlotBox;
begin
  P := TopPlot;
  DrawPlotGrid(B, P, 0.5, 2, ' s');
  DashH(B, P, 1.0, ClrText);
  DrawSeries(B, P, FTrace.Y, ReplayN, 0, SampleDt, ClrGold, 2, 45);
  Txt(B, PX(P, ReplayTime) - 4, PY(P, 1.0) - 22, 'r = 1', ClrText, 13, [], taRightJustify);
end;

procedure TReplayLesson.DrawMoving(B: TBGRABitmap; C: Integer);
var
  P: TPlotBox;
begin
  P := TopPlot;
  DrawSeries(B, P, FTrace.Y, C + 1, 0, SampleDt, ClrGold, 2.8);
  CursorDot(B, P, C * SampleDt, FTrace.Y[C], ClrGold);
end;

{ Page 3 - Kp }

type
  TKpLesson = class(TReplayLesson)
  private
    FGhost: array[0..2] of TTrace;
  protected
    function TraceGains: TPIDGains; override;
    procedure DrawStill(B: TBGRABitmap); override;
    procedure DrawMoving(B: TBGRABitmap; C: Integer); override;
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
  end;

const
  GhostKp: array[0..2] of Double = (1, 4, 15);

constructor TKpLesson.Create;
var
  I: Integer;
begin
  inherited Create;
  Title := 'Kp — Proportional: แรงตาม error ตอนนี้';
  TabName := 'Kp';
  Hints := 'ลากแถบเลื่อน Kp   เส้นจาง = Kp 1, 4, 15   (หน้านี้ Ki = 0, Kd = 0)';
  FText := Lines([
    '## {p}P = Kp · e',
    'เทอม P ให้แรงสั่งการ แปรผันตรงกับ error ณ ตอนนี้ ห่างจากเป้ามาก ดันมาก ใกล้เป้าแล้ว ดันน้อยลง ' +
    'เหมือนคนขับรถที่เหยียบคันเร่งมากเมื่อยังช้ากว่าที่ต้องการมาก',
    '',
    '## ความหมายของ Kp',
    '- หน่วย: [หน่วยของ u] ต่อ [หน่วยของ e] เช่น % คันเร่ง ต่อ 1 km/h',
    '- Kp ต่ำ: ตอบสนองช้า เข้าเป้าช้า',
    '- Kp สูง: เร็วขึ้น แต่ overshoot (เลยเป้า) และ แกว่งมากขึ้น ถ้าสูงเกินไประบบอาจไม่เสถียร',
    '',
    '## ทำไม P อย่างเดียวไม่ถึงเป้า',
    'ระบบสปริงต้องการแรง u = k·y ค้างไว้ แต่ถ้า e = 0 แล้ว P = 0 ' +
    'ระบบจึงหยุดในจุดที่ยังมี error เหลืออยู่ (steady-state error) เรียกว่า offset',
    '{g}e∞ = 1 / (1 + Kp)   (เส้นประสีทอง)',
    'Kp ยิ่งมาก error ค้างยิ่งน้อย แต่ไม่มีวันเป็นศูนย์ → จึงต้องมี Ki'
    ]);
  FTextSize := 16;
  AddSlider('K', 'p', 0, 20, 4, ClrKp, 2, 0, 1);
  for I := 0 to 2 do
    FGhost[I] := BuildTrace(Gains(GhostKp[I], 0, 0), DefaultPlant, ReplayTime, ReplayN);
end;

function TKpLesson.TraceGains: TPIDGains;
begin
  Result := Gains(Slider(0).Value, 0, 0);
end;

procedure TKpLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'y(t) ผลตอบสนองต่อ step (r = 1)');
  PlotPanel(B, BotPanel, 'P(t) = Kp · e(t)   (หน้านี้ u = P)');
end;

procedure TKpLesson.DrawStill(B: TBGRABitmap);
var
  P: TPlotBox;
  I: Integer;
  Kp, Ss, Step: Double;
begin
  P := TopPlot;
  for I := 0 to 2 do
  begin
    DrawSeries(B, P, FGhost[I].Y, ReplayN, 0, SampleDt, ClrKp, 1.5, 55);
    Txt(B, PX(P, ReplayTime) + 2, PY(P, FGhost[I].Y[ReplayN - 1]) - 8,
      Fmt(GhostKp[I], 0), ClrKp, 11, [], taLeftJustify, 120);
  end;
  inherited DrawStill(B);
  Kp := Slider(0).Value;
  Ss := Kp / (1 + Kp);
  B.PenStyle := psDash;
  B.DrawLineAntialias(P.R.X1, PY(P, Ss), P.R.X2, PY(P, Ss), HexPixel(ClrGold, 200), 1.5);
  B.PenStyle := psSolid;
  Txt(B, P.R.X1 + 8, PY(P, Ss) + 4, Format('y∞ = %.2f   error ค้าง e∞ = %.2f', [Ss, 1 - Ss]),
    ClrGold, 14);

  FBot := AutoPlot(Inner(BotPanel), 0, ReplayTime, [FTrace.P], Step);
  DrawPlotGrid(B, FBot, Step, 2, ' s');
  DrawSeries(B, FBot, FTrace.P, ReplayN, 0, SampleDt, ClrKp, 1.5, 50);
end;

procedure TKpLesson.DrawMoving(B: TBGRABitmap; C: Integer);
begin
  inherited DrawMoving(B, C);
  DrawSeries(B, FBot, FTrace.P, C + 1, 0, SampleDt, ClrKp, 2.8);
  CursorDot(B, FBot, C * SampleDt, FTrace.P[C], ClrKp);
  Readout(B, BotPanel.X1 + 290, BotPanel.Y1 + 10, ['t', 'e', 'P'],
    [C * SampleDt, FTrace.E[C], FTrace.P[C]], [ClrDim, ClrBad, ClrKp]);
end;

{ Page 4 - Ki }

type
  TKiLesson = class(TReplayLesson)
  protected
    function TraceGains: TPIDGains; override;
    procedure DrawStill(B: TBGRABitmap); override;
    procedure DrawMoving(B: TBGRABitmap; C: Integer); override;
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
  end;

constructor TKiLesson.Create;
begin
  inherited Create;
  Title := 'Ki — Integral: สะสม error ในอดีต';
  TabName := 'Ki';
  Hints := 'ลากแถบเลื่อน Ki   (Kp = 4, Kd = 1 คงที่)   พื้นที่สีฟ้า = ∫e dt';
  FText := Lines([
    '## {i}I = Ki · ∫ e dt',
    'เทอม I บวก error สะสมไปเรื่อย ๆ ตามเวลา (พื้นที่ใต้กราฟ e) ' +
    'ตราบใดที่ยังมี error แม้เพียงเล็กน้อย I จะโตขึ้นเรื่อย ๆ จนกว่า e จะเป็นศูนย์',
    '',
    '## หน้าที่ของ Ki',
    '- กำจัด steady-state error ที่ P ทำไม่ได้ เมื่อเข้าเป้าแล้ว I จะ "ค้าง" ' +
    'แรงที่ระบบต้องการไว้ให้ (ที่นี่ I → 1 เพราะสปริงต้องการ u = 1)',
    '- หน่วย: [u] ต่อ ([e] · วินาที)  มักเขียนเป็น Ti = Kp / Ki (integral time)',
    '- Ki ต่ำ: เข้าเป้าช้า ค่อย ๆ คืบไปหาเป้า',
    '- Ki สูง: เร็ว แต่ overshoot และ แกว่งนาน เพราะ I "จำ" error เก่าไว้ ต้องใช้เวลาคายออก',
    '',
    '## Integral windup',
    'ถ้า actuator ติดขีดจำกัด (เช่น ฮีตเตอร์ 100 %) แต่ I ยังสะสมต่อ ' +
    'ค่า I จะพองมาก แล้วทำให้เลยเป้าไปไกล แก้ด้วย anti-windup ' +
    '(หยุดสะสมเมื่อ u อิ่มตัว) ดูตัวอย่างเตาอบ หน้า 9'
    ]);
  FTextSize := 16;
  AddSlider('K', 'i', 0, 8, 2, ClrKi, 2, 0, 1);
end;

function TKiLesson.TraceGains: TPIDGains;
begin
  Result := Gains(4, Slider(0).Value, 1);
end;

procedure TKiLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'y(t) ผลตอบสนองต่อ step (r = 1)');
  PlotPanel(B, BotPanel, 'e(t) และ I(t) = Ki · ∫e dt');
end;

procedure TKiLesson.DrawStill(B: TBGRABitmap);
var
  Step: Double;
begin
  inherited DrawStill(B);
  FBot := AutoPlot(Inner(BotPanel), 0, ReplayTime, [FTrace.E, FTrace.I], Step);
  DrawPlotGrid(B, FBot, Step, 2, ' s');
  DrawSeries(B, FBot, FTrace.E, ReplayN, 0, SampleDt, ClrBad, 1.5, 120);
  DrawSeries(B, FBot, FTrace.I, ReplayN, 0, SampleDt, ClrKi, 1.5, 50);
  Legend(B, FBot.R.X2 - 150, FBot.R.Y1 + 4, ['e', 'I'], [ClrBad, ClrKi]);
end;

procedure TKiLesson.DrawMoving(B: TBGRABitmap; C: Integer);
var
  K: Integer;
  Area: Double;
begin
  inherited DrawMoving(B, C);
  FillUnder(B, FBot, FTrace.E, C + 1, 0, SampleDt, 0, ClrKi, 80);
  DrawSeries(B, FBot, FTrace.I, C + 1, 0, SampleDt, ClrKi, 2.8);
  CursorDot(B, FBot, C * SampleDt, FTrace.I[C], ClrKi);
  Area := 0;
  for K := 1 to C do
    Area := Area + FTrace.E[K] * SampleDt;
  Readout(B, BotPanel.X1 + 250, BotPanel.Y1 + 10, ['e', '∫e dt', 'I'],
    [FTrace.E[C], Area, FTrace.I[C]], [ClrBad, ClrKi, ClrKi]);
end;

{ Page 5 - Kd }

type
  TKdLesson = class(TReplayLesson)
  private
    FNoiseBox: TBox;
  protected
    function TraceGains: TPIDGains; override;
    procedure DrawStill(B: TBGRABitmap); override;
    procedure DrawMoving(B: TBGRABitmap; C: Integer); override;
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
    function MouseDown(X, Y: Single): Boolean; override;
    function KeyDown(Key: Word): Boolean; override;
  end;

constructor TKdLesson.Create;
begin
  inherited Create;
  Title := 'Kd — Derivative: ตอบสนองต่ออัตราการเปลี่ยน';
  TabName := 'Kd';
  Hints := 'ลากแถบเลื่อน Kd   N = เปิด/ปิด noise ของเซนเซอร์   (Kp = 8, Ki = 2 คงที่)';
  FText := Lines([
    '## {d}D = Kd · de/dt',
    'เทอม D ดูว่า error กำลังเปลี่ยนเร็วแค่ไหน (ความชันของกราฟ) จึงเหมือน "มองอนาคต" ' +
    'ถ้า y พุ่งเข้าหาเป้าเร็ว D จะออกแรงต้าน (เบรก) ก่อนถึงเป้า ลด overshoot',
    '',
    '## หน้าที่ของ Kd',
    '- เพิ่ม damping เหมือนโช้คอัพ ทำให้ระบบนิ่งเร็ว ไม่แกว่ง',
    '- หน่วย: [u] · วินาที ต่อ [e]  มักเขียนเป็น Td = Kd / Kp (derivative time)',
    '- ไม่ช่วยลด error ค้าง เพราะ error คงที่ → de/dt = 0',
    '- Kd สูงเกินไป: ตอบสนองหนืด ช้า และ ขยาย noise',
    '',
    '## ข้อควรระวังในงานจริง',
    '- Noise: สัญญาณรบกวนเล็ก ๆ ที่เปลี่ยนเร็ว ทำให้ de/dt สูงมาก u จะกระตุก → ใส่ low-pass filter (DerivTau)',
    '- Derivative kick: ถ้า r กระโดด de/dt จะพุ่งชั่วขณะ → PIDCore ใช้ −dy/dt แทน (derivative on measurement)'
    ]);
  FTextSize := 16;
  AddSlider('K', 'd', 0, 5, 1.5, ClrKd, 2, 0, 1);
end;

function TKdLesson.TraceGains: TPIDGains;
begin
  Result := Gains(8, 2, Slider(0).Value);
end;

procedure TKdLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'y(t) และ เส้นสัมผัส (ความชัน) ณ เวลาปัจจุบัน');
  PlotPanel(B, BotPanel, 'D(t) = Kd · de/dt   และ   u(t)');
end;

procedure TKdLesson.DrawStill(B: TBGRABitmap);
var
  Step: Double;
begin
  inherited DrawStill(B);
  FBot := AutoPlot(Inner(BotPanel), 0, ReplayTime, [FTrace.D, FTrace.U], Step);
  DrawPlotGrid(B, FBot, Step, 2, ' s');
  DrawSeries(B, FBot, FTrace.U, ReplayN, 0, SampleDt, ClrText, 1.2, 110);
  DrawSeries(B, FBot, FTrace.D, ReplayN, 0, SampleDt, ClrKd, 1.5, 50);
  Legend(B, FBot.R.X2 - 150, FBot.R.Y1 + 4, ['D', 'u'], [ClrKd, ClrText]);

  FNoiseBox := Box(TopPanel.X2 - 168, TopPanel.Y1 + 6, TopPanel.X2 - 12, TopPanel.Y1 + 34);
  if FNoise > 0 then
    Chip(B, FNoiseBox.X1, FNoiseBox.Y1, 'noise: เปิด (N)', ClrBad, 14, True)
  else
    Chip(B, FNoiseBox.X1, FNoiseBox.Y1, 'noise: ปิด (N)', ClrDim, 14);
end;

procedure TKdLesson.DrawMoving(B: TBGRABitmap; C: Integer);
var
  P: TPlotBox;
  C0, C1: Integer;
  Slope, T0, Y0: Double;
begin
  inherited DrawMoving(B, C);
  P := TopPlot;
  C0 := Max(0, C - 3);
  C1 := Min(ReplayN - 1, C + 3);
  Slope := (FTrace.Y[C1] - FTrace.Y[C0]) / Max(1e-9, (C1 - C0) * SampleDt);
  T0 := C * SampleDt;
  Y0 := FTrace.Y[C];
  B.DrawLineAntialias(PX(P, Max(0, T0 - 0.8)), PY(P, Y0 - Slope * (T0 - Max(0, T0 - 0.8))),
    PX(P, Min(ReplayTime, T0 + 0.8)), PY(P, Y0 + Slope * (Min(ReplayTime, T0 + 0.8) - T0)),
    HexPixel(ClrKd), 2.5);
  Txt(B, P.R.X1 + 8, P.R.Y2 - 24, Format('dy/dt = %.2f    →    de/dt = −dy/dt = %.2f',
    [Slope, -Slope]), ClrKd, 14);

  DrawSeries(B, FBot, FTrace.D, C + 1, 0, SampleDt, ClrKd, 2.6);
  CursorDot(B, FBot, C * SampleDt, FTrace.D[C], ClrKd);
  Readout(B, BotPanel.X1 + 330, BotPanel.Y1 + 10, ['D', 'u'], [FTrace.D[C], FTrace.U[C]],
    [ClrKd, ClrText]);
end;

function TKdLesson.MouseDown(X, Y: Single): Boolean;
begin
  Result := inherited MouseDown(X, Y);
  if not Result and InBox(FNoiseBox, X, Y) then
    Result := KeyDown(VK_N);
end;

function TKdLesson.KeyDown(Key: Word): Boolean;
begin
  Result := Key = VK_N;
  if Result then
  begin
    if FNoise > 0 then
      FNoise := 0
    else
      FNoise := 0.02;
    FDirty := True;
  end;
end;

{ Page 6 - u = P + I + D }

type
  TOutputLesson = class(TReplayLesson)
  protected
    function TraceGains: TPIDGains; override;
    procedure DrawStill(B: TBGRABitmap); override;
    procedure DrawMoving(B: TBGRABitmap; C: Integer); override;
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
  end;

const
  OutNames: array[0..3] of string = ('P', 'I', 'D', 'u');
  OutColors: array[0..3] of LongWord = (ClrKp, ClrKi, ClrKd, ClrText);

constructor TOutputLesson.Create;
begin
  inherited Create;
  Title := 'u — สัญญาณควบคุม: P + I + D รวมกัน';
  TabName := 'u';
  Hints := 'ปรับเกนทั้ง 3 ตัว แล้วดูว่าแต่ละเทอม "แบ่งงาน" กันอย่างไร';
  FText := Lines([
    '## u = P + I + D',
    'u คือคำสั่งที่ส่งไปยังตัวขับ (actuator) เช่น แรงดันมอเตอร์ % ฮีตเตอร์ แรงขับใบพัด คันเร่ง',
    '',
    '## การแบ่งงานของแต่ละเทอม',
    '- {p}ช่วงแรก: P ใหญ่ที่สุด เพราะ error ยังมาก',
    '- {d}ช่วงพุ่งเข้าเป้า: D ติดลบ ช่วยเบรก ไม่ให้เลยเป้ามาก',
    '- {i}ช่วงท้าย: P → 0 และ D → 0 เหลือ I รับภาระทั้งหมด คือ แรงที่ต้องใช้ค้างระบบไว้ที่เป้า',
    '',
    '## Saturation (ขีดจำกัด)',
    'actuator จริงมีขีดจำกัด เช่น 0–100 % จึงต้องจำกัด u ด้วย OutMin / OutMax ' +
    '(EnsureRange) และ ใช้ anti-windup กับเทอม I',
    '',
    '> แท่งด้านขวาของกราฟล่าง แสดงค่า P, I, D และ u ณ เวลาปัจจุบัน บนสเกลเดียวกัน'
    ]);
  FTextSize := 16;
  AddSlider('K', 'p', 0, 15, 4, ClrKp, 2, 0, 3);
  AddSlider('K', 'i', 0, 6, 2, ClrKi, 2, 1, 3);
  AddSlider('K', 'd', 0, 5, 1.5, ClrKd, 2, 2, 3);
end;

function TOutputLesson.TraceGains: TPIDGains;
begin
  Result := Gains(Slider(0).Value, Slider(1).Value, Slider(2).Value);
end;

procedure TOutputLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'y(t) ผลตอบสนองต่อ step (r = 1)');
  PlotPanel(B, BotPanel, 'P, I, D และ u = P + I + D');
end;

procedure TOutputLesson.DrawStill(B: TBGRABitmap);
var
  Step: Double;
  I: Integer;
begin
  inherited DrawStill(B);
  FBot := AutoPlot(Box(BotPanel.X1 + 50, BotPanel.Y1 + 40, 1060, BotPanel.Y2 - 28),
    0, ReplayTime, [FTrace.P, FTrace.I, FTrace.D, FTrace.U], Step);
  DrawPlotGrid(B, FBot, Step, 2, ' s');
  Legend(B, BotPanel.X1 + 300, BotPanel.Y1 + 10, OutNames, OutColors);
  B.DrawLineAntialias(1078, PY(FBot, 0), 1236, PY(FBot, 0), HexPixel(ClrDim, 120), 1);
  for I := 0 to 3 do
    Txt(B, 1086 + I * 38 + 13, FBot.R.Y2 + 4, OutNames[I], OutColors[I], 14, [fsBold], taCenter);
end;

procedure TOutputLesson.DrawMoving(B: TBGRABitmap; C: Integer);
var
  I: Integer;
  V: Double;
  BX: Single;
begin
  inherited DrawMoving(B, C);
  DrawSeries(B, FBot, FTrace.U, C + 1, 0, SampleDt, ClrText, 3);
  DrawSeries(B, FBot, FTrace.P, C + 1, 0, SampleDt, ClrKp, 2);
  DrawSeries(B, FBot, FTrace.I, C + 1, 0, SampleDt, ClrKi, 2);
  DrawSeries(B, FBot, FTrace.D, C + 1, 0, SampleDt, ClrKd, 2);
  for I := 0 to 3 do
  begin
    case I of
      0: V := FTrace.P[C];
      1: V := FTrace.I[C];
      2: V := FTrace.D[C];
    else
      V := FTrace.U[C];
    end;
    BX := 1086 + I * 38;
    if Abs(PY(FBot, V) - PY(FBot, 0)) > 0.5 then
      B.FillRectAntialias(BX, Min(PY(FBot, V), PY(FBot, 0)), BX + 26,
        Max(PY(FBot, V), PY(FBot, 0)), HexPixel(OutColors[I], 220));
    Txt(B, BX + 13, Min(PY(FBot, V), PY(FBot, 0)) - 18, Fmt(V, 1), OutColors[I], 11, [],
      taCenter);
  end;
end;

{ ---------------------------------------------------------------------------
  Page 7 - t and dt: sampling, sum for the integral, difference for the derivative }

type
  TDtLesson = class(TLesson)
  private
    function ECont(T: Double): Double;
    function EInt(T: Double): Double;
    function EDer(T: Double): Double;
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
    procedure DrawDynamic(B: TBGRABitmap); override;
  end;

const
  DtA = 0.35;
  DtW = 1.4;

constructor TDtLesson.Create;
begin
  inherited Create;
  Title := 't และ dt — PID ในคอมพิวเตอร์ทำงานเป็นจังหวะ';
  TabName := 'dt';
  Hints := 'ลากแถบเลื่อน dt เพื่อดูว่าการประมาณค่าหยาบหรือละเอียด';
  FText := Lines([
    '## t และ dt',
    'คอมพิวเตอร์คำนวณ PID เป็นรอบ ๆ ทุก dt วินาที (sample time) เช่น 1 ms ในไมโครคอนโทรลเลอร์ ' +
    'หรือ 16.7 ms ถ้าผูกกับ vsync 60 Hz  t คือเวลาสะสม t = k · dt',
    '',
    '- {i}ปริพันธ์ → ผลรวม:  ∫e dt ≈ Σ e[k] · dt  (สี่เหลี่ยมสีฟ้า)',
    '- {d}อนุพันธ์ → ผลต่าง:  de/dt ≈ (e[k] − e[k−1]) / dt  (เส้นสีเขียว)',
    '- dt ใหญ่: ประมาณค่าหยาบ ตอบสนองช้า อาจไม่เสถียร',
    '- ต้องใช้ dt จริงเป็นวินาที (วัดด้วย QueryPerformanceCounter) หรือ คงที่',
    '',
    '## โค้ดจริงใน PIDCore.pas (ย่อ)',
    '` E := Setpoint - Measured;',
    '` FIntegral := FIntegral + E * Dt;            // Σ e·dt',
    '` D := -(Measured - FPrevMeas) / Dt;          // −dy/dt',
    '` FDeriv := FDeriv + (D - FDeriv) * Dt / (DerivTau + Dt);',
    '` FPrevMeas := Measured;',
    '` U := Kp * E + Ki * FIntegral + Kd * FDeriv;',
    '` Result := EnsureRange(U, OutMin, OutMax);'
    ]);
  FTextSize := 16;
  AddSlider('dt', '', 0.05, 1.0, 0.4, ClrGold, 2, 0, 1);
  Slider(0).Units := ' s';
end;

function TDtLesson.ECont(T: Double): Double;
begin
  Result := Exp(-DtA * T) * Cos(DtW * T);
end;

function TDtLesson.EInt(T: Double): Double;
begin
  Result := (Exp(-DtA * T) * (DtW * Sin(DtW * T) - DtA * Cos(DtW * T)) + DtA) /
    (DtA * DtA + DtW * DtW);
end;

function TDtLesson.EDer(T: Double): Double;
begin
  Result := Exp(-DtA * T) * (-DtA * Cos(DtW * T) - DtW * Sin(DtW * T));
end;

procedure TDtLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, TopPanel, 'e(t) ต่อเนื่อง (ขาว)  และ ค่าที่สุ่มวัดทุก dt (จุดทอง)');
  PlotPanel(B, BotPanel, 'เทียบค่าจริง กับ ค่าประมาณแบบดิจิทัล ณ ตัวอย่าง k');
end;

procedure TDtLesson.DrawDynamic(B: TBGRABitmap);
var
  P: TPlotBox;
  Dt, T, Sum, Exact, DExact, DApprox: Double;
  K, KCur, NS: Integer;
  Curve: TDoubleArray;
  I: Integer;
  X, Y: Single;

  procedure Row(RY: Single; const Name: string; Exa, Apx: Double; C: LongWord);
  begin
    Txt(B, BotPanel.X1 + 24, RY, Name, C, 18, [fsBold]);
    Txt(B, BotPanel.X1 + 170, RY, 'จริง ' + Fmt(Exa, 3), ClrText, 17);
    Txt(B, BotPanel.X1 + 330, RY, 'ประมาณ ' + Fmt(Apx, 3), C, 17, [fsBold]);
    Txt(B, BotPanel.X2 - 24, RY, 'ต่างกัน ' + Fmt(Abs(Apx - Exa), 3), ClrDim, 16, [],
      taRightJustify);
  end;

begin
  Dt := Slider(0).Value;
  NS := Floor(10 / Dt);
  T := FTime * 1.2 - Floor(FTime * 1.2 / 10.5) * 10.5;
  KCur := EnsureRange(Floor(T / Dt), 1, NS);

  P := MakePlot(Inner(TopPanel), 0, 10, -0.8, 1.1);
  DrawPlotGrid(B, P, 0.4, 2, ' s');
  Sum := 0;
  for K := 0 to KCur - 1 do
  begin
    B.FillRectAntialias(PX(P, K * Dt), PY(P, ECont(K * Dt)), PX(P, (K + 1) * Dt), PY(P, 0),
      HexPixel(ClrKi, 70));
    Sum := Sum + ECont(K * Dt) * Dt;
  end;
  SetLength(Curve, 401);
  for I := 0 to 400 do
    Curve[I] := ECont(I * 0.025);
  DrawSeries(B, P, Curve, 401, 0, 0.025, ClrText, 2, 200);
  for K := 0 to NS do
  begin
    X := PX(P, K * Dt);
    Y := PY(P, ECont(K * Dt));
    B.DrawLineAntialias(X, PY(P, 0), X, Y, HexPixel(ClrGold, 90), 1);
    B.FillEllipseAntialias(X, Y, 3.5, 3.5, HexPixel(ClrGold));
  end;
  // secant between the last two samples = digital derivative
  X := PX(P, (KCur - 1) * Dt);
  Y := PY(P, ECont((KCur - 1) * Dt));
  B.DrawLineAntialias(X, Y, PX(P, KCur * Dt), PY(P, ECont(KCur * Dt)), HexPixel(ClrKd), 3);
  CursorDot(B, P, KCur * Dt, ECont(KCur * Dt), ClrKd);
  Txt(B, PX(P, KCur * Dt) + 8, PY(P, ECont(KCur * Dt)) - 26, 'k = ' + IntToStr(KCur),
    ClrKd, 14, [fsBold]);

  Exact := EInt(KCur * Dt);
  DExact := EDer(KCur * Dt);
  DApprox := (ECont(KCur * Dt) - ECont((KCur - 1) * Dt)) / Dt;
  Txt(B, BotPanel.X1 + 24, BotPanel.Y1 + 50, Format('t = k · dt = %d × %.2f = %.2f s',
    [KCur, Dt, KCur * Dt]), ClrGold, 18, [fsBold]);
  Row(BotPanel.Y1 + 110, '∫ e dt', Exact, Sum, ClrKi);
  Row(BotPanel.Y1 + 160, 'de/dt', DExact, DApprox, ClrKd);
  Txt(B, BotPanel.X1 + 24, BotPanel.Y1 + 220,
    'dt เล็กลง → ค่าประมาณใกล้ค่าจริงมากขึ้น แต่ต้องคำนวณบ่อยขึ้น', ClrDim, 15);
  Txt(B, BotPanel.X1 + 24, BotPanel.Y1 + 246,
    'สี่เหลี่ยมใช้ค่าด้านซ้าย e[k]·dt จึงคลาดเคลื่อนสะสมเมื่อ dt ใหญ่', ClrDim, 15);
  inherited DrawDynamic(B);
end;

{ ---------------------------------------------------------------------------
  Pages 8-10 - real-world examples }

type
  TScenarioLesson = class(TLesson)
  private
    FScn: TScenario;
    FScale: Double; // display units per internal unit (setpoint slider)
    FWindupChip: Boolean;
    FChipBox: TBox;
  protected
    procedure SliderChanged(Sender: TObject); override;
  public
    constructor CreateFor(AScn: TScenario; const ATitle, ATab, AHints, AText: string;
      KpMax, KiMax, KdMax, SpMin, SpMax: Double; Decimals: Integer);
    destructor Destroy; override;
    procedure Enter; override;
    procedure Update(Dt: Double); override;
    procedure DrawStatic(B: TBGRABitmap); override;
    procedure DrawDynamic(B: TBGRABitmap); override;
    function MouseDown(X, Y: Single): Boolean; override;
    function KeyDown(Key: Word): Boolean; override;
  end;

const
  ScenePanelY2 = 410;

constructor TScenarioLesson.CreateFor(AScn: TScenario; const ATitle, ATab, AHints,
  AText: string; KpMax, KiMax, KdMax, SpMin, SpMax: Double; Decimals: Integer);
begin
  inherited Create;
  FScn := AScn;
  FScale := FScn.Display(1);
  Title := ATitle;
  TabName := ATab;
  Hints := AHints;
  FText := AText;
  FTextSize := 16;
  AddSlider('K', 'p', 0, KpMax, FScn.Pid.Gains.Kp, ClrKp, Decimals, 0, 4);
  AddSlider('K', 'i', 0, KiMax, FScn.Pid.Gains.Ki, ClrKi, Decimals + 1, 1, 4);
  AddSlider('K', 'd', 0, KdMax, FScn.Pid.Gains.Kd, ClrKd, Decimals, 2, 4);
  AddSlider('r', '', SpMin, SpMax, FScn.Setpoint * FScale, ClrText, 0, 3, 4);
  Slider(3).Units := FScn.OutUnit;
end;

destructor TScenarioLesson.Destroy;
begin
  FScn.Free;
  inherited Destroy;
end;

procedure TScenarioLesson.SliderChanged(Sender: TObject);
begin
  FScn.Pid.Gains := Gains(Slider(0).Value, Slider(1).Value, Slider(2).Value);
  FScn.Setpoint := Slider(3).Value / FScale;
end;

procedure TScenarioLesson.Enter;
begin
  inherited Enter;
  SliderChanged(nil);
  FScn.Reset;
end;

procedure TScenarioLesson.Update(Dt: Double);
begin
  inherited Update(Dt);
  FScn.Advance(Dt);
end;

procedure TScenarioLesson.DrawStatic(B: TBGRABitmap);
begin
  inherited DrawStatic(B);
  PlotPanel(B, Box(RightX1, ScenePanelY2 + 12, RightX2, ContentY2),
    FScn.OutLabel + ': y เทียบกับ r   และ   u');
end;

procedure TScenarioLesson.DrawDynamic(B: TBGRABitmap);
var
  P: TPlotBox;
  Slot, X0: Double;
  N, I: Integer;
  RS, YS: TDoubleArray;
  R: TBox;
begin
  FScn.DrawScene(B, Box(RightX1, ContentY - 4, RightX2, ScenePanelY2));

  N := FScn.History.Count;
  Slot := FScn.Span / FScn.History.Capacity;
  X0 := -(N - 1) * Slot;
  RS := FScn.History.Series(0);
  YS := FScn.History.Series(1);
  for I := 0 to N - 1 do
  begin
    RS[I] := FScn.Display(RS[I]);
    YS[I] := FScn.Display(YS[I]);
  end;
  R := Box(RightX1 + 56, ScenePanelY2 + 52, RightX2 - 18, 584);
  P := MakePlot(R, -FScn.Span, 0, FScn.YMin, FScn.YMax);
  DrawPlotGrid(B, P, FScn.YStep);
  DrawSeries(B, P, RS, N, X0, Slot, ClrText, 1.5, 170);
  DrawSeries(B, P, YS, N, X0, Slot, ClrGold, 2.6);
  Legend(B, RightX2 - 300, ScenePanelY2 + 22, ['r', 'y'], [ClrText, ClrGold]);
  Txt(B, RightX2 - 18, ScenePanelY2 + 20, 'y = ' +
    Fmt(FScn.Display(FScn.Output), 1) + FScn.OutUnit, ClrGold, 16, [fsBold], taRightJustify);

  R := Box(RightX1 + 56, 622, RightX2 - 18, ContentY2 - 24);
  P := MakePlot(R, -FScn.Span, 0, FScn.Pid.OutMin, FScn.Pid.OutMax);
  DrawPlotGrid(B, P, (FScn.Pid.OutMax - FScn.Pid.OutMin) / 2, FScn.Span / 4, ' s');
  DrawSeries(B, P, FScn.History.Series(2), N, X0, Slot, ClrKi, 1.8);
  Txt(B, RightX1 + 14, 640, 'u', ClrKi, 16, [fsBold]);

  if FWindupChip then
  begin
    FChipBox := Box(LeftX + LeftW - 230, ContentY2 - 186, LeftX + LeftW, ContentY2 - 158);
    if FScn.Pid.AntiWindup then
      Chip(B, FChipBox.X1, FChipBox.Y1, 'anti-windup: เปิด (W)', ClrKd, 14, True)
    else
      Chip(B, FChipBox.X1, FChipBox.Y1, 'anti-windup: ปิด (W)', ClrBad, 14, True);
  end;
  inherited DrawDynamic(B);
end;

function TScenarioLesson.MouseDown(X, Y: Single): Boolean;
begin
  Result := inherited MouseDown(X, Y);
  if not Result and FWindupChip and InBox(FChipBox, X, Y) then
    Result := KeyDown(VK_W);
end;

function TScenarioLesson.KeyDown(Key: Word): Boolean;
begin
  Result := True;
  case Key of
    VK_G: FScn.Disturb;
    VK_W: if FWindupChip then
        FScn.Pid.AntiWindup := not FScn.Pid.AntiWindup
      else
        Result := False;
  else
    Result := False;
  end;
end;

function CreateCruise: TLesson;
begin
  Result := TScenarioLesson.CreateFor(TCruiseScenario.Create,
    'ตัวอย่างที่ 1 — Cruise Control รถยนต์', 'รถยนต์',
    'G = ลมต้านแรง ๆ   R = เริ่มใหม่   ลองตั้ง Ki = 0 แล้วดูตอนขึ้นเนิน',
    Lines([
      '## รักษาความเร็วรถให้คงที่',
      '{w}r = ความเร็วที่ตั้ง   y = ความเร็วจริง   u = คันเร่ง (+) / เบรก (−)',
      'ถนนมีเนินขึ้นลงตลอด (แรงโน้มถ่วงคือ disturbance) และ มีแรงต้านอากาศ',
      '',
      '- {p}Kp: ช้ากว่าที่ตั้งมาก ยิ่งเหยียบคันเร่งมาก เกน 0.25 = คันเร่ง 25 % ต่อความเร็วต่าง 1 m/s',
      '- {i}Ki: ขึ้นเนินต้องใช้คันเร่ง "ค้าง" เพิ่มตลอด P อย่างเดียวจะช้ากว่าที่ตั้งเสมอ ' +
      'I จะค่อย ๆ เพิ่มคันเร่งจนความเร็วตรงพอดี',
      '- {d}Kd: ลดการกระชาก ทำให้นุ่มนวล ในรถจริงมักใช้น้อย เพราะสัญญาณความเร็วล้อมี noise',
      '',
      '> สังเกต: กราฟ u ด้านล่างขึ้นลงตามเนิน ในขณะที่ความเร็ว y แทบไม่เปลี่ยน ' +
      'นั่นคือ PID ทำงานถูกต้อง'
      ]), 1, 0.3, 0.3, 40, 120, 2);
end;

function CreateOven: TLesson;
begin
  Result := TScenarioLesson.CreateFor(TOvenScenario.Create,
    'ตัวอย่างที่ 2 — ควบคุมอุณหภูมิเตาอบ', 'เตาอบ',
    'W = เปิด/ปิด anti-windup แล้วกด R   G = เปิดประตูเตา (−30 °C)   เวลาเร่ง ×6',
    Lines([
      '## เตาอบ: ระบบช้า + dead time + ขีดจำกัด',
      '{w}r = อุณหภูมิที่ตั้ง   y = อุณหภูมิในเตา   u = กำลังฮีตเตอร์ 0–100 %',
      'ความร้อนใช้เวลา 4 วินาทีกว่าจะถึงเซนเซอร์ (dead time) และ เตาค่อย ๆ ร้อน (τ = 40 s)',
      '',
      '- {p}Kp: สูงไปจะแกว่ง เพราะตัวควบคุมเห็นผลช้า จึงใส่ความร้อนเกินไปก่อน',
      '- {i}Ki: ชดเชยความร้อนที่รั่วออกนอกเตา ที่ 180 °C ต้องค้าง u ≈ 52 %',
      '- {d}Kd: เห็นอุณหภูมิกำลังพุ่ง จึงลดไฟลงก่อนถึงเป้า',
      '',
      '## Integral windup',
      'ตอนอุ่นเตา u ติด 100 % นาน ถ้าปิด anti-windup ค่า I จะพองมาก → อุณหภูมิเกินเป้าไปไกล'
      ]), 0.08, 0.004, 0.2, 50, 250, 3);
  TScenarioLesson(Result).FWindupChip := True;
end;

function CreateDrone: TLesson;
begin
  Result := TScenarioLesson.CreateFor(TDroneScenario.Create,
    'ตัวอย่างที่ 3 — โดรนรักษาระดับความสูง', 'โดรน',
    'G = ลมกดลง   R = บินขึ้นใหม่   ลอง Ki = 0 (ลอยต่ำ) หรือ Kd = 0 (แกว่ง)',
    Lines([
      '## โดรน: สู้กับแรงโน้มถ่วงตลอดเวลา',
      '{w}r = ความสูงเป้าหมาย   y = ความสูงจริง   u = แรงขับใบพัด 0–100 %',
      'ต้องใช้แรงขับ 50 % เพื่อลอยนิ่ง (ขีดขาวบนเกจ) ถ้าน้อยกว่าจะตก ถ้ามากกว่าจะลอยขึ้น',
      '',
      '- {p}Kp: ต่ำกว่าเป้ามาก → เร่งใบพัดมาก',
      '- {i}Ki: สำคัญมาก! ถ้า Ki = 0 โดรนจะลอยต่ำกว่าเป้าเสมอ เพราะต้องมี error ค้าง ' +
      'เพื่อให้ P สร้างแรง 50 % (e = 0.5 / Kp = 2 m)',
      '- {d}Kd: เป็นแดมเปอร์ ระบบนี้แทบไม่มีแรงหน่วงตามธรรมชาติ ถ้าไม่มี D จะเด้งขึ้นลง',
      '',
      '> ในโดรนจริง มักเพิ่ม feed-forward (u = 50 % + PID) เพื่อลดภาระของ I'
      ]), 1, 0.5, 1, 0, 9, 2);
end;

{ ---------------------------------------------------------------------------
  Page 11 - using PIDCore in Lazarus + the vsync loop of this program }

type
  TCodeLesson = class(TLesson)
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
  end;

constructor TCodeLesson.Create;
begin
  inherited Create;
  Title := 'นำไปใช้งาน — PIDCore + BGRABitmap + OpenGL vsync ใน Lazarus';
  TabName := 'โค้ด';
  Hints := 'โค้ดทั้งหมดอยู่ใน Math 01\src และ Math 01\Explainer\src';
end;

procedure TCodeLesson.DrawStatic(B: TBGRABitmap);
begin
  DrawRichText(B, LeftX, ContentY, 580, Lines([
    '## 1. ตั้งค่าโปรเจกต์ใน Lazarus IDE',
    '- Project → Project Options → Paths → Other unit files: เพิ่ม ..\src',
    '- Project → Project Inspector → Add → New Requirement: BGRABitmapPack และ LazOpenGLContext',
    '',
    '## 2. ใช้ TPIDController',
    '` uses PIDCore;',
    '` var Pid: TPIDController;',
    '` Pid := TPIDController.Create(Gains(2.0, 0.5, 0.1));',
    '` Pid.OutMin := 0;  Pid.OutMax := 1;   // 0..100 %',
    '` Pid.DerivTau := 0.02;                // กรอง noise ของ D',
    '` // ทุกรอบ (Dt วินาที):',
    '` U := Pid.Update(Setpoint, ReadSensor, Dt);',
    '` WriteActuator(U);',
    '` // อ่านแต่ละเทอมได้: Pid.LastP, Pid.LastI, Pid.LastD',
    '',
    '## 3. ข้อควรระวัง',
    '- Dt ต้องเป็นวินาทีจริง ใช้ฟิสิกส์ sub-step คงที่ (เช่น 2 ms) แยกจากเฟรม',
    '- เรียก Pid.Reset เมื่อเริ่มใหม่ หรือ เปลี่ยนโหมด เพื่อล้าง I',
    '- ตั้ง OutMin/OutMax ให้ตรงขีดจำกัดของ actuator จริงเสมอ'
    ]), 16);
  DrawRichText(B, 650, ContentY, 598, Lines([
    '## 4. ลูป vsync: OpenGL + BGRABitmap (โปรแกรมนี้)',
    '` procedure TExplainerForm.AppIdle(Sender: TObject;',
    '`   var Done: Boolean);',
    '` begin',
    '`   FGL.Invalidate;  Done := False;   // วาดเฟรมถัดไปทันที',
    '` end;',
    '`',
    '` procedure TExplainerForm.GLPaint(Sender: TObject);',
    '` begin',
    '`   SetSwapInterval(1);               // vsync on',
    '`   T := NowSeconds;  Dt := T - FLast;  FLast := T;',
    '`   Explainer.Update(Dt);             // ฟิสิกส์ + PID',
    '`   Explainer.Render(FBuf);           // วาดด้วย BGRABitmap',
    '`   BGLViewPort(FGL.Width, FGL.Height, BGRABlack);',
    '`   BGLCanvas.StretchPutImage(X, Y, W, H, FBuf.Texture);',
    '`   FGL.SwapBuffers;                  // รอ vblank',
    '` end;',
    '',
    '- FBuf เป็น TBGLBitmap: วาดด้วย CPU (BGRABitmap) แล้วอัปโหลดเป็น texture',
    '- SwapBuffers บล็อกจนถึงจังหวะรีเฟรชจอ ลูปจึงเดินตาม 60 / 144 Hz ไม่มีภาพฉีก',
    '- ข้อความ/พื้นหลังของแต่ละหน้า cache ไว้ ทุกเฟรมวาดเฉพาะส่วนที่เคลื่อนไหว',
    '- กด V เพื่อเปิด/ปิด vsync และ F เพื่อดู fps'
    ]), 16);
end;

{ ---------------------------------------------------------------------------
  Page 12 - summary, tuning recipes and the Kp x Kd map from PID Tuning Explorer }

type
  TSummaryLesson = class(TLesson)
  public
    constructor Create; override;
    procedure DrawStatic(B: TBGRABitmap); override;
  end;

constructor TSummaryLesson.Create;
begin
  inherited Create;
  Title := 'สรุป — ผลของแต่ละเกน และ วิธีจูน';
  TabName := 'สรุป';
  Hints := 'แผนที่ด้านขวามาจาก PID Tuning Explorer (Math 01\bin\PIDTuner.exe)';
end;

procedure TSummaryLesson.DrawStatic(B: TBGRABitmap);
const
  Head: array[0..5] of string = ('เพิ่มค่า', 'เวลาขึ้น', 'Overshoot', 'เวลาเข้าที่',
    'Error ค้าง', 'เสถียรภาพ');
  Cells: array[0..2, 0..4] of string = (
    ('ลดลง', 'เพิ่มขึ้น', 'เล็กน้อย', 'ลดลง', 'แย่ลง'),
    ('ลดลง', 'เพิ่มขึ้น', 'เพิ่มขึ้น', 'หายไป', 'แย่ลง'),
    ('เล็กน้อย', 'ลดลง', 'ลดลง', 'ไม่มีผล', 'ดีขึ้น*'));
  Cols: array[0..5] of Single = (32, 132, 232, 342, 452, 552);
  RowH = 38;
var
  I, J: Integer;
  Y: Single;
  C: LongWord;
  Heat: THeatmap;
  Part: TBGRABitmap;
begin
  Panel(B, Box(LeftX - 8, ContentY - 4, 660, ContentY + 4 * RowH + 30));
  for J := 0 to 5 do
    Txt(B, Cols[J] + 8, ContentY + 8, Head[J], ClrDim, 15, [fsBold], taLeftJustify, 255, True);
  for I := 0 to 2 do
  begin
    Y := ContentY + 10 + (I + 1) * RowH;
    case I of
      0: C := ClrKp;
      1: C := ClrKi;
    else
      C := ClrKd;
    end;
    B.DrawLineAntialias(LeftX, Y - 6, 650, Y - 6, HexPixel(ClrGrid), 1);
    DrawSymbol(B, Cols[0] + 8, Y - 2, 'K', Copy('pid', I + 1, 1), HexPixel(C), 24);
    for J := 0 to 4 do
      Txt(B, Cols[J + 1] + 8, Y, Cells[I, J], ClrBody, 16, [], taLeftJustify, 255, True);
  end;
  Txt(B, LeftX, ContentY + 4 * RowH + 8, '* ถ้า Kd ไม่มากเกินไป และ สัญญาณมี noise ต่ำ',
    ClrDim, 13, [], taLeftJustify, 255, True);

  DrawRichText(B, LeftX, ContentY + 4 * RowH + 44, 610, Lines([
    '## วิธีจูนด้วยมือ (ใช้ได้กับระบบส่วนใหญ่)',
    '- 1) ตั้ง Ki = 0 และ Kd = 0',
    '- 2) เพิ่ม Kp จนตอบสนองเร็วพอ และ เริ่มมี overshoot เล็กน้อย',
    '- 3) เพิ่ม Kd เพื่อลด overshoot และ การแกว่ง',
    '- 4) เพิ่ม Ki ทีละน้อย จน error ค้างหายในเวลาที่ยอมรับได้',
    '- 5) ทดสอบกับ disturbance และ setpoint หลายระดับ ถ้าแกว่งให้ลด Ki ก่อน',
    '',
    '## Ziegler–Nichols (วงปิด)',
    'เพิ่ม Kp (Ki = Kd = 0) จนระบบแกว่งคงที่ ได้ Ku = Kp ขณะนั้น และ Tu = คาบการแกว่ง',
    '` Kp = 0.6 Ku    Ki = 1.2 Ku / Tu    Kd = 0.075 Ku · Tu',
    '> ZN ให้ค่าเริ่มต้นที่ค่อนข้างแรง (overshoot ~25 %) ใช้เป็นจุดเริ่ม แล้วปรับละเอียดต่อ'
    ]), 16);

  Panel(B, Box(690, ContentY - 4, RightX2, ContentY2));
  UseFont(B, 16, [fsBold], UIFont, True);
  B.TextOut(706, ContentY + 6, 'แผนที่คะแนน Kp × Kd (Ki = 2)', HexPixel(ClrText));
  Heat := THeatmap.Create(nil);
  Part := TBGRABitmap.Create(530, 420, HexPixel(ClrPanel));
  try
    Heat.SetBounds(0, 0, Part.Width, Part.Height);
    Heat.SetGrid(SweepKpKd(2, 0.5, 12, 0, 7, 10, 8, DefaultPlant));
    Heat.Select(3, 3);
    Heat.Render(Part);
    B.PutImage(706, ContentY + 36, Part, dmSet);
  finally
    Part.Free;
    Heat.Free;
  end;
  DrawRichText(B, 712, ContentY + 470, 520, Lines([
    'สีทอง = ตอบสนองดีที่สุด (ITAE ต่ำ overshoot น้อย) สีแดงเข้ม = แกว่ง / ไม่เสถียร ' +
    'โซนที่ดีเป็นแนวทแยง: ยิ่ง Kp สูง ยิ่งต้องการ Kd สูงขึ้นเพื่อหน่วง'
    ]), 15);
end;

{ --------------------------------------------------------------------------- }

function CreateAllLessons: TLessonList;
begin
  SetLength(Result, 12);
  Result[0] := TOverviewLesson.Create;
  Result[1] := TErrorLesson.Create;
  Result[2] := TKpLesson.Create;
  Result[3] := TKiLesson.Create;
  Result[4] := TKdLesson.Create;
  Result[5] := TOutputLesson.Create;
  Result[6] := TDtLesson.Create;
  Result[7] := CreateCruise;
  Result[8] := CreateOven;
  Result[9] := CreateDrone;
  Result[10] := TCodeLesson.Create;
  Result[11] := TSummaryLesson.Create;
end;

end.
