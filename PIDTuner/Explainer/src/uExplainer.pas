{ PID Explainer - page host: header, tab bar, cached static layer per page,
  input routing, PNG / GIF capture. Renders into any TBGRABitmap (TBGLBitmap
  on screen, a plain TBGRABitmap for --snapshot).
  Frame order on screen: Render (content) -> Capture (PNG / GIF frame)
  -> RenderOverlay (capture buttons, fps, messages), so captures never
  contain the overlay. }
unit uExplainer;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, LCLType, Graphics, BGRABitmap, BGRABitmapTypes,
  BGRAView, PIDCore, CaptureKit, uDrawKit, uLessons;

const
  GifFps = 12;
  GifScale = 0.75;   // 960 x 570: Thai body text stays readable
  GifMaxSeconds = 60;

type
  TExplainer = class
  private
    FLessons: TLessonList;
    FStatic: array of TBGRABitmap;
    FTabs: array of TBox;
    FPage, FHotTab, FHotBtn: Integer;
    FBtnPng, FBtnGif: TBox;
    FRecorder: TGifRecorder;
    FRecAcc: Double;
    FCapBuf: TBGRABitmap; // canvas-sized copy of the frame for captures
    FPngPending: Boolean;
    FMsg: string;
    FMsgTime: Double;
    procedure BuildStatic(I: Integer);
    function TabAt(X, Y: Single): Integer;
    procedure ShowMsg(const S: string);
  public
    Paused, ShowFps, VSyncOn: Boolean;
    Fps: Double;
    constructor Create;
    destructor Destroy; override;
    procedure SetPage(I: Integer);
    procedure Update(Dt: Double);
    procedure Render(B: TBGRABitmap);
    { Saves a pending PNG and feeds the GIF recorder from the finished frame }
    procedure Capture(B: TBGRABitmap; Dt: Double);
    procedure RenderOverlay(B: TBGRABitmap);
    procedure RequestPng;
    procedure ToggleGif;
    function Recording: Boolean;
    procedure MouseDown(X, Y: Single);
    procedure MouseMove(X, Y: Single);
    procedure MouseUp;
    function KeyDown(Key: Word): Boolean;
    function PageCount: Integer;
    property Page: Integer read FPage;
  end;

implementation

const
  HeaderH = 76;
  TabY1 = 714;
  TabY2 = 750;

constructor TExplainer.Create;
var
  I: Integer;
  W: Single;
begin
  inherited Create;
  FLessons := CreateAllLessons;
  SetLength(FStatic, Length(FLessons));
  SetLength(FTabs, Length(FLessons));
  W := (CanvasW - 64) / Length(FLessons);
  for I := 0 to High(FTabs) do
    FTabs[I] := Box(32 + I * W + 3, TabY1, 32 + (I + 1) * W - 3, TabY2);
  FHotTab := -1;
  FHotBtn := -1;
  FBtnPng := Box(988, 14, 1068, 44);
  FBtnGif := Box(1076, 14, 1156, 44);
  ShowFps := True;
  VSyncOn := True;
  FPage := -1;
  SetPage(0);
end;

destructor TExplainer.Destroy;
var
  I: Integer;
begin
  FRecorder.Free; // finishes the GIF if still recording
  FCapBuf.Free;
  for I := 0 to High(FLessons) do
  begin
    FLessons[I].Free;
    FStatic[I].Free;
  end;
  inherited Destroy;
end;

function TExplainer.PageCount: Integer;
begin
  Result := Length(FLessons);
end;

procedure TExplainer.SetPage(I: Integer);
begin
  I := EnsureRange(I, 0, High(FLessons));
  if I = FPage then
    Exit;
  if FPage >= 0 then
    FLessons[FPage].MouseUp;
  FPage := I;
  FLessons[FPage].Enter;
end;

procedure TExplainer.BuildStatic(I: Integer);
var
  B: TBGRABitmap;
  L: TLesson;
  J: Integer;
  S: string;
