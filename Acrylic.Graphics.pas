unit Acrylic.Graphics;

{
  Replacement for the Win2D part of main.rs:

    CanvasDevice::GetSharedDevice()
    CanvasComposition::CreateCompositionGraphicsDevice(...)
    composition_graphics_device.CreateDrawingSurface(256x256, B8G8R8A8, Premultiplied)
    CanvasBitmap::LoadAsyncFromStream(png) + DrawImageAtOrigin

  Without Win2D:  D3D11 device -> D2D device -> ICompositorInterop.CreateGraphicsDevice,
  PNG decoded with WIC to premultiplied BGRA, copied into the drawing surface's
  texture between BeginDraw / EndDraw.
}

interface

uses
  Winapi.Windows,
  Winapi.ActiveX,
  System.SysUtils,
  System.Types,
  Winapi.DXGI,
  Winapi.D3D11,
  Winapi.D3DCommon,
  Winapi.D2D1,
  Winapi.Wincodec,
  Winapi.CommonTypes,
  Winapi.UI.Composition,
  Winapi.D2DMissing,
  Acrylic.Interop;

const
  IID_ID2D1Device: TGUID = '{47dd575d-ac05-4cdd-8049-9b02cd16f44c}';

type

  TCompositionGraphics = class
  private
    FD3DDevice: ID3D11Device;
    FD3DContext: ID3D11DeviceContext;
    FD2DDevice: ID2D1Device;
    FGraphicsDevice: ICompositionGraphicsDevice;
    procedure CreateDevices;
  public
    constructor Create(const ACompositor: ICompositor);
    // Decode a PNG held in memory and return a Composition surface containing it.
    function CreateSurfaceFromPng(AData: Pointer; ASize: Integer): ICompositionDrawingSurface;
  end;

implementation
uses
  System.Win.ComObj;

function D2D1CreateDevice(dxgiDevice: IDXGIDevice; creationProperties: Pointer;
  out d2dDevice: ID2D1Device): HRESULT; stdcall; external 'd2d1.dll' name 'D2D1CreateDevice' delayed;


{ TCompositionGraphics }

constructor TCompositionGraphics.Create(const ACompositor: ICompositor);
begin
  inherited Create;
  CreateDevices;
  FGraphicsDevice := (ACompositor as ICompositorInterop).CreateGraphicsDevice(FD2DDevice);
end;

procedure TCompositionGraphics.CreateDevices;
var
  FeatureLevel: TD3D_FEATURE_LEVEL;
  DxgiDevice: IDXGIDevice;
  HR: HRESULT;
  DriverType: TD3D_DRIVER_TYPE;
begin
  HR := 0;

  // Hardware first, WARP as fallback (BGRA support is required for D2D / Composition)
  for DriverType in [D3D_DRIVER_TYPE_HARDWARE, D3D_DRIVER_TYPE_WARP] do
  begin
    HR := D3D11CreateDevice(nil, DriverType, 0, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
      nil, 0, D3D11_SDK_VERSION, FD3DDevice, FeatureLevel, FD3DContext);
    if Succeeded(HR) then
      Break;
  end;
  if FD3DDevice = nil then
    raise Exception.CreateFmt('D3D11CreateDevice failed (0x%.8x)', [HR]);

  DxgiDevice := FD3DDevice as IDXGIDevice;
  HR := D2D1CreateDevice(DxgiDevice, nil, FD2DDevice);
  if Failed(HR) then
    raise Exception.CreateFmt('D2D1CreateDevice failed (0x%.8x)', [HR]);
end;

function TCompositionGraphics.CreateSurfaceFromPng(AData: Pointer; ASize: Integer): ICompositionDrawingSurface;
var
  Factory: IWICImagingFactory;
  Stream: IWICStream;
  Decoder: IWICBitmapDecoder;
  Frame: IWICBitmapFrameDecode;
  Converter: IWICFormatConverter;
  W, H: UINT;
  Pixels: TBytes;
  SurfaceSize: TSizeF;
  Interop: ICompositionDrawingSurfaceInterop;
  UpdateObj: Pointer;
  Texture: ID3D11Texture2D;
  Offset: TPoint;
  Box: TD3D11_BOX;
begin
  // --- WIC: PNG -> premultiplied BGRA (what CanvasBitmap gives DrawImageAtOrigin) ---
  OleCheck(CoCreateInstance(CLSID_WICImagingFactory, nil, CLSCTX_INPROC_SERVER,
    IWICImagingFactory, Factory));
  OleCheck(Factory.CreateStream(Stream));
  OleCheck(Stream.InitializeFromMemory(AData, ASize));
  OleCheck(Factory.CreateDecoderFromStream(Stream, TGUID.Empty, WICDecodeMetadataCacheOnDemand, Decoder));
  OleCheck(Decoder.GetFrame(0, Frame));
  OleCheck(Factory.CreateFormatConverter(Converter));
  OleCheck(Converter.Initialize(Frame, GUID_WICPixelFormat32bppPBGRA,
    WICBitmapDitherTypeNone, nil, 0.0, WICBitmapPaletteTypeCustom));
  OleCheck(Converter.GetSize(W, H));
  SetLength(Pixels, W * H * 4);
  OleCheck(Converter.CopyPixels(nil, W * 4, Length(Pixels), @Pixels[0]));

  // --- Composition surface: B8G8R8A8UIntNormalized, Premultiplied (same as main.rs) ---
  SurfaceSize.Width := W;
  SurfaceSize.Height := H;
  Result := FGraphicsDevice.CreateDrawingSurface(SurfaceSize,
    DirectX_DirectXPixelFormat.B8G8R8A8UIntNormalized,
    DirectX_DirectXAlphaMode.Premultiplied);

  // --- "ds.Clear(Transparent); ds.DrawImageAtOrigin(bitmap)" ---
  // Writing every pixel of the surface makes the Clear redundant.
  Interop := Result as ICompositionDrawingSurfaceInterop;
  OleCheck(Interop.BeginDraw(nil, ID3D11Texture2D, UpdateObj, Offset));
  try
    Pointer(Texture) := UpdateObj;   // BeginDraw returned an owned reference
    Box.left := Offset.X;
    Box.top := Offset.Y;
    Box.front := 0;
    Box.right := Offset.X + Integer(W);
    Box.bottom := Offset.Y + Integer(H);
    Box.back := 1;
    FD3DContext.UpdateSubresource(Texture, 0, @Box, @Pixels[0], W * 4, 0);
  finally
    Texture := nil;
    OleCheck(Interop.EndDraw);
  end;
end;

end.
