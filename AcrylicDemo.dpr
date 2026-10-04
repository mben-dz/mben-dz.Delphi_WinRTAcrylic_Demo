program AcrylicDemo;

{$APPTYPE GUI}

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.SysUtils,
  Acrylic.NoiseData in 'Acrylic.NoiseData.pas',
  Acrylic.Interop in 'Acrylic.Interop.pas',
  Acrylic.Effects in 'Acrylic.Effects.pas',
  Acrylic.Graphics in 'Acrylic.Graphics.pas',
  Acrylic.Window in 'Acrylic.Window.pas',
  Acrylic.Host in 'Acrylic.Host.pas';

// winit makes the process DPI aware; do the same (looked up dynamically: older Windows lacks it)
procedure EnableDpiAwareness;
type
  TSetCtx = function(Value: THandle): BOOL; stdcall;
const
  DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = THandle(-4);
var
  Fn: TSetCtx;
begin
  Fn := GetProcAddress(GetModuleHandle('user32.dll'), 'SetProcessDpiAwarenessContext');
  if Assigned(Fn) then
    Fn(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
end;

var
  Demo: TAcrylicDemo;
begin
  EnableDpiAwareness;

  CoInitializeEx(nil, COINIT_MULTITHREADED);
  try
    Demo := TAcrylicDemo.Create;
    try
      Demo.Run;
    finally
      Demo.Free;
    end;
  except
    on E: Exception do
      MessageBox(0, PChar(E.ClassName + ': ' + E.Message), 'AcrylicDemo', MB_ICONERROR or MB_OK);
  end;
end.