begin
  L := FLessons[I];
  B := TBGRABitmap.Create(CanvasW, CanvasH, HexPixel(ClrBackground));
  Txt(B, 32, 14, L.Title, ClrText, 28, [fsBold], taLeftJustify, 255, True);
  Txt(B, 34, 52, L.Hints, ClrDim, 14, [], taLeftJustify, 255, True);
  B.DrawLineAntialias(32, HeaderH, CanvasW - 32, HeaderH, HexPixel(ClrGrid), 1);
  Txt(B, CanvasW - 32, 20, Format('%d / %d', [I + 1, Length(FLessons)]), ClrDim, 18,
    [], taRightJustify, 255, True);
  for J := 0 to High(FTabs) do
  begin
    S := FLessons[J].TabName;
    if J < 10 then
      S := IntToStr((J + 1) mod 10) + '  ' + S;
    if J = I then
    begin
      Panel(B, FTabs[J], ClrKnobTrack, 8);
      Txt(B, (FTabs[J].X1 + FTabs[J].X2) / 2, TabY1 + 7, S, ClrGold, 14, [fsBold],
        taCenter, 255, True);
    end
    else
    begin
      Panel(B, FTabs[J], ClrPanel, 8);
      Txt(B, (FTabs[J].X1 + FTabs[J].X2) / 2, TabY1 + 7, S, ClrDim, 14, [],
        taCenter, 255, True);
    end;
  end;
  L.DrawStatic(B);
  FStatic[I] := B;
end;

procedure TExplainer.Update(Dt: Double);
begin
  if not Paused then
    FLessons[FPage].Update(Dt);
end;

procedure TExplainer.Render(B: TBGRABitmap);
begin
  if FStatic[FPage] = nil then
    BuildStatic(FPage);
  B.PutImage(0, 0, FStatic[FPage], dmSet);
  FLessons[FPage].DrawDynamic(B);
  if (FHotTab >= 0) and (FHotTab <> FPage) then
    B.RoundRectAntialias(FTabs[FHotTab].X1, FTabs[FHotTab].Y1, FTabs[FHotTab].X2,
      FTabs[FHotTab].Y2, 8, 8, HexPixel(ClrGold, 150), 1.5);
end;

procedure TExplainer.ShowMsg(const S: string);
begin
  FMsg := S;
  FMsgTime := 4;
end;

procedure TExplainer.RequestPng;
begin
  FPngPending := True;
end;

function TExplainer.Recording: Boolean;
begin
  Result := FRecorder <> nil;
end;

procedure TExplainer.ToggleGif;
var
  N: Integer;
begin
  if FRecorder = nil then
  begin
    FRecorder := TGifRecorder.Create(CaptureFileName('.gif'), GifScale, GifMaxSeconds);
    FRecAcc := 1; // take the first frame right away
    Exit;
  end;
  try
    N := FRecorder.Finish;
    ShowMsg(Format('บันทึก %s  (%d เฟรม, %.1f s)',
      [ExtractFileName(FRecorder.FileName), N, FRecorder.Seconds]));
  except
    on E: Exception do
      ShowMsg('GIF ผิดพลาด: ' + E.Message);
  end;
  FreeAndNil(FRecorder);
end;

procedure TExplainer.Capture(B: TBGRABitmap; Dt: Double);
var
  FileName: string;

  { B may be a TBGLBitmap whose size is rounded up to a power of two
    (2048 x 1024); captures use only the design canvas in its top-left }
  function Canvas: TBGRABitmap;
  begin
    if (B.Width = CanvasW) and (B.Height = CanvasH) then
      Exit(B);
    if FCapBuf = nil then
      FCapBuf := TBGRABitmap.Create(CanvasW, CanvasH);
    FCapBuf.PutImage(0, 0, B, dmSet);
    Result := FCapBuf;
  end;

begin
  FMsgTime := FMsgTime - Dt;
  if FPngPending then
  begin
    FPngPending := False;
    FileName := CaptureFileName('.png');
    Canvas.SaveToFile(FileName);
    ShowMsg('บันทึก ' + ExtractFileName(FileName));
  end;
  if FRecorder = nil then
    Exit;
  if FRecorder.Failed then
  begin
    ToggleGif; // stops and reports the error
    Exit;
  end;
  FRecAcc := FRecAcc + Dt;
  if FRecAcc >= 1 / GifFps - 0.002 then
  begin
    FRecorder.AddFrame(B, Max(10, Round(Min(FRecAcc, 0.5) * 1000)), CanvasW, CanvasH);
    FRecAcc := 0;
    if FRecorder.Full then
      ToggleGif;
  end;
end;

