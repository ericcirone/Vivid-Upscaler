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
vvd input.jpg output.jxl --mode advanced --scale 2 --quality 90
vvd input.jpg output.png --mode maximum --tile on

vvd models status
vvd models status --json
vvd models install normal
vvd models delete normal
```

Run `vvd --help` for the complete option list. The main options are:

| Option | Description |
| --- | --- |
| `--mode MODE` | `fast`, `normal`, `normal-hq`, `advanced`, or `maximum`; default is `normal` |
| `--scale N` | Multiply both source dimensions by `N` |
| `--resolution N` | Target the short edge in pixels; default is 2048 |
| `--max-resolution N` | Cap the long edge in pixels; default is 4096 |
| `--tile auto\|on\|off` | Control lower-memory processing; default is `auto` |
| `--quality N` | JPG, JPEG XL, or WebP quality from 1 to 100; default is 90 |
| `--denoise-strength N` | Fast-mode denoise balance from 0 to 1; default is 0.5 |
| `--seed N` | SeedVR2 random seed; default is 42 |
| `--no-progress` | Hide wrapper progress messages |

A bare output filename is saved beside the input file. Include a slash, such as `./output.jpg`, to explicitly save relative to the current directory. When no output is supplied, Vivid writes an `_upscaled` file beside the input. The CLI currently processes one image at a time.

## Models and memory

| Mode | Model | Backend | Minimum RAM | Recommended RAM | Large Image RAM | Intended use |
| --- | --- | --- | ---: | ---: | ---: | --- |
| `fast` | `mlx-community/Real-ESRGAN-general-x4v3` | MLX | 8 GB | 16 GB | 24 GB | Quickest general-purpose upscaling |
| `normal` | `mlx-community/Real-ESRGAN-x4plus` | MLX | 16 GB | 16 GB | 24 GB | Main quality and speed balance |
| `normal-hq` | `4xNomosWebPhoto_esrgan` | PyTorch MPS via Spandrel | 16 GB | 16 GB | 24 GB | Photographic restoration for compression, blur, noise, and Web/JPEG sources |
| `advanced` | SeedVR2 3B 8-bit | Native MLX | 16 GB | 24 GB | 32 GB | Difficult restoration jobs where a longer wait is acceptable |
| `maximum` | SeedVR2 3B source precision | Native MLX | 24 GB | 32 GB | 48 GB | Highest-quality and slowest processing |

SeedVR2 is intentionally limited to the 3B model. Advanced quantizes it to 8-bit at load time; Maximum keeps the source precision.

### Tiling

`--tile auto` is the default. It enables a safer path for larger Real-ESRGAN and Normal HQ jobs and enables MFLUX low-RAM mode for Advanced and Maximum. `--tile on` forces the lower-memory path, while `--tile off` forces the faster path when memory allows. Fast mode automatically forces tiling on 8 GB systems.

Vivid keeps PyTorch's Metal memory guard enabled and reserves CPU headroom. Advanced users can override the defaults with `PYTORCH_MPS_HIGH_WATERMARK_RATIO`, `PYTORCH_MPS_LOW_WATERMARK_RATIO`, or `VIVID_CPU_THREADS`.

## Formats, metadata, and output names

The app supports the input format, PNG, JPG, JPEG XL, and WebP. Every pipeline uses the same final encoder, preserving EXIF, XMP, DPI, comments where supported, and the source ICC color profile. Orientation is normalized after source pixels are physically rotated. Vivid refuses color-managed JPEG XL output when `cjxl` is unavailable instead of silently replacing or dropping the profile.

App output is written beside the input with a predictable name:

```text
portrait-vivid-upscale-normal-2x.jpg
portrait-vivid-upscale-advanced-2048px.webp
```

## Data locations

```text
~/.local/bin/vvd
~/.local/share/vivid/venv
~/.local/share/vivid/models/SEEDVR2
~/.local/share/vivid/models/mlx/Real-ESRGAN-general-x4v3
~/.local/share/vivid/models/mlx/Real-ESRGAN-x4plus
~/.local/share/vivid/models/nomos-webphoto-esrgan
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
