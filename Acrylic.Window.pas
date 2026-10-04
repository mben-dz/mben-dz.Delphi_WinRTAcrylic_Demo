unit Acrylic.Window;

{
  Port of window_subclass.rs (+ the winit WindowBuilder bits of main.rs).

  The Rust demo lets winit create the window and then subclasses it with
  SetWindowSubclass.  Here the window class owns the WndProc directly, so the
  "subclass" logic is simply the first half of that WndProc and the fall-through
  is DefWindowProc instead of DefSubclassProc.

  What it does (the standard "custom frame" recipe from Microsoft):
    * WS_EX_NOREDIRECTIONBITMAP     - DWM draws nothing behind the composition target
    * DwmExtendFrameIntoClientArea  - 2px top margin keeps the DWM shadow/border
    * WM_NCCALCSIZE                 - client area grows over the caption
    * WM_NCHITTEST                  - resize borders + the whole client area acts as caption
}

interface

uses
  System.SysUtils,
  System.Types,
  Winapi.Windows,
  Winapi.Messages,
  Winapi.Dwmapi,
  Winapi.UxTheme;

function CreateAcrylicWindow(const ATitle: string; AWidth, AHeight: Integer): HWND;

implementation

const
  WindowClassName = 'DelphiAcrylicDemoWindow';

  WS_EX_NOREDIRECTIONBITMAP = $00200000;

function IsDwmEnabled: Boolean;
var
  Enabled: BOOL;
begin
  Enabled := False;
  Result := Succeeded(DwmIsCompositionEnabled(Enabled)) and Enabled;
end;

// window_frame_borders()
function WindowFrameBorders(AWithCaption: Boolean): TRect;
var
  Style: DWORD;
begin
  if AWithCaption then
    Style := WS_OVERLAPPEDWINDOW
  else
    Style := WS_OVERLAPPEDWINDOW and not WS_CAPTION;
  Result := Rect(0, 0, 0, 0);
  AdjustWindowRectEx(Result, Style, False, 0);
end;

// hit_test_nca()
function HitTestNCA(AWnd: HWND; ALParam: LPARAM): LRESULT;
const
  HitTests: array[0..2, 0..2] of Integer = (
    (HTTOPLEFT,    HTCAPTION,   HTTOPRIGHT),   // row 0 (HTCAPTION slot replaced below by HTTOP)
    (HTLEFT,       HTNOWHERE,   HTRIGHT),
    (HTBOTTOMLEFT, HTBOTTOM,    HTBOTTOMRIGHT));
var
  X, Y, Row, Col: Integer;
  WindowRect, FrameRect, CaptionFrameRect: TRect;
  OnResizeBorder: Boolean;
begin
  X := SmallInt(ALParam and $FFFF);
  Y := SmallInt((ALParam shr 16) and $FFFF);

  GetWindowRect(AWnd, WindowRect);
  FrameRect := WindowFrameBorders(False);
  CaptionFrameRect := WindowFrameBorders(True);

  Row := 1;
  Col := 1;
  OnResizeBorder := False;

  // top / bottom
  if (Y >= WindowRect.Top) and (Y < WindowRect.Top - CaptionFrameRect.Top) then
  begin
    OnResizeBorder := Y < (WindowRect.Top - FrameRect.Top);
    Row := 0;
  end
  else if (Y < WindowRect.Bottom) and (Y >= WindowRect.Bottom - CaptionFrameRect.Bottom) then
    Row := 2;

  // left / right
  if (X >= WindowRect.Left) and (X < WindowRect.Left - CaptionFrameRect.Left) then
    Col := 0
  else if (X < WindowRect.Right) and (X >= WindowRect.Right - CaptionFrameRect.Right) then
    Col := 2;

  if (Row = 0) and (Col = 1) then
  begin
    if OnResizeBorder then Exit(HTTOP) else Exit(HTCAPTION);
  end;
  Result := HitTests[Row, Col];
end;

function AcrylicWndProc(AWnd: HWND; AMsg: UINT; AWParam: WPARAM; ALParam: LPARAM): LRESULT; stdcall;
var
  DwmResult: LRESULT;
  DwmHandled: Boolean;
  R: TRect;
  Margins: TMargins;
  FrameRect: TRect;
  CaptionHeight: Integer;
  HitResult: LRESULT;
begin
  if IsDwmEnabled then
  begin
    DwmResult := 0;
    DwmHandled := DwmDefWindowProc(AWnd, AMsg, AWParam, ALParam, DwmResult);

    if AMsg = WM_CREATE then
    begin
      GetWindowRect(AWnd, R);
      // Inform the application of the frame change.
      SetWindowPos(AWnd, 0, R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, SWP_FRAMECHANGED);
    end;

    if AMsg = WM_ACTIVATE then
    begin
      // Extend the frame into the client area.
      Margins := Default(TMargins);
      Margins.cyTopHeight := 2;
      DwmExtendFrameIntoClientArea(AWnd, Margins);
    end;

    if (AMsg = WM_NCCALCSIZE) and (AWParam <> 0) then
    begin
      FrameRect := WindowFrameBorders(True);
      CaptionHeight := -FrameRect.Top;
      // Custom NCA inset (falls through to DefWindowProc like the Rust version)
      with PNCCalcSizeParams(ALParam)^ do
      begin
        rgrc[0].Left := rgrc[0].Left - 0;
        rgrc[0].Top := rgrc[0].Top - CaptionHeight;
        rgrc[0].Right := rgrc[0].Right + 0;
        rgrc[0].Bottom := rgrc[0].Bottom + 1;
      end;
    end;

    if (AMsg = WM_NCHITTEST) and (DwmResult = 0) then
    begin
      HitResult := HitTestNCA(AWnd, ALParam);
      if HitResult = HTNOWHERE then
        Exit(HTCAPTION);
      Exit(HitResult);
    end;

    if DwmHandled then
      Exit(DwmResult);
  end;

  if AMsg = WM_DESTROY then
  begin
    PostQuitMessage(0);   // winit: CloseRequested -> ControlFlow::Exit
    Exit(0);
  end;

  Result := DefWindowProc(AWnd, AMsg, AWParam, ALParam);
end;

function CreateAcrylicWindow(const ATitle: string; AWidth, AHeight: Integer): HWND;
var
  WC: TWndClassEx;
begin
  WC := Default(TWndClassEx);
  WC.cbSize := SizeOf(WC);
  WC.style := CS_HREDRAW or CS_VREDRAW;
  WC.lpfnWndProc := @AcrylicWndProc;
  WC.hInstance := HInstance;
  WC.hCursor := LoadCursor(0, IDC_ARROW);
  WC.hbrBackground := 0;                 // nothing to paint: Composition owns the pixels
  WC.lpszClassName := WindowClassName;
  if RegisterClassEx(WC) = 0 then
    RaiseLastOSError;

  // with_visible(false) + with_no_redirection_bitmap(true)
  Result := CreateWindowEx(WS_EX_NOREDIRECTIONBITMAP, WindowClassName, PChar(ATitle),
    WS_OVERLAPPEDWINDOW, CW_USEDEFAULT, CW_USEDEFAULT, AWidth, AHeight,
    0, 0, HInstance, nil);
  if Result = 0 then
    RaiseLastOSError;
end;

end.
