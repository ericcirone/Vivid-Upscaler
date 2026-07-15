# Vivid Upscaler

Vivid is a native Mac photo upscaler with an optional Terminal command.
The app bundles the CLI, so both surfaces execute the same models and processing pipeline.

The six modes are:

| Mode | Model | Minimum RAM | Recommended RAM | Large Image RAM | Default Tiling | Intended use |
| --- | --- | ---: | ---: | ---: | --- | --- |
| `fast` | `realesr-general-x4v3` | 8 GB | 16 GB | 24 GB | `auto` | Fastest general-purpose upscaling. Tiling is forced on 8 GB systems. |
| `normal` | `4xNomosWebPhoto_atd` | 16 GB | 16 GB | 24 GB | `auto` | Best balance for compressed, resized, noisy, or slightly blurry photographs. |
| `normal-hq` | `4xNomos2_hq_atd` | 16 GB | 16 GB | 24 GB | `auto` | Best for clean camera originals and high-quality source photographs. |
| `creative` | `AuraSR v2` | 16 GB | 24 GB | 32 GB | `auto` | Aggressive generated detail that may alter identity-sensitive details. |
| `advanced` | `SeedVR2 3B FP8` | 16 GB | 24 GB | 32 GB | `auto` | Faster SeedVR2 restoration with reduced memory use. |
| `maximum` | `SeedVR2 3B FP16` | 24 GB | 32 GB | 48 GB | `auto` | Highest-quality and most memory-intensive SeedVR2 processing. |

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
vvd ./input-folder ./output-folder --mode advanced --resolution 2048
vvd models status
vvd models status --json
vvd models install normal
vvd models delete normal
```

Supported GUI output choices are the input format, PNG, JPG, JPEG XL, and WebP.
JPEG XL encoding uses the reference `libjxl` implementation through `pyjpegxl`;
`pillow-jxl-plugin` provides JPEG XL input decoding.
When a source image contains an ICC color profile, Vivid uses `cjxl` in lossless
mode so the decoded JXL retains that exact profile instead of switching to
sRGB. Install the reference encoder with `brew install jpeg-xl` if it is not
already available.

## Modes

### Fast

Uses `realesr-general-x4v3` for the quickest photo upscaling.

### Normal and Normal HQ

Normal uses `4xNomosWebPhoto_atd` for imperfect or compressed photographs and is the default. Normal HQ uses `4xNomos2_hq_atd` for clean source photographs.

### Creative

Uses AuraSR v2 for more aggressive generated detail.

### Advanced and Maximum

Advanced uses SeedVR2 3B FP8. Maximum uses SeedVR2 3B FP16 for the highest quality at a substantially higher memory cost.

## Tiling

The wrapper supports:

```bash
--tile auto
--tile on
--tile off
```

Default is `auto`.

- In **fast**, **normal**, and **normal-hq** mode, auto turns tiling on for larger outputs. Normal and Normal HQ use larger tiles on Macs with at least 24 GB RAM to reduce overlap and model invocations without resizing the source. Fast forces tiling on 8 GB systems.
- **Creative** uses AuraSR's overlapped tiles.
- In **advanced** and **maximum** mode, auto always uses 512 px SeedVR2 VAE tiles on macOS. This keeps peak unified-memory use bounded while preserving the full requested output size.
- Vivid keeps PyTorch's Metal memory guard enabled and reserves CPU headroom so macOS remains responsive during long SeedVR2 runs. Advanced users can override the defaults with `PYTORCH_MPS_HIGH_WATERMARK_RATIO`, `PYTORCH_MPS_LOW_WATERMARK_RATIO`, or `VIVID_CPU_THREADS`.
- `off` forces the faster path when memory allows.
- `on` forces the safer lower memory path.

## Install locations

By default Vivid installs to:

```text
~/.local/bin/vvd
~/.local/share/vivid/repo
~/.local/share/vivid/venv
```

## Model locations

Downloaded model weights are kept in fixed locations:

```text
~/.local/share/vivid/models/SEEDVR2
~/.local/share/vivid/models/realesrgan
~/.local/share/vivid/models/nomos
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
- The default SeedVR2 model is `3b` for practicality on a Mac.
- `--scale 2` targets twice the source width and height. `--multiplier 2` is an alias.
- `--scale` currently accepts a single image. Folder processing still uses `--resolution`.
- `--denoise-strength` applies only to `fast` mode.
