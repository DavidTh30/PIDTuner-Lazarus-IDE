{ PID Explainer - main window: TOpenGLControl + BGRAOpenGL, vsync paced loop.
  Each frame is drawn by BGRABitmap into a TBGLBitmap at the fixed design
  size, uploaded as a texture and letterboxed to the window. }
unit uExplainerForm;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Math, Forms, Controls, Graphics, LCLType,
  OpenGLContext, BGRABitmap, BGRABitmapTypes, BGRAOpenGL,
  uDrawKit, uExplainer;

const
  APP_NAME = 'PID Explainer';

type

  { TExplainerForm }

  TExplainerForm = class(TForm)
  private
    FGL: TOpenGLControl;
    FBuf: TBGLBitmap;
    FExplainer: TExplainer;
    FLastTime, FFpsClock: Double;
    FFrames: Integer;
    FVSyncApplied: Integer;
    FVSyncOk: Boolean;
    FPrevBounds: TRect;
    FViewX, FViewY: Integer;
    FViewScale: Single;
    procedure GLPaint(Sender: TObject);
    procedure GLMouseDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure GLMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
    procedure GLMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure AppIdle(Sender: TObject; var Done: Boolean);
    procedure FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    function ToCanvasX(X: Integer): Single;
    function ToCanvasY(Y: Integer): Single;
    procedure ToggleFullScreen;
  public
    constructor Create(TheOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  ExplainerForm: TExplainerForm;

implementation

uses
  uPlatform;

{ TExplainerForm }

constructor TExplainerForm.Create(TheOwner: TComponent);
begin
  { No .lfm: build the UI in code }
  inherited CreateNew(TheOwner);
  Caption := APP_NAME;
  Color := clBlack;
  KeyPreview := True;
  Position := poScreenCenter;
  ClientWidth := Min(CanvasW, Screen.WorkAreaWidth - 40);
  ClientHeight := Round(ClientWidth * CanvasH / CanvasW);
  OnKeyDown := @FormKeyDown;

  FExplainer := TExplainer.Create;
  { FBuf (TBGLBitmap) is created in the first paint: it needs a current GL context }
  FVSyncApplied := -1;
  FViewScale := 1;

  FGL := TOpenGLControl.Create(Self);
  FGL.Parent := Self;
  FGL.Align := alClient;
  FGL.AutoResizeViewport := True;
  FGL.DoubleBuffered := True;
  FGL.OnPaint := @GLPaint;
  FGL.OnMouseDown := @GLMouseDown;
  FGL.OnMouseMove := @GLMouseMove;
  FGL.OnMouseUp := @GLMouseUp;

  FLastTime := NowSeconds;
  FFpsClock := FLastTime;
  Application.AddOnIdleHandler(@AppIdle);
end;

destructor TExplainerForm.Destroy;
begin
  Application.RemoveOnIdleHandler(@AppIdle);
  FBuf.Free;
  FExplainer.Free;
  inherited Destroy;
end;

procedure TExplainerForm.AppIdle(Sender: TObject; var Done: Boolean);
begin
  if (WindowState = wsMinimized) or not Visible then
  begin
    Done := True;
    Exit;
  end;
  { With vsync on, SwapBuffers blocks until the next vblank, so this loop
    is paced by the display refresh rate. }
  FGL.Invalidate;
  Done := False;
end;

procedure TExplainerForm.GLPaint(Sender: TObject);
var
  W, H, VW, VH: Integer;
  T, Dt: Double;
begin
  if FVSyncApplied <> Ord(FExplainer.VSyncOn) then
  begin
    FVSyncOk := SetSwapInterval(Ord(FExplainer.VSyncOn));
    FVSyncApplied := Ord(FExplainer.VSyncOn);
  end;

  T := NowSeconds;
  Dt := EnsureRange(T - FLastTime, 0, 0.1);
  FLastTime := T;

  W := FGL.Width;
  H := FGL.Height;
  if (W < 2) or (H < 2) then
    Exit;
  if FBuf = nil then
    FBuf := TBGLBitmap.Create(CanvasW, CanvasH);

  FExplainer.Update(Dt);
  FExplainer.Render(FBuf);
  FExplainer.Capture(FBuf, Dt);      // PNG / GIF frame, before the overlay
  FExplainer.RenderOverlay(FBuf);

  // letterbox the fixed design canvas into the window
  FViewScale := Min(W / CanvasW, H / CanvasH);
  VW := Round(CanvasW * FViewScale);
  VH := Round(CanvasH * FViewScale);
  FViewX := (W - VW) div 2;
  FViewY := (H - VH) div 2;
  BGLViewPort(W, H, BGRA(14, 17, 23));
  if (VW = CanvasW) and (VH = CanvasH) then
    BGLCanvas.PutImage(FViewX, FViewY, FBuf.Texture)
  else
    BGLCanvas.StretchPutImage(FViewX, FViewY, VW, VH, FBuf.Texture);
  FGL.SwapBuffers;

  Inc(FFrames);
  if T - FFpsClock >= 0.5 then
  begin
    FExplainer.Fps := FFrames / (T - FFpsClock);
    FFrames := 0;
    FFpsClock := T;
    if FVSyncOk then
      Caption := Format('%s  —  %.0f fps, vsync %s', [APP_NAME, FExplainer.Fps,
        BoolToStr(FExplainer.VSyncOn, 'on', 'off')])
    else
      Caption := Format('%s  —  %.0f fps (driver has no vsync control)',
        [APP_NAME, FExplainer.Fps]);
  end;
end;

function TExplainerForm.ToCanvasX(X: Integer): Single;
begin
  Result := (X - FViewX) / FViewScale;
end;

function TExplainerForm.ToCanvasY(Y: Integer): Single;
begin
  Result := (Y - FViewY) / FViewScale;
end;

procedure TExplainerForm.GLMouseDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FExplainer.MouseDown(ToCanvasX(X), ToCanvasY(Y));
end;

procedure TExplainerForm.GLMouseMove(Sender: TObject; Shift: TShiftState; X, Y: Integer);
begin
  FExplainer.MouseMove(ToCanvasX(X), ToCanvasY(Y));
end;

procedure TExplainerForm.GLMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if Button = mbLeft then
    FExplainer.MouseUp;
end;

procedure TExplainerForm.ToggleFullScreen;
begin
  if BorderStyle <> bsNone then
  begin
    FPrevBounds := BoundsRect;
    BorderStyle := bsNone;
    BoundsRect := Monitor.BoundsRect;
  end
  else
  begin
    BorderStyle := bsSizeable;
    BoundsRect := FPrevBounds;
  end;
end;

procedure TExplainerForm.FormKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if ssCtrl in Shift then
  begin
    case Key of
      VK_S: FExplainer.RequestPng;
      VK_G: FExplainer.ToggleGif;
    else
      Exit;
    end;
    Key := 0;
    Exit;
  end;
  case Key of
    VK_F11: ToggleFullScreen;
    VK_ESCAPE: if BorderStyle = bsNone then ToggleFullScreen;
    VK_V: FExplainer.VSyncOn := not FExplainer.VSyncOn;
  else
    if not FExplainer.KeyDown(Key) then
      Exit;
  end;
  Key := 0;
end;

end.
