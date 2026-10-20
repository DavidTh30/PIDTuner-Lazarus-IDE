unit CaptureKit;

{ Screen capture helpers shared by PID Tuning Explorer and PID Explainer.

  TGifRecorder streams an animated GIF straight to disk while recording:
  - each frame is scaled, compared with the previous one, and only the
    changed rectangle is written (disposal "do not dispose"),
  - an unchanged frame just makes the previous one last longer,
  - each written rectangle gets its own <= 256 colour palette
    (popularity on a 15-bit histogram + nearest colour, no dithering).
  Memory use stays at about two frames, however long the recording.
  The encoding runs on a worker thread: AddFrame only copies the frame into
  a short queue, so a vsync render loop keeps its frame rate. If the worker
  falls behind (Realtime = True), the newest queued frame is held longer
  instead of growing the queue; with Realtime = False (headless rendering)
  AddFrame waits for room so no frame is merged.

  CaptureFileName gives exe\captures\pid_yyyymmdd_hhnnss.<ext>. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Types, BGRABitmap, BGRABitmapTypes, BGRAGifFormat;

type
  TGifRecorder = class
  private
    FStream: TFileStream;
    FFileName: string;
    FScale: Double;
    FMaxMs, FElapsedMs: Integer;
    FWidth, FHeight: Integer;
    FPrev: TBGRABitmap;  // last scaled frame = what the GIF shows now
    FFrames: Integer;    // frames written
    // the newest frame waits here until its display time is known
    FHasPending: Boolean;
    FPendRect: TRect;
    FPendPal: TBGRAPixelBuffer;
    FPendIdx: TBytes;
    FPendMs: Integer;
    FCarryMs: Integer;   // rounding left over from the 1/100 s GIF delays
    // producer (caller) / consumer (worker thread) queue
    FLock: TRTLCriticalSection;
    FWake: PRTLEvent;
    FQueue: TFPList;     // of PQueuedFrame
    FPool: TFPList;      // reusable frame copies (no 4 MB allocation per frame)
    FWorker: TThread;
    FStopping: Boolean;
    FError: string;
    FAccepted: Integer;  // frames handed to AddFrame and kept
    procedure WriteHeader;
    procedure WritePending;
    procedure Encode(Src: TBGRABitmap; DelayMs: Integer);
    procedure WorkerLoop;
    function QueueCount: Integer;
  public
    Realtime: Boolean;
    constructor Create(const AFileName: string; AScale: Double = 0.5;
      AMaxSeconds: Integer = 60);
    destructor Destroy; override;
    { Src is the full-size frame (copied, the caller keeps it);
      DelayMs = time it stays on screen. AWidth / AHeight > 0 capture only
      the top-left part of Src (e.g. a power-of-two sized TBGLBitmap). }
    procedure AddFrame(Src: TBGRABitmap; DelayMs: Integer; AWidth: Integer = 0;
      AHeight: Integer = 0);
    { Writes the last frame and closes the file. Returns the frame count
      (0 = nothing recorded, the file is deleted). }
    function Finish: Integer;
    function FrameCount: Integer;
    function Seconds: Double;
    function Full: Boolean;
    { True once the worker hit an error; Finish raises it }
    function Failed: Boolean;
    property FileName: string read FFileName;
  end;

function CaptureFileName(const Ext: string): string;

implementation

const
  MaxQueue = 8; // full-size frames waiting for the worker (~4 MB each at 1280 x 760)

type
  PQueuedFrame = ^TQueuedFrame;
  TQueuedFrame = record
    Bmp: TBGRABitmap;
    DelayMs: Integer;
  end;

  TGifWorker = class(TThread)
  private
    FOwner: TGifRecorder;
  protected
    procedure Execute; override;
  end;

procedure TGifWorker.Execute;
begin
  FOwner.WorkerLoop;
end;

function CaptureFileName(const Ext: string): string;
var
  Dir: string;
begin
  Dir := ExtractFilePath(ParamStr(0)) + 'captures' + PathDelim;
  ForceDirectories(Dir);
  Result := Dir + 'pid_' + FormatDateTime('yyyymmdd_hhnnss', Now) + Ext;
  if FileExists(Result) then
    Result := Dir + 'pid_' + FormatDateTime('yyyymmdd_hhnnss_zzz', Now) + Ext;
end;

{ Bounding box of the pixels that differ; empty rect when identical }
function DiffRect(A, B: TBGRABitmap): TRect;
var
  X, Y, RowBytes: Integer;
  PA, PB: PLongWord;
begin
  Result := Rect(B.Width, B.Height, 0, 0);
  RowBytes := B.Width * SizeOf(TBGRAPixel);
  for Y := 0 to B.Height - 1 do
  begin
    PA := PLongWord(A.ScanLine[Y]);
    PB := PLongWord(B.ScanLine[Y]);
    if CompareMem(PA, PB, RowBytes) then
      Continue;
    if Y < Result.Top then
      Result.Top := Y;
    Result.Bottom := Y + 1;
    X := 0;
    while (X < Result.Left) and (PA[X] = PB[X]) do
      Inc(X);
    Result.Left := Min(Result.Left, X);
    X := B.Width - 1;
    while (X >= Result.Right) and (PA[X] = PB[X]) do
      Dec(X);
    Result.Right := Max(Result.Right, X + 1);
  end;
  if Result.Bottom = 0 then
    Result := Rect(0, 0, 0, 0);
end;

{ Palette (<= 256 colours) and one index per pixel for rectangle R of Bmp }
procedure Quantize(Bmp: TBGRABitmap; const R: TRect;
  out Pal: TBGRAPixelBuffer; out Idx: TBytes);
const
  Bins = 32768;
var
  Count: array of Integer;
  SumR, SumG, SumB: array of Int64;
  Lut: array of Byte;
  Order: array of Integer;
  P: PBGRAPixel;
  X, Y, I, J, K, Used, Best, D, BestD, N: Integer;
  C: TBGRAPixel;

  function KeyOf(Px: PBGRAPixel): Integer; inline;
  begin
    Result := (Px^.red shr 3) shl 10 or (Px^.green shr 3) shl 5 or (Px^.blue shr 3);
  end;

  function BinColor(B: Integer): TBGRAPixel;
  begin
    Result := BGRA(Byte(SumR[B] div Count[B]), Byte(SumG[B] div Count[B]),
      Byte(SumB[B] div Count[B]));
  end;

  procedure SortByCount(L, R: Integer); // descending
  var
    A, B, Pivot, T: Integer;
  begin
    while L < R do
    begin
      A := L;
      B := R;
      Pivot := Count[Order[(L + R) shr 1]];
      repeat
        while Count[Order[A]] > Pivot do Inc(A);
        while Count[Order[B]] < Pivot do Dec(B);
        if A <= B then
        begin
          T := Order[A]; Order[A] := Order[B]; Order[B] := T;
          Inc(A);
          Dec(B);
        end;
      until A > B;
      if L < B then
        SortByCount(L, B);
      L := A;
    end;
  end;

begin
  SetLength(Count, Bins);
  SetLength(SumR, Bins);
  SetLength(SumG, Bins);
  SetLength(SumB, Bins);
  for Y := R.Top to R.Bottom - 1 do
  begin
    P := Bmp.ScanLine[Y] + R.Left;
    for X := R.Left to R.Right - 1 do
    begin
      K := KeyOf(P);
      Inc(Count[K]);
      Inc(SumR[K], P^.red);
      Inc(SumG[K], P^.green);
      Inc(SumB[K], P^.blue);
      Inc(P);
    end;
  end;

  Used := 0;
  SetLength(Order, Bins);
  for I := 0 to Bins - 1 do
    if Count[I] > 0 then
    begin
      Order[Used] := I;
      Inc(Used);
    end;
  if Used > 1 then
    SortByCount(0, Used - 1);

  // palette = average colour of the most used bins
  SetLength(Pal, Max(1, Min(256, Used)));
  for I := 0 to Min(256, Used) - 1 do
    Pal[I] := BinColor(Order[I]);

  // every used bin -> nearest palette entry
  SetLength(Lut, Bins);
  for J := 0 to Used - 1 do
  begin
    K := Order[J];
    if J < Length(Pal) then
    begin
      Lut[K] := J;
      Continue;
    end;
    C := BinColor(K);
    Best := 0;
    BestD := MaxInt;
    for I := 0 to High(Pal) do
    begin
      D := Sqr(Integer(C.red) - Pal[I].red) * 3 + Sqr(Integer(C.green) - Pal[I].green) * 4 +
        Sqr(Integer(C.blue) - Pal[I].blue) * 2;
      if D < BestD then
      begin
        BestD := D;
        Best := I;
      end;
    end;
    Lut[K] := Best;
  end;

  SetLength(Idx, (R.Right - R.Left) * (R.Bottom - R.Top));
  N := 0;
  for Y := R.Top to R.Bottom - 1 do
  begin
    P := Bmp.ScanLine[Y] + R.Left;
    for X := R.Left to R.Right - 1 do
    begin
      Idx[N] := Lut[KeyOf(P)];
      Inc(N);
      Inc(P);
    end;
  end;
end;

{ TGifRecorder }

constructor TGifRecorder.Create(const AFileName: string; AScale: Double;
  AMaxSeconds: Integer);
begin
  inherited Create;
  FFileName := AFileName;
  FScale := EnsureRange(AScale, 0.1, 1);
  FMaxMs := AMaxSeconds * 1000;
  Realtime := True;
  FStream := TFileStream.Create(AFileName, fmCreate);
  InitCriticalSection(FLock);
  FWake := RTLEventCreate;
  FQueue := TFPList.Create;
  FPool := TFPList.Create;
  FWorker := TGifWorker.Create(True);
  TGifWorker(FWorker).FOwner := Self;
  FWorker.FreeOnTerminate := False;
  FWorker.Priority := tpLower; // the render loop comes first
  FWorker.Start;
end;

destructor TGifRecorder.Destroy;
var
  I: Integer;
begin
  try
    Finish;
  except
    // the error was already reported by an explicit Finish, or is moot here
  end;
  for I := 0 to FQueue.Count - 1 do
  begin
    PQueuedFrame(FQueue[I])^.Bmp.Free;
    Dispose(PQueuedFrame(FQueue[I]));
  end;
  FQueue.Free;
  for I := 0 to FPool.Count - 1 do
    TBGRABitmap(FPool[I]).Free;
  FPool.Free;
  RTLEventDestroy(FWake);
  DoneCriticalSection(FLock);
  FPrev.Free;
  inherited Destroy;
end;

function TGifRecorder.QueueCount: Integer;
begin
  EnterCriticalSection(FLock);
  try
    Result := FQueue.Count;
  finally
    LeaveCriticalSection(FLock);
  end;
end;

procedure TGifRecorder.WorkerLoop;
var
  Q: PQueuedFrame;
  Stop: Boolean;
begin
  repeat
    RTLEventWaitFor(FWake, 200);
    repeat
      Q := nil;
      EnterCriticalSection(FLock);
      try
        if FQueue.Count > 0 then
        begin
          Q := PQueuedFrame(FQueue[0]);
          FQueue.Delete(0);
        end;
        Stop := FStopping;
      finally
        LeaveCriticalSection(FLock);
      end;
      if Q <> nil then
      begin
        try
          if FError = '' then
            Encode(Q^.Bmp, Q^.DelayMs);
        except
          on E: Exception do
            FError := E.Message;
        end;
        EnterCriticalSection(FLock);
        try
          if FPool.Count < MaxQueue then
            FPool.Add(Q^.Bmp)
          else
            Q^.Bmp.Free;
        finally
          LeaveCriticalSection(FLock);
        end;
        Dispose(Q);
      end;
    until Q = nil;
  until Stop;
end;

procedure TGifRecorder.AddFrame(Src: TBGRABitmap; DelayMs: Integer;
  AWidth: Integer; AHeight: Integer);
var
  Q: PQueuedFrame;
  Bmp: TBGRABitmap;
  Y: Integer;
  Busy: Boolean;
begin
  if (FStream = nil) or FStopping or Full or (FError <> '') then
    Exit;
  if AWidth <= 0 then
    AWidth := Src.Width;
  if AHeight <= 0 then
    AHeight := Src.Height;
  if not Realtime then
    while QueueCount >= MaxQueue do
      Sleep(2);
  Inc(FElapsedMs, DelayMs);

  Bmp := nil;
  EnterCriticalSection(FLock);
  try
    Busy := FQueue.Count >= MaxQueue;
    if Busy then
      // encoder is behind: the newest queued frame simply stays longer
      Inc(PQueuedFrame(FQueue.Last)^.DelayMs, DelayMs)
    else if FPool.Count > 0 then
    begin
      Bmp := TBGRABitmap(FPool.Last);
      FPool.Delete(FPool.Count - 1);
    end;
  finally
    LeaveCriticalSection(FLock);
  end;
  if Busy then
    Exit;

  // a plain TBGRABitmap copy, row by row: Src may be a TBGLBitmap (OpenGL
  // texture), which must not be duplicated or freed on the worker thread
  if (Bmp <> nil) and ((Bmp.Width <> AWidth) or (Bmp.Height <> AHeight)) then
    FreeAndNil(Bmp);
  if Bmp = nil then
    Bmp := TBGRABitmap.Create(AWidth, AHeight);
  for Y := 0 to AHeight - 1 do
    Move(Src.ScanLine[Y]^, Bmp.ScanLine[Y]^, AWidth * SizeOf(TBGRAPixel));
  Bmp.InvalidateBitmap;

  New(Q);
  Q^.Bmp := Bmp;
  Q^.DelayMs := DelayMs;
  EnterCriticalSection(FLock);
  try
    FQueue.Add(Q);
    Inc(FAccepted);
  finally
    LeaveCriticalSection(FLock);
  end;
  RTLEventSetEvent(FWake);
end;

procedure TGifRecorder.WriteHeader;
const
  Sig: array[0..5] of Char = 'GIF89a';
  App: string = 'NETSCAPE2.0';
begin
  FStream.WriteBuffer(Sig, 6);
  FStream.WriteWord(NtoLE(Word(FWidth)));
  FStream.WriteWord(NtoLE(Word(FHeight)));
  FStream.WriteByte(0); // no global colour table
  FStream.WriteByte(0); // background index
  FStream.WriteByte(0); // aspect ratio
  // loop forever
  FStream.WriteByte($21);
  FStream.WriteByte($FF);
  FStream.WriteByte(Length(App));
  FStream.WriteBuffer(App[1], Length(App));
  FStream.WriteByte(3);
  FStream.WriteByte(1);
  FStream.WriteWord(0);
  FStream.WriteByte(0);
end;

procedure TGifRecorder.WritePending;
var
  Bits, I, Cs: Integer;
begin
  if not FHasPending then
    Exit;
  FHasPending := False;
  Bits := Max(2, CeilLn2(Length(FPendPal)));
  // delay in 1/100 s; the remainder carries over so long recordings keep time
  Cs := Max(2, Round((FPendMs + FCarryMs) / 10));
  FCarryMs := FPendMs + FCarryMs - Cs * 10;
  // graphic control extension: disposal 1 = keep
  FStream.WriteByte($21);
  FStream.WriteByte($F9);
  FStream.WriteByte(4);
  FStream.WriteByte(1 shl 2);
  FStream.WriteWord(NtoLE(Word(Cs)));
  FStream.WriteByte(0);
  FStream.WriteByte(0);
  // image descriptor with a local colour table
  FStream.WriteByte($2C);
  FStream.WriteWord(NtoLE(Word(FPendRect.Left)));
  FStream.WriteWord(NtoLE(Word(FPendRect.Top)));
  FStream.WriteWord(NtoLE(Word(FPendRect.Right - FPendRect.Left)));
  FStream.WriteWord(NtoLE(Word(FPendRect.Bottom - FPendRect.Top)));
  FStream.WriteByte($80 or (Bits - 1));
  for I := 0 to (1 shl Bits) - 1 do
    if I < Length(FPendPal) then
    begin
      FStream.WriteByte(FPendPal[I].red);
      FStream.WriteByte(FPendPal[I].green);
      FStream.WriteByte(FPendPal[I].blue);
    end
    else
    begin
      FStream.WriteByte(0);
      FStream.WriteByte(0);
      FStream.WriteByte(0);
    end;
  GIFEncodeLZW(FStream, @FPendIdx[0], FPendRect.Right - FPendRect.Left,
    FPendRect.Bottom - FPendRect.Top, Bits);
  Inc(FFrames);
end;

{ Worker thread: scale, diff, quantize, write the previous frame }
procedure TGifRecorder.Encode(Src: TBGRABitmap; DelayMs: Integer);
var
  Frame: TBGRABitmap;
  R: TRect;
  Pal: TBGRAPixelBuffer;
  Idx: TBytes;
begin
  if FWidth = 0 then
  begin
    FWidth := Max(1, Round(Src.Width * FScale));
    FHeight := Max(1, Round(Src.Height * FScale));
    WriteHeader;
  end;
  if (Src.Width = FWidth) and (Src.Height = FHeight) then
    Frame := Src.Duplicate as TBGRABitmap
  else
    Frame := Src.Resample(FWidth, FHeight, rmFineResample) as TBGRABitmap;

  if FPrev = nil then
    R := Rect(0, 0, FWidth, FHeight)
  else
    R := DiffRect(FPrev, Frame);
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
  begin
    // nothing changed: the frame on screen just stays longer
    if FHasPending then
      Inc(FPendMs, DelayMs);
    Frame.Free;
    Exit;
  end;

  WritePending;
  Quantize(Frame, R, Pal, Idx);
  FPendPal := Pal;
  FPendIdx := Idx;
  FPendRect := R;
  FPendMs := DelayMs;
  FHasPending := True;
  FPrev.Free;
  FPrev := Frame;
end;

function TGifRecorder.Finish: Integer;
begin
  Result := FFrames;
  if FStream = nil then
    Exit;
  // let the worker drain the queue, then stop it
  EnterCriticalSection(FLock);
  FStopping := True;
  LeaveCriticalSection(FLock);
  RTLEventSetEvent(FWake);
  FWorker.WaitFor;
  FreeAndNil(FWorker);

  WritePending;
  Result := FFrames;
  if FWidth > 0 then
    FStream.WriteByte($3B);
  FreeAndNil(FStream);
  if Result = 0 then
    DeleteFile(FFileName);
  if FError <> '' then
    raise Exception.Create('GIF: ' + FError);
end;

function TGifRecorder.FrameCount: Integer;
begin
  Result := FAccepted;
end;

function TGifRecorder.Seconds: Double;
begin
  Result := FElapsedMs / 1000;
end;

function TGifRecorder.Failed: Boolean;
begin
  Result := FError <> '';
end;

function TGifRecorder.Full: Boolean;
begin
  Result := FElapsedMs >= FMaxMs;
end;

end.
