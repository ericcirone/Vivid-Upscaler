# Vivid Upscaler

[![CI](https://github.com/ericcirone/Vivid-Upscaler/actions/workflows/ci.yml/badge.svg)](https://github.com/ericcirone/Vivid-Upscaler/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Vivid is an open-source, native macOS photo upscaler with an optional Terminal command, `vvd`. The app bundles the CLI, so both interfaces use the same models and processing pipeline.

## Requirements

- An Apple Silicon Mac running macOS 14 Sonoma or newer
- Xcode Command Line Tools with Swift 6 (`xcode-select --install`)
- An internet connection for the first runtime and model download
- At least 8 GB RAM; 16 GB or more is recommended
- Disk space for the Python runtime, dependencies, and any models you install

JPEG XL output requires the reference `cjxl` encoder:

```bash
brew install jpeg-xl
```

## Run the Mac app from source

```bash
git clone https://github.com/ericcirone/Vivid-Upscaler.git
cd Vivid-Upscaler
./script/build_and_run.sh
```

This builds `dist/VividUpscaler.app` and opens it. Other development commands are:

```bash
./script/build_and_run.sh build       # Build the app bundle without opening it
./script/build_and_run.sh --debug     # Build and launch under LLDB
./script/build_and_run.sh --logs      # Build, launch, and stream app logs
./script/build_and_run.sh --verify    # Build, launch, and verify the process starts
```

On first use, the app installs its shared processing runtime under `~/.local/share/vivid` and guides you through downloading one or more models. Normal is the recommended starting point.

To use the app's exact bundled CLI in Terminal, choose **Vivid Upscaler > Install Command Line Tool…**. This creates `~/.local/bin/vvd` as a symbolic link to the command inside the app bundle. Move the app to `/Applications` first if you plan to keep using that link outside development.

## Install and run the CLI from source

For a repository-only CLI installation, clone the repository and run:

```bash
./install.sh
```

The installer adds `vvd` to `~/.local/bin`, installs `uv` if needed, creates a Python 3.12 environment under `~/.local/share/vivid`, and installs the processing dependencies. Run the installer again after pulling changes so the installed command stays in sync with the repository.

If `~/.local/bin` is not already on your `PATH`, add the appropriate line to your shell configuration:

```bash
# zsh: ~/.zshrc   bash: ~/.bashrc
export PATH="$HOME/.local/bin:$PATH"
```

```fish
# fish
set -Ux fish_user_paths ~/.local/bin $fish_user_paths
```

Restart the shell, then confirm the installation:

```bash
vvd --help
vvd models status
```

### CLI examples

```bash
vvd input.jpg                                      # Writes input_upscaled.jpg beside the input
vvd input.jpg output.jpg --scale 2
vvd input.jpg output.png --mode fast --scale 4
vvd input.jpg output.webp --mode normal-hq --resolution 2048
vvd input.jpg output.png --mode normal --deblur deblur-motion --scale 2
vvd portrait.jpg restored.png --mode normal --face-restore --codeformer-preset balanced --scale 2
vvd input.jpg output.jxl --mode advanced --scale 2 --quality 90 --seed 42
vvd input.jpg output.png --mode maximum --tile on
vvd input.jpg output.png --mode maximum --seedvr2-preset softer-detail --seed 123

vvd models status
vvd models status --json
vvd models install normal
vvd models install deblur-motion
vvd models install face-restore
vvd models delete normal
```

Run `vvd --help` for the complete option list. The main options are:

| Option | Description |
| --- | --- |
| `--mode MODE` | `fast`, `normal`, `normal-hq`, `advanced`, `maximum`, or `maximum-experimental`; default is `normal` |
| `--deblur MODE` | Optional `deblur-motion` or `deblur-defocus` Restormer pass before upscaling; default is `none` |
| `--face-restore` | Restore detected faces with CodeFormer after deblur and before upscaling; disabled by default |
| `--codeformer-preset PRESET` | `enhance`, `balanced`, `faithful`, or `custom`; default is `balanced` |
| `--codeformer-fidelity N` | Custom CodeFormer fidelity weight from 0 to 1; default is 0.7 |
| `--scale N` | Multiply both source dimensions by `N` |
| `--resolution N` | Target the short edge in pixels; default is 2048 |
| `--max-resolution N` | Cap the long edge in pixels; default is 4096 |
| `--tile auto\|on\|off` | Control lower-memory processing; default is `auto` |
| `--quality N` | JPG, JPEG XL, or WebP quality from 1 to 100; default is 90 |
| `--denoise-strength N` | Fast-mode denoise balance from 0 to 1; default is 0.5 |
| `--seed N` | Variation seed for `advanced`, `maximum`, and `maximum-experimental`; default is 42 |
| `--seedvr2-preset PRESET` | `faithful`, `high-resolution-cleanup`, `softer-detail`, or `custom`; SeedVR2 modes only; default is `faithful` |
| `--input-noise-scale N` | SeedVR2 input noise from 0 to 1; preset value unless explicitly overridden |
| `--latent-noise-scale N` | SeedVR2 latent noise from 0 to 1; preset value unless explicitly overridden |
| `--color-correction METHOD` | `lab`, `wavelet`, `wavelet_adaptive`, `hsv`, `adain`, or `none`; SeedVR2 modes only |
| `--hypir-preset PRESET` | `natural`, `balanced`, `enhanced`, or `custom`; HYPIR only; default is `balanced` |
| `--hypir-restoration-strength N` | Custom HYPIR generated-detail blend from 0 to 1; requires `custom`; default is 0.70 |
| `--hypir-patch-size N` | Custom HYPIR patch size from 512 through 1024 in increments of 128 |
| `--hypir-patch-stride N` | Custom HYPIR stride from 256 through patch size in increments of 128 |
| `--hypir-prompt TEXT` | Custom HYPIR photographic-result prompt |
| `--no-progress` | Hide wrapper progress messages |

A bare output filename is saved beside the input file. Include a slash, such as `./output.jpg`, to explicitly save relative to the current directory. When no output is supplied, Vivid writes an `_upscaled` file beside the input. The CLI currently processes one image at a time.

## Models and memory

| Mode | Model | Backend | Minimum RAM | Recommended RAM | Large Image RAM | Intended use |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `fast` | `mlx-community/Real-ESRGAN-general-x4v3` | MLX | 8 GB | 16 GB | 24 GB | Quickest general-purpose upscaling |
| `normal` | `mlx-community/Real-ESRGAN-x4plus` | MLX | 16 GB | 16 GB | 24 GB | Main quality and speed balance |
| `normal-hq` | `4xNomosWebPhoto_esrgan` | PyTorch MPS via Spandrel | 16 GB | 16 GB | 24 GB | Photographic restoration for compression, blur, noise, and Web/JPEG sources |
| `advanced` | SeedVR2 3B 8-bit, 80% internal scale | Native MLX | 16 GB | 24 GB | 32 GB | High-quality restoration with a meaningful speed improvement over Maximum |
| `maximum` | SeedVR2 3B source precision | Native MLX | 24 GB | 32 GB | 48 GB | Highest-quality and slowest processing |
| `maximum-experimental` | HYPIR-SD2 | PyTorch MPS, experimental | 24 GB | 32 GB | 48 GB | Maximum-tier opt-in generative restoration with strong detail reconstruction and adjustable texture richness |
| `deblur-motion` | Restormer Motion Deblurring | PyTorch MPS | 16 GB | 24 GB | 32 GB | Camera shake, subject movement, and directional motion blur |
| `deblur-defocus` | Restormer Single-Image Defocus Deblurring | PyTorch MPS | 16 GB | 24 GB | 32 GB | Out-of-focus and lens-related blur |
| `face-restore` | CodeFormer v0.1.0 | PyTorch MPS via Vivid adapter | 8 GB | 16 GB | 24 GB | Detected-face restoration with an adjustable reconstruction/fidelity trade-off |

SeedVR2 is intentionally limited to the 3B model. Advanced quantizes it to 8-bit at load time and processes 80% of the requested width and height before a high-quality Lanczos resize to the exact output dimensions. Maximum keeps the source precision and processes the full requested dimensions.

HYPIR processes the requested output dimensions directly. Its `natural`, `balanced`, and `enhanced` presets use restoration strengths of 0.45, 0.70, and 1.00 while also controlling the photographic prompt and patch overlap; `balanced` is the default. Restoration strength blends source and HYPIR-generated high-frequency detail while retaining the source's low-frequency structure. The `custom` preset accepts an explicit strength, prompt, patch size, and patch stride. Smaller strides increase overlap and processing time. Strength does not reduce inference cost because the full HYPIR result is generated before blending. For compatibility, the generic `--tile` mapping is used only when `--tile` is explicitly supplied without HYPIR preset settings.

Maximum Experimental is an opt-in HYPIR-SD2 path. It may reconstruct plausible detail that was not present in the source, so avoid it for facial identity, text, or documentary-critical work. The official HYPIR implementation documents CUDA rather than Apple Silicon MPS; Vivid's MPS integration remains experimental. HYPIR's official repository also restricts commercial use without separate permission, even though its model repository displays an Apache 2.0 label; review and follow the more restrictive terms before enabling it in a commercial product.

The two Restormer entries and CodeFormer are optional preprocessors, not upscale modes. Choose Motion Blur or Out of Focus in the app; Vivid does not guess when the blur type is uncertain. Processing order is deblur, then face restoration, then the selected upscale mode. Each preprocessor preserves the full image dimensions.

CodeFormer is disabled by default. Its Balanced preset uses a fidelity weight of 0.7; Enhance uses 0.4 for stronger reconstruction, while Faithful uses 0.9 for closer identity preservation. If no eligible face is detected, Vivid leaves the image unchanged before upscaling. Review identity-sensitive details carefully. CodeFormer uses the NTU S-Lab License 1.0, so review its redistribution and commercial-use terms before shipping it in a product.

### Tiling

`--tile auto` is the default. It enables a safer path for larger Real-ESRGAN, Normal HQ, and Restormer jobs and enables MFLUX low-RAM mode for Advanced and Maximum. `--tile on` forces the lower-memory path, while `--tile off` forces the faster path when memory allows. Fast mode automatically forces tiling on 8 GB systems.

Vivid keeps PyTorch's Metal memory guard enabled and reserves CPU headroom. Advanced users can override the defaults with `PYTORCH_MPS_HIGH_WATERMARK_RATIO`, `PYTORCH_MPS_LOW_WATERMARK_RATIO`, or `VIVID_CPU_THREADS`.

## Formats, metadata, and output names

The app supports the input format, PNG, JPG, JPEG XL, and WebP. Every pipeline uses the same final encoder, preserving EXIF, XMP, DPI, comments where supported, and the source ICC color profile. Orientation is normalized after source pixels are physically rotated. Vivid refuses color-managed JPEG XL output when `cjxl` is unavailable instead of silently replacing or dropping the profile.

App output is written beside the input with a predictable name:

```text
portrait-vivid-upscale-normal-2x.jpg
portrait-vivid-upscale-normal-deblur-motion-2x.jpg
portrait-vivid-upscale-advanced-2048px.webp
```

## Data locations

```text
~/.local/bin/vvd
~/.local/share/vivid/venv
~/.local/share/vivid/models/SEEDVR2
~/.local/share/vivid/models/HYPIR
~/.local/share/vivid/models/mlx/Real-ESRGAN-general-x4v3
~/.local/share/vivid/models/mlx/Real-ESRGAN-x4plus
~/.local/share/vivid/models/nomos-webphoto-esrgan
~/.local/share/vivid/models/restormer/motion
~/.local/share/vivid/models/restormer/defocus
```

Set `VIVID_HOME` to change the runtime and model root, or `VIVID_BIN_DIR` to change the standalone CLI installation directory.

## Development

Run the Swift test suite without launching the app:

```bash
swift test
```

The app is a SwiftPM executable. `install.sh` is the single source of truth for the CLI wrapper and Python processing helper; the app build script extracts those payloads into the generated app bundle.

Contributions are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the development workflow and [SECURITY.md](SECURITY.md) for private vulnerability reporting.

## License

Vivid Upscaler's original source code and repository assets are available under the [MIT License](LICENSE). Third-party packages and downloaded model weights are not relicensed by this repository; their respective upstream licenses and terms apply.
