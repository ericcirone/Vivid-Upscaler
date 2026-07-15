# Vivid Upscaler

Vivid is a native Mac photo upscaler with an optional Terminal command.
The app bundles the CLI, so both surfaces execute the same models and processing pipeline.

The five modes are:

| Mode | Model | Backend | Minimum RAM | Recommended RAM | Large Image RAM | Default Tiling | Intended use |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| `fast` | `mlx-community/Real-ESRGAN-general-x4v3` | MLX | 8 GB | 16 GB | 24 GB | `auto` | Quickest option: a compact native FP16 MLX upscaler for Apple Silicon. |
| `normal` | `mlx-community/Real-ESRGAN-x4plus` | MLX | 16 GB | 16 GB | 24 GB | `auto` | Main quality and speed balance with a stronger conventional single-pass upscaler. |
| `normal-hq` | `4xNomosWebPhoto_esrgan` | PyTorch MPS via Spandrel | 16 GB | 16 GB | 24 GB | `auto` | Fast photographic restoration for compression, lens blur, noise, and Web/JPEG sources. |
| `advanced` | `SeedVR2 3B 8-bit` | Native MLX | 16 GB | 24 GB | 32 GB | `auto` | Difficult restoration jobs where a longer wait is acceptable. |
| `maximum` | `SeedVR2 3B source precision` | Native MLX | 24 GB | 32 GB | 48 GB | `auto` | Highest-quality and slowest option. |

The command name is:

```bash
vvd
```

## Native Mac app

```bash
./script/build_and_run.sh
```

The built app contains the `vvd` implementation and works without installing a
separate command first. The first model installation also prepares the shared
processing runtime under `~/.local/share/vivid`.

To use the exact same bundled CLI in Terminal, choose **Vivid Upscaler > Install
Command Line Tool…**. This creates `~/.local/bin/vvd` as a link to the copy in
the app bundle.

## Standalone CLI development install

For a repository-only CLI installation without the app:

```bash
./install.sh
```

Run the installer again after pulling changes so the standalone `vvd` command
stays in sync with this repository.

The app lets you drop in one photo, choose the mode, a scale or target
resolution, and an output format. Output is written beside the input using a
predictable name:

```text
portrait-vivid-upscale-2x.jpg
portrait-vivid-upscale-2048px.webp
```

On first launch, the app checks the CLI model inventory and guides you through
downloading one or more models. Normal is the recommended starting point.

For fish, if `~/.local/bin` is not already on your path:

```fish
set -Ux fish_user_paths ~/.local/bin $fish_user_paths
```

## Use

```bash
vvd input.jpg output.jpg --scale 2
vvd input.jpg output.jpg --mode fast --scale 2
vvd input.jpg output.jpg --mode normal --scale 2
vvd input.jpg output.jpg --mode advanced --scale 2
vvd models status
vvd models status --json
vvd models install normal
vvd models delete normal
```

Supported GUI output choices are the input format, PNG, JPG, JPEG XL, and WebP.
JPEG XL encoding uses the reference `libjxl` implementation through `pyjpegxl`;
`pillow-jxl-plugin` provides JPEG XL input decoding.
Every pipeline uses the same final encoder, which preserves EXIF, XMP, DPI,
comments where the destination supports them, and the source ICC color profile
for PNG, JPG, JPEG XL, and WebP. Orientation is normalized after the source
pixels are physically rotated. Vivid refuses color-managed JPEG XL output when
`cjxl` is unavailable instead of silently dropping or replacing the profile;
install it with `brew install jpeg-xl`.

## Modes

### Fast

Uses `mlx-community/Real-ESRGAN-general-x4v3` through native MLX for the quickest photo upscaling.

### Normal and Normal HQ

Normal uses `mlx-community/Real-ESRGAN-x4plus` through native MLX and is the default. Normal HQ uses `4xNomosWebPhoto_esrgan` through PyTorch MPS and Spandrel for photographic restoration.

### Advanced and Maximum

Both modes use MFLUX's native MLX SeedVR2 implementation and are locked to the 3B model. Advanced quantizes it to 8-bit at load time. Maximum keeps the source precision. Vivid never selects or exposes SeedVR2 7B.

## Tiling

The wrapper supports:

```bash
--tile auto
--tile on
--tile off
```

Default is `auto`.

- In **fast** and **normal**, auto uses Real-ESRGAN MLX tiling for larger outputs. Fast forces tiling on 8 GB systems.
- In **normal-hq**, auto uses Spandrel/MPS tiling for larger outputs.
- In **advanced** and **maximum**, `auto` and `on` enable MFLUX low-RAM mode so the transformer is released before VAE decode.
- Vivid keeps PyTorch's Metal memory guard enabled for Normal HQ and reserves CPU headroom. Advanced users can override the PyTorch defaults with `PYTORCH_MPS_HIGH_WATERMARK_RATIO`, `PYTORCH_MPS_LOW_WATERMARK_RATIO`, or `VIVID_CPU_THREADS`.
- `off` forces the faster path when memory allows.
- `on` forces the safer lower memory path.

## Install locations

By default Vivid installs to:

```text
~/.local/bin/vvd
~/.local/share/vivid/venv
```

## Model locations

Downloaded model weights are kept in fixed locations:

```text
~/.local/share/vivid/models/SEEDVR2
~/.local/share/vivid/models/mlx/Real-ESRGAN-general-x4v3
~/.local/share/vivid/models/mlx/Real-ESRGAN-x4plus
~/.local/share/vivid/models/nomos-webphoto-esrgan
```

## Output locations

A bare output filename is saved in the same directory as the input image:

```bash
vvd /Users/me/Photos/input.jpg enhanced.jpg --scale 2
# Saves /Users/me/Photos/enhanced.jpg
```

Include a slash to choose a location explicitly:

```bash
vvd /Users/me/Photos/input.jpg ./enhanced.jpg --scale 2
# Saves ./enhanced.jpg in the current directory
```

When no output is supplied, Vivid writes an `_upscaled` file beside the input.

## Notes

- The default mode is `normal`.
- SeedVR2 is always the 3B model; 7B is intentionally unsupported.
- `--scale 2` targets twice the source width and height. `--multiplier 2` is an alias.
- The CLI currently accepts a single image.
- `--denoise-strength` applies only to `fast` mode.