procedure TExplainer.RenderOverlay(B: TBGRABitmap);
var
  S: string;

  procedure Button(const R: TBox; Hot, Active: Boolean; const Caption: string; Rec: Boolean);
  var
    Border: LongWord;
    CX, CY: Single;
  begin
    if Active then
      Border := ClrBad
    else if Hot then
      Border := ClrGold
    else
      Border := ClrKnobTrack;
    Panel(B, R, ClrPanel, 8);
    B.RoundRectAntialias(R.X1, R.Y1, R.X2, R.Y2, 8, 8, HexPixel(Border), 1.5);
    CX := R.X1 + 18;
    CY := (R.Y1 + R.Y2) / 2;
    if not Rec then
    begin
      B.FillRoundRectAntialias(CX - 9, CY - 6, CX + 9, CY + 7, 2, 2, HexPixel(ClrText));
      B.FillRectAntialias(CX - 4, CY - 9, CX + 3, CY - 5, HexPixel(ClrText));
      B.FillEllipseAntialias(CX, CY + 0.5, 4, 4, HexPixel(ClrPanel));
      B.FillEllipseAntialias(CX, CY + 0.5, 2, 2, HexPixel(ClrText));
    end
    else if Active then
      B.FillRoundRectAntialias(CX - 6, CY - 6, CX + 6, CY + 6, 2, 2, HexPixel(ClrBad))
    else
      B.FillEllipseAntialias(CX, CY, 6.5, 6.5, HexPixel(ClrBad));
    Txt(B, (R.X1 + 30 + R.X2) / 2, CY - 10, Caption, ClrText, 15, [fsBold], taCenter);
  end;

begin
  Button(FBtnPng, FHotBtn = 0, False, 'PNG', False);
  if Recording then
    Button(FBtnGif, FHotBtn = 1, True, 'Stop', True)
  else
    Button(FBtnGif, FHotBtn = 1, False, 'GIF', True);

  S := '';
  if Recording then
  begin
    if Frac(FRecorder.Seconds) < 0.5 then
      B.FillEllipseAntialias(FBtnPng.X1 - 16, 29, 5, 5, HexPixel(ClrBad));
    S := Format('REC %.1f s  (%d เฟรม)   ', [FRecorder.Seconds, FRecorder.FrameCount]);
  end
  else if FMsgTime > 0 then
    S := FMsg + '   ';
  if Paused then
    S := S + 'หยุดชั่วคราว (Space)   ';
  if ShowFps then
    S := S + Format('%.0f fps  vsync %s', [Fps, BoolToStr(VSyncOn, 'on', 'off')]);
  if S <> '' then
  begin
    B.FillRectAntialias(CanvasW - 32 - TxtW(B, S, 13) - 6, 50, CanvasW - 30, 70,
      HexPixel(ClrBackground));
    if Recording or (FMsgTime > 0) then
      Txt(B, CanvasW - 32, 52, S, ClrGold, 13, [], taRightJustify)
    else
      Txt(B, CanvasW - 32, 52, S, ClrDim, 13, [], taRightJustify);
  end;
end;

function TExplainer.TabAt(X, Y: Single): Integer;
var
  I: Integer;
begin
  for I := 0 to High(FTabs) do
    if InBox(FTabs[I], X, Y) then
      Exit(I);
  Result := -1;
end;

procedure TExplainer.MouseDown(X, Y: Single);
var
  T: Integer;
begin
  if InBox(FBtnPng, X, Y) then
  begin
    RequestPng;
    Exit;
  end;
  if InBox(FBtnGif, X, Y) then
  begin
    ToggleGif;
    Exit;
  end;
  T := TabAt(X, Y);
  if T >= 0 then
    SetPage(T)
  else
    FLessons[FPage].MouseDown(X, Y);
end;

procedure TExplainer.MouseMove(X, Y: Single);
begin
  FHotTab := TabAt(X, Y);
  if InBox(FBtnPng, X, Y) then
    FHotBtn := 0
  else if InBox(FBtnGif, X, Y) then
    FHotBtn := 1
  else
    FHotBtn := -1;
  FLessons[FPage].MouseMove(X, Y);
end;

procedure TExplainer.MouseUp;
begin
  FLessons[FPage].MouseUp;
end;

function TExplainer.KeyDown(Key: Word): Boolean;
begin
  Result := True;
  case Key of
    VK_RIGHT, VK_NEXT: SetPage(FPage + 1);
    VK_LEFT, VK_PRIOR: SetPage(FPage - 1);
    VK_HOME: SetPage(0);
    VK_END: SetPage(High(FLessons));
    VK_1..VK_9: SetPage(Key - VK_1);
    VK_0: SetPage(9);
    VK_SPACE: Paused := not Paused;
    VK_F: ShowFps := not ShowFps;
    VK_R: FLessons[FPage].Enter;
  else
    Result := FLessons[FPage].KeyDown(Key);
  end;
end;

end.
