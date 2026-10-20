{ Platform helpers: high resolution clock and OpenGL swap interval (vsync).
  Kept in its own unit so the Windows unit does not shadow LCL types. }
unit uPlatform;

{$mode objfpc}{$H+}

interface

{ Seconds from an arbitrary origin, sub-millisecond precision on Windows }
function NowSeconds: Double;

{ Must be called with the OpenGL context current.
  Returns False if the driver does not expose a swap-interval extension. }
function SetSwapInterval(AInterval: Integer): Boolean;

implementation

uses
  {$IFDEF WINDOWS}Windows, GL, GLext{$ELSE}SysUtils{$ENDIF};

{$IFDEF WINDOWS}
var
  QpcFreq: Int64 = 0;
  SwapLoaded: Boolean = False;
  SwapSupported: Boolean = False;

function NowSeconds: Double;
var
  c: Int64;
begin
  if QpcFreq = 0 then QueryPerformanceFrequency(QpcFreq);
  QueryPerformanceCounter(c);
  Result := c / QpcFreq;
end;

function SetSwapInterval(AInterval: Integer): Boolean;
begin
  if not SwapLoaded then
  begin
    SwapLoaded := True;
    try
      SwapSupported := Load_WGL_EXT_swap_control;
    except
      SwapSupported := False;
    end;
  end;
  Result := SwapSupported and Assigned(wglSwapIntervalEXT);
  if Result then
    Result := wglSwapIntervalEXT(AInterval);
end;
{$ELSE}
function NowSeconds: Double;
begin
  Result := GetTickCount64 / 1000;
end;

function SetSwapInterval(AInterval: Integer): Boolean;
begin
  { TODO: glXSwapIntervalEXT / NSOpenGLContext setValues on other platforms }
  Result := False;
end;
{$ENDIF}

end.
