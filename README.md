# Vivid Mac CLI

Vivid is a Mac wrapper for photo upscaling with three modes:

- **fast** uses `realesr-general-x4v3`
- **normal** uses `4xNomosWebPhoto_RealPLKSR`
- **advanced** uses SeedVR2

The command name is:

```bash
vvd
```

## Install

```bash
./install.sh
```

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
```

## Modes

### Fast

Uses `realesr-general-x4v3` for the quickest photo upscaling.

### Normal

Uses `4xNomosWebPhoto_RealPLKSR` for a better quality and speed balance on general photography.
This is the default mode.

### Advanced

Uses SeedVR2 for the slowest but most restorative processing.

## Tiling

The wrapper supports:

```bash
--tile auto
--tile on
--tile off
```

Default is `auto`.

- In **fast** and **normal** mode, auto turns tiling on only for larger outputs.
- In **advanced** mode, auto decides whether SeedVR2 VAE tiling is needed based on output size and model.
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
