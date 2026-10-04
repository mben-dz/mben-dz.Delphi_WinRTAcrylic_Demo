unit Acrylic.Host;

{
  Port of main.rs.  Same order of operations:

    1. DispatcherQueueController for the current thread
    2. window (hidden, no redirection bitmap) -> DWM frame handling -> show
    3. Compositor + DesktopWindowTarget
    4. root SpriteVisual with a 1px top inset clip
    5. acrylic effect graph
    6. noise surface + surface brush
    7. effect factory -> effect brush, bind "Backdrop" and "Noise"
    8. root.Brush / RelativeSizeAdjustment(1,1) / target.Root
    9. message loop

  Every WinRT object that must stay alive (controller, compositor, target, visuals,
  graphics device) is held in a field.
}

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  Winapi.ActiveX,
  System.Win.ComObj,
  System.SysUtils,
  Winapi.WinRT,
  System.Win.WinRT,
  Winapi.CommonTypes,
  Winapi.SystemRT,
  Winapi.UI.Composition,
  Acrylic.Interop,
  Acrylic.Effects,
  Acrylic.Graphics,
  Acrylic.NoiseData,
  Acrylic.Window;

type
  TAcrylicDemo = class
  private
    FController: IDispatcherQueueController;
    FWindow: HWND;
    FCompositor: ICompositor;
    FTarget: ICompositionTarget;
    FRoot: ISpriteVisual;
    FGraphics: TCompositionGraphics;
    FNoiseSurface: ICompositionDrawingSurface;
    FEffectBrush: ICompositionEffectBrush;
    function BuildAcrylicEffect: Effects_IGraphicsEffectSource;
    procedure Build;
  public
    destructor Destroy; override;
    procedure Run;
  end;

implementation

{ TAcrylicDemo }

destructor TAcrylicDemo.Destroy;
begin
  FEffectBrush := nil;
  FNoiseSurface := nil;
  FreeAndNil(FGraphics);
  FRoot := nil;
  FTarget := nil;
  FCompositor := nil;
  FController := nil;
  inherited;
end;

// The big `acrylic_effect` block of main.rs, read inside-out:
//
//   Blend(Overlay)
//     Background = Composite(SourceOver)
//        [0] Blend(Exclusion)
//              Background = Saturation(2)  <-  GaussianBlur(30, Hard)  <-  "Backdrop"
//              Foreground = ColorSource(A=26,  24,24,24)
//        [1] ColorSource(A=128, 24,24,24)
//     Foreground = Opacity(0.02)  <-  Border(Wrap, Wrap)  <-  "Noise"
function TAcrylicDemo.BuildAcrylicEffect: Effects_IGraphicsEffectSource;
var
  Backdrop, Noise: Effects_IGraphicsEffectSource;
  Tint, Luminosity, BaseLayer, NoiseLayer: Effects_IGraphicsEffectSource;
begin
  Backdrop := TEffects.SourceParameter('Backdrop');
  Noise := TEffects.SourceParameter('Noise');

  Tint := TEffects.Blend(D2D1_BLEND_MODE_EXCLUSION,
    TEffects.Saturation(TEffects.GaussianBlur(Backdrop, 30, True), 2),
    TEffects.ColorSource(26, 24, 24, 24));

  Luminosity := TEffects.ColorSource(128, 24, 24, 24);

  BaseLayer := TEffects.Composite(D2D1_COMPOSITE_MODE_SOURCE_OVER, [Tint, Luminosity]);

  NoiseLayer := TEffects.Opacity(
    TEffects.Border(Noise, D2D1_BORDER_EDGE_MODE_WRAP, D2D1_BORDER_EDGE_MODE_WRAP),
    0.02);

  Result := TEffects.Blend(D2D1_BLEND_MODE_OVERLAY, BaseLayer, NoiseLayer);
end;

procedure TAcrylicDemo.Build;
var
  Interop: ICompositorDesktopInterop;
  TargetUnk: IUnknown;
  Visual: IVisual;
  Clip: IInsetClip;
  Factory: ICompositionEffectFactory;
  NoiseBrush: ICompositionSurfaceBrush;
  BackdropBrush: ICompositionBackdropBrush;
  Size1: Numerics_Vector2;
begin
  // 1. DispatcherQueue for this thread (must exist before the Compositor)
  FController := CreateDispatcherQueueControllerForCurrentThread;

  // 2. window: created hidden, DWM logic lives in its WndProc, then shown
  FWindow := CreateAcrylicWindow('Acrylic (Delphi + WinRT)', 900, 700);
  ShowWindow(FWindow, SW_SHOW);

  // 3. compositor + desktop window target (window_target.rs)
  FCompositor := TCompositor.Create;
  Interop := FCompositor as ICompositorDesktopInterop;
  OleCheck(Interop.CreateDesktopWindowTarget(FWindow, False, TargetUnk));
  FTarget := TargetUnk as ICompositionTarget;

  // 4. root visual with 1px top inset clip
  FRoot := FCompositor.CreateSpriteVisual;
  Visual := FRoot as IVisual;
  Clip := FCompositor.CreateInsetClip;
  Clip.TopInset := 1;
  Visual.Clip := Clip as ICompositionClip;

  // 6. noise surface (+ brush: Stretch None, aligned top-left so the Border effect tiles it)
  FGraphics := TCompositionGraphics.Create(FCompositor);
  FNoiseSurface := FGraphics.CreateSurfaceFromPng(@NoisePng[0], NoisePngSize);
  NoiseBrush := FCompositor.CreateSurfaceBrush(FNoiseSurface as ICompositionSurface);
  NoiseBrush.Stretch := CompositionStretch.None;
  NoiseBrush.HorizontalAlignmentRatio := 0;
  NoiseBrush.VerticalAlignmentRatio := 0;

  // 5 + 7. effect graph -> factory -> brush
  Factory := FCompositor.CreateEffectFactory(BuildAcrylicEffect as Effects_IGraphicsEffect);
  // Success or Pending are fine; anything else means the effect graph was rejected
  if (Factory.LoadStatus <> CompositionEffectFactoryLoadStatus.Success) and
     (Factory.LoadStatus <> CompositionEffectFactoryLoadStatus.Pending) then
    raise Exception.CreateFmt('Effect factory load status = %d (HRESULT 0x%.8x)',
      [Ord(Factory.LoadStatus), Cardinal(Factory.ExtendedError)]);
  FEffectBrush := Factory.CreateBrush;

  BackdropBrush := (FCompositor as ICompositor2).CreateBackdropBrush;
  FEffectBrush.SetSourceParameter(TWindowsString('Backdrop'), BackdropBrush as ICompositionBrush);
  FEffectBrush.SetSourceParameter(TWindowsString('Noise'), NoiseBrush as ICompositionBrush);

  // 8. attach
  FRoot.Brush := FEffectBrush as ICompositionBrush;
  Size1.X := 1;
  Size1.Y := 1;
  (Visual as IVisual2).RelativeSizeAdjustment := Size1;
  FTarget.Root := Visual;
end;

procedure TAcrylicDemo.Run;
var
  Msg: TMsg;
begin
  Build;
  // 9. event loop (also pumps the DispatcherQueue of this thread)
  while GetMessage(Msg, 0, 0, 0) do
  begin
    TranslateMessage(Msg);
    DispatchMessage(Msg);
  end;
end;

end.
