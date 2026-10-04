## AcrylicDemo — rust-acrylic-demo in Delphi (WinRT, no Win2D)

Port of https://github.com/thisKai/rust-acrylic-demo using the Delphi WinRT units (`winrt.zip`).

## Snapshot:
![](https://github.com/mben-dz/mben-dz.Delphi_WinRTAcrylic_Demo/blob/main/snapshot.png)

| Rust file            | Delphi unit            |
|----------------------|------------------------|
| `interop.rs`         | `Acrylic.Interop`      |
| `window_target.rs`   | `Acrylic.Interop` (`ICompositorDesktopInterop`) + `Acrylic.Host` |
| `window_subclass.rs` | `Acrylic.Window`       |
| `main.rs` effect graph | `Acrylic.Effects` + `Acrylic.Host.BuildAcrylicEffect` |
| `main.rs` Win2D noise  | `Acrylic.Graphics` + `Acrylic.NoiseData` |
| `main.rs` rest       | `Acrylic.Host`         |

Add the winrt folder to the project search path (Winapi.UI.Composition, Winapi.Foundation,
Winapi.CommonTypes, Winapi.SystemRT, Winapi.Storage.Streams are needed).
Target: Win64 or Win32, Windows 10 1803+.

## Video:
![Click Here](https://youtu.be/jc3oSnCaNfo)

## What is different from the Rust version
* **Win2D is gone.** The Rust code uses Win2D (`win2d_uwp`) for the effect classes, `CanvasDevice`
  and `CanvasBitmap`. Your winrt units have none of that, so:
  * the effect classes are replaced by `TD2DEffectNode` (implements `IGraphicsEffect`,
    `IGraphicsEffectSource` and `IGraphicsEffectD2D1Interop` directly on the D2D1 effect CLSIDs);
  * `CanvasDevice`/`CanvasBitmap` are replaced by D3D11 + D2D device + WIC (PNG decode) writing into
    the composition drawing surface.
* `noise.png` is embedded as a byte array (`Acrylic.NoiseData`), like `include_bytes!`.
* winit is replaced by a plain Win32 window + message loop (no VCL, so nothing paints over the surface).
