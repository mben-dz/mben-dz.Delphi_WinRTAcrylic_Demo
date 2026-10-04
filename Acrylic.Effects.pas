unit Acrylic.Effects;

{
  Replacement for the Win2D effect classes used in main.rs
  (GaussianBlurEffect, SaturationEffect, BlendEffect, CompositeEffect,
   ColorSourceEffect, OpacityEffect, BorderEffect).

  Windows.UI.Composition accepts any object that implements
    IGraphicsEffect + IGraphicsEffectSource + IGraphicsEffectD2D1Interop.
  Each node below is one D2D1 effect: its CLSID, its properties in D2D
  property-index order (0..N-1, contiguous - Composition applies value i to
  D2D property i) and its sources.
}

interface

uses
  Winapi.Windows,
  System.SysUtils,
  Winapi.WinRT,
  System.Win.WinRT,
  Winapi.Foundation,
  Winapi.CommonTypes,
  Winapi.UI.Composition,
  Acrylic.Interop;

type
  TEffectPropKind = (pkSingle, pkUInt32, pkVector4);

  TEffectProp = record
    Kind: TEffectPropKind;
    F: array[0..3] of Single;
    U: Cardinal;
    class function Float(AValue: Single): TEffectProp; static;
    class function UInt(AValue: Cardinal): TEffectProp; static;
    class function Vec4(R, G, B, A: Single): TEffectProp; static;
  end;

  TD2DEffectNode = class(TInspectableObject,
    Effects_IGraphicsEffect, Effects_IGraphicsEffectSource, IGraphicsEffectD2D1Interop)
  private
    FClsid: TGUID;
    FName: string;
    FProps: TArray<TEffectProp>;
    FSources: TArray<Effects_IGraphicsEffectSource>;
  public
    constructor Create(const AClsid: TGUID; const AProps: array of TEffectProp;
      const ASources: array of Effects_IGraphicsEffectSource);
    // Effects_IGraphicsEffect
    function get_Name: HSTRING; safecall;
    procedure put_Name(AName: HSTRING); safecall;
    // IGraphicsEffectD2D1Interop
    function GetEffectId(out id: TGUID): HRESULT; stdcall;
    function GetNamedPropertyMapping(name: PWideChar; out index: Cardinal;
      out mapping: Integer): HRESULT; stdcall;
    function GetPropertyCount(out count: Cardinal): HRESULT; stdcall;
    function GetProperty(index: Cardinal; out value: IInspectable): HRESULT; stdcall;
    function GetSource(index: Cardinal; out source: Effects_IGraphicsEffectSource): HRESULT; stdcall;
    function GetSourceCount(out count: Cardinal): HRESULT; stdcall;
  end;

  // Builders - same names/roles as the Win2D classes in main.rs
  TEffects = class
  public
    // CompositionEffectSourceParameter("Backdrop") / ("Noise")
    class function SourceParameter(const AName: string): Effects_IGraphicsEffectSource; static;
    class function GaussianBlur(const ASource: Effects_IGraphicsEffectSource;
      ABlurAmount: Single; AHardBorder: Boolean): Effects_IGraphicsEffectSource; static;
    class function Saturation(const ASource: Effects_IGraphicsEffectSource;
      ASaturation: Single): Effects_IGraphicsEffectSource; static;
    class function Blend(AMode: Cardinal; const ABackground, AForeground: Effects_IGraphicsEffectSource): Effects_IGraphicsEffectSource; static;
    class function Composite(AMode: Cardinal; const ASources: array of Effects_IGraphicsEffectSource): Effects_IGraphicsEffectSource; static;
    // ColorSourceEffect - note Color{A,R,G,B} order like Windows.UI.Color
    class function ColorSource(A, R, G, B: Byte): Effects_IGraphicsEffectSource; static;
    class function Opacity(const ASource: Effects_IGraphicsEffectSource; AOpacity: Single): Effects_IGraphicsEffectSource; static;
    class function Border(const ASource: Effects_IGraphicsEffectSource; AEdgeX, AEdgeY: Cardinal): Effects_IGraphicsEffectSource; static;
  end;

implementation

const
  E_BOUNDS_ = HRESULT($8000000B);

{ TEffectProp }

class function TEffectProp.Float(AValue: Single): TEffectProp;
begin
  Result := Default(TEffectProp);
  Result.Kind := pkSingle;
  Result.F[0] := AValue;
end;

class function TEffectProp.UInt(AValue: Cardinal): TEffectProp;
begin
  Result := Default(TEffectProp);
  Result.Kind := pkUInt32;
  Result.U := AValue;
end;

class function TEffectProp.Vec4(R, G, B, A: Single): TEffectProp;
begin
  Result := Default(TEffectProp);
  Result.Kind := pkVector4;
  Result.F[0] := R;
  Result.F[1] := G;
  Result.F[2] := B;
  Result.F[3] := A;
end;

{ TD2DEffectNode }

constructor TD2DEffectNode.Create(const AClsid: TGUID; const AProps: array of TEffectProp;
  const ASources: array of Effects_IGraphicsEffectSource);
var
  I: Integer;
begin
  inherited Create;
  FClsid := AClsid;
  SetLength(FProps, Length(AProps));
  for I := 0 to High(AProps) do
    FProps[I] := AProps[I];
  SetLength(FSources, Length(ASources));
  for I := 0 to High(ASources) do
    FSources[I] := ASources[I];
