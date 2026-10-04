unit Acrylic.Interop;

{
  Win32 / COM interop pieces that the Embarcadero winrt units do NOT declare.
  Port of:  interop.rs (dispatcher queue)  +  window_target.rs (ICompositorDesktopInterop)
  plus the two interfaces Win2D normally hides from you:
    ICompositionDrawingSurfaceInterop   (draw into a composition surface)
    IGraphicsEffectD2D1Interop          (lets Windows.UI.Composition build a D2D effect graph)
}

interface

uses
  Winapi.Windows,
  Winapi.WinRT,
  Winapi.CommonTypes,
  Winapi.SystemRT;

// ---------------------------------------------------------------------------
// CreateDispatcherQueueController (CoreMessaging.dll)
// ---------------------------------------------------------------------------
type
  TDispatcherQueueOptions = record
    dwSize: DWORD;
    threadType: Integer;
    apartmentType: Integer;
  end;

const
  DQTYPE_THREAD_DEDICATED = 1;
  DQTYPE_THREAD_CURRENT   = 2;
  DQTAT_COM_NONE          = 0;
  DQTAT_COM_ASTA          = 1;
  DQTAT_COM_STA           = 2;

function CreateDispatcherQueueController(options: TDispatcherQueueOptions;
  out controller: IDispatcherQueueController): HRESULT; stdcall;
  external 'CoreMessaging.dll';

function CreateDispatcherQueueControllerForCurrentThread: IDispatcherQueueController;

// ---------------------------------------------------------------------------
// window_target.rs  -  windows.ui.composition.interop.h
// ---------------------------------------------------------------------------
type
  ICompositorDesktopInterop = interface(IUnknown)
    ['{29E691FA-4567-4DCA-B319-D0F207EB6807}']
    // result is a Windows.UI.Composition.Desktop.DesktopWindowTarget;
    // QueryInterface it for ICompositionTarget to get at .Root
    function CreateDesktopWindowTarget(hwndTarget: HWND; isTopmost: BOOL;
      out result: IUnknown): HRESULT; stdcall;
    function EnsureOnThread(threadId: DWORD): HRESULT; stdcall;
  end;

  ICompositionDrawingSurfaceInterop = interface(IUnknown)
    ['{FD04E6E3-FE0C-4C3C-AB19-A07601A576EE}']
    function BeginDraw(updateRect: PRect; const iid: TGUID;
      out updateObject: Pointer; out updateOffset: TPoint): HRESULT; stdcall;
    function EndDraw: HRESULT; stdcall;
    function Resize(sizePixels: TSize): HRESULT; stdcall;
    function Scroll(scrollRect: PRect; clipRect: PRect; offsetX, offsetY: Integer): HRESULT; stdcall;
    function ResumeDraw: HRESULT; stdcall;
    function SuspendDraw: HRESULT; stdcall;
  end;

  // windows.graphics.effects.interop.h
  // Every effect object handed to Compositor.CreateEffectFactory must implement this.
  IGraphicsEffectD2D1Interop = interface(IUnknown)
    ['{2FC57384-A068-44D7-A331-30982FCF7177}']
    function GetEffectId(out id: TGUID): HRESULT; stdcall;
    function GetNamedPropertyMapping(name: PWideChar; out index: Cardinal;
      out mapping: Integer): HRESULT; stdcall;
    function GetPropertyCount(out count: Cardinal): HRESULT; stdcall;
    function GetProperty(index: Cardinal; out value: IInspectable): HRESULT; stdcall;
    function GetSource(index: Cardinal; out source: Effects_IGraphicsEffectSource): HRESULT; stdcall;
    function GetSourceCount(out count: Cardinal): HRESULT; stdcall;
  end;

const
  // d2d1effects.h
  CLSID_D2D1GaussianBlur: TGUID = '{1FEB6D69-2FE6-4AC9-8C58-1D7F93E7A6A5}';
  CLSID_D2D1Saturation:   TGUID = '{5CB2D9CF-327D-459F-A0CE-40C0B2086BF7}';
  CLSID_D2D1Blend:        TGUID = '{81C5B77B-13F8-4CDD-AD20-C890547AC65D}';
  CLSID_D2D1Composite:    TGUID = '{48FC9F51-F6AC-48F1-8B58-3B28AC46F76D}';
  CLSID_D2D1Flood:        TGUID = '{61C23C20-AE69-4D8E-94CF-50078DF638F2}';
  CLSID_D2D1Opacity:      TGUID = '{811D79A4-DE28-4454-8094-C64685F8BD4C}';
  CLSID_D2D1Border:       TGUID = '{2A2D49C0-4ACF-43C7-8C6A-7C4A27874D27}';

  // D2D1_BLEND_MODE
  D2D1_BLEND_MODE_OVERLAY   = 11;
  D2D1_BLEND_MODE_EXCLUSION = 19;
  // D2D1_COMPOSITE_MODE
  D2D1_COMPOSITE_MODE_SOURCE_OVER = 0;
  // D2D1_BORDER_EDGE_MODE
  D2D1_BORDER_EDGE_MODE_CLAMP  = 0;
  D2D1_BORDER_EDGE_MODE_WRAP   = 1;
  D2D1_BORDER_EDGE_MODE_MIRROR = 2;
  // D2D1_GAUSSIANBLUR_OPTIMIZATION / BORDER_MODE
  D2D1_GAUSSIANBLUR_OPTIMIZATION_BALANCED = 1;
  D2D1_BORDER_MODE_SOFT = 0;
  D2D1_BORDER_MODE_HARD = 1;

implementation

uses
  System.SysUtils;

function CreateDispatcherQueueControllerForCurrentThread: IDispatcherQueueController;
var
  Options: TDispatcherQueueOptions;
begin
  Options.dwSize := SizeOf(Options);
  Options.threadType := DQTYPE_THREAD_CURRENT;
  Options.apartmentType := DQTAT_COM_NONE;
  if Failed(CreateDispatcherQueueController(Options, Result)) then
    raise Exception.Create('CreateDispatcherQueueController failed');
end;

end.