end;

function TD2DEffectNode.get_Name: HSTRING;
begin
  if Failed(WindowsCreateString(PChar(FName), Length(FName), Result)) then
    Result := 0;
end;

procedure TD2DEffectNode.put_Name(AName: HSTRING);
begin
  FName := string(WindowsGetStringRawBuffer(AName, nil));
end;

function TD2DEffectNode.GetEffectId(out id: TGUID): HRESULT;
begin
  id := FClsid;
  Result := S_OK;
end;

function TD2DEffectNode.GetNamedPropertyMapping(name: PWideChar; out index: Cardinal;
  out mapping: Integer): HRESULT;
begin
  // No animatable (named) properties in this demo
  index := 0;
  mapping := 0;
  Result := E_INVALIDARG;
end;

function TD2DEffectNode.GetPropertyCount(out count: Cardinal): HRESULT;
begin
  count := Length(FProps);
  Result := S_OK;
end;

function TD2DEffectNode.GetProperty(index: Cardinal; out value: IInspectable): HRESULT;
begin
  value := nil;
  if index >= Cardinal(Length(FProps)) then
    Exit(E_BOUNDS_);
  try
    case FProps[index].Kind of
      pkSingle:  value := TPropertyValue.CreateSingle(FProps[index].F[0]);
      pkUInt32:  value := TPropertyValue.CreateUInt32(FProps[index].U);
      pkVector4: value := TPropertyValue.CreateSingleArray(4, @FProps[index].F[0]);
    end;
    Result := S_OK;
  except
    Result := E_FAIL;
  end;
end;

function TD2DEffectNode.GetSource(index: Cardinal; out source: Effects_IGraphicsEffectSource): HRESULT;
begin
  source := nil;
  if index >= Cardinal(Length(FSources)) then
    Exit(E_BOUNDS_);
  source := FSources[index];
  Result := S_OK;
end;

function TD2DEffectNode.GetSourceCount(out count: Cardinal): HRESULT;
begin
  count := Length(FSources);
  Result := S_OK;
end;

{ TEffects }

class function TEffects.SourceParameter(const AName: string): Effects_IGraphicsEffectSource;
var
  P: ICompositionEffectSourceParameter;
begin
  P := TCompositionEffectSourceParameter.Create(TWindowsString(AName));
  Result := P as Effects_IGraphicsEffectSource;
end;

class function TEffects.GaussianBlur(const ASource: Effects_IGraphicsEffectSource;
  ABlurAmount: Single; AHardBorder: Boolean): Effects_IGraphicsEffectSource;
var
  Border: Cardinal;
begin
  if AHardBorder then Border := D2D1_BORDER_MODE_HARD else Border := D2D1_BORDER_MODE_SOFT;
  // D2D1_GAUSSIANBLUR_PROP_STANDARD_DEVIATION / OPTIMIZATION / BORDER_MODE
  Result := TD2DEffectNode.Create(CLSID_D2D1GaussianBlur,
    [TEffectProp.Float(ABlurAmount),
     TEffectProp.UInt(D2D1_GAUSSIANBLUR_OPTIMIZATION_BALANCED),
     TEffectProp.UInt(Border)],
    [ASource]);
end;

class function TEffects.Saturation(const ASource: Effects_IGraphicsEffectSource;
  ASaturation: Single): Effects_IGraphicsEffectSource;
begin
  Result := TD2DEffectNode.Create(CLSID_D2D1Saturation,
    [TEffectProp.Float(ASaturation)], [ASource]);
end;

class function TEffects.Blend(AMode: Cardinal;
  const ABackground, AForeground: Effects_IGraphicsEffectSource): Effects_IGraphicsEffectSource;
begin
  // D2D1 Blend: input 0 = background (destination), input 1 = foreground (source)
  Result := TD2DEffectNode.Create(CLSID_D2D1Blend,
    [TEffectProp.UInt(AMode)], [ABackground, AForeground]);
end;

class function TEffects.Composite(AMode: Cardinal;
  const ASources: array of Effects_IGraphicsEffectSource): Effects_IGraphicsEffectSource;
begin
  Result := TD2DEffectNode.Create(CLSID_D2D1Composite,
    [TEffectProp.UInt(AMode)], ASources);
end;

class function TEffects.ColorSource(A, R, G, B: Byte): Effects_IGraphicsEffectSource;
begin
  Result := TD2DEffectNode.Create(CLSID_D2D1Flood,
    [TEffectProp.Vec4(R / 255, G / 255, B / 255, A / 255)], []);
end;

class function TEffects.Opacity(const ASource: Effects_IGraphicsEffectSource;
  AOpacity: Single): Effects_IGraphicsEffectSource;
begin
  Result := TD2DEffectNode.Create(CLSID_D2D1Opacity,
    [TEffectProp.Float(AOpacity)], [ASource]);
end;

class function TEffects.Border(const ASource: Effects_IGraphicsEffectSource;
  AEdgeX, AEdgeY: Cardinal): Effects_IGraphicsEffectSource;
begin
  Result := TD2DEffectNode.Create(CLSID_D2D1Border,
    [TEffectProp.UInt(AEdgeX), TEffectProp.UInt(AEdgeY)], [ASource]);
end;

end.
