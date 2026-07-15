#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${VIVID_HOME:-$HOME/.local/share/vivid}"
BIN_DIR="${VIVID_BIN_DIR:-$HOME/.local/bin}"
VENV_DIR="$INSTALL_ROOT/venv"
MODEL_ROOT="$INSTALL_ROOT/models"
RUNTIME_VERSION="13"

if ! command -v uv >/dev/null 2>&1; then
  echo "Installing uv..."
  curl -LsSf https://astral.sh/uv/install.sh | sh
  export PATH="$HOME/.local/bin:$HOME/.cargo/bin:$PATH"
fi

mkdir -p "$INSTALL_ROOT" "$BIN_DIR" "$MODEL_ROOT"

REQUIRED_PYTHON="3.12"
CURRENT_PYTHON=""
if [[ -x "$VENV_DIR/bin/python" ]]; then
  CURRENT_PYTHON="$($VENV_DIR/bin/python -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
fi

if [[ -n "$CURRENT_PYTHON" && "$CURRENT_PYTHON" != "$REQUIRED_PYTHON" ]]; then
  echo "Replacing Python $CURRENT_PYTHON environment with Python $REQUIRED_PYTHON..."
  rm -rf "$VENV_DIR"
fi

if [[ ! -x "$VENV_DIR/bin/python" ]]; then
  echo "Installing Python $REQUIRED_PYTHON..."
  uv python install "$REQUIRED_PYTHON"
  echo "Creating Python $REQUIRED_PYTHON environment..."
  uv venv --python "$REQUIRED_PYTHON" "$VENV_DIR"
fi

echo "Installing dependencies..."
uv pip install --python "$VENV_DIR/bin/python" --upgrade pip setuptools wheel
uv pip install --python "$VENV_DIR/bin/python" torch torchvision
uv pip install --python "$VENV_DIR/bin/python" \
  "mflux==0.18.0" \
  "realesrgan-mlx @ git+https://github.com/xocialize/realesrgan-mlx.git@52c0fc1044277900b995308095a1f3cc484a3581" \
  pillow pillow-jxl-plugin "pyjpegxl==0.2.2" numpy "spandrel==0.4.2" "spandrel-extra-arches==0.2.0" safetensors huggingface-hub

cat > "$INSTALL_ROOT/vivid_upscale.py" <<'PY'
#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

import numpy as np
import pyjpegxl
from PIL import Image, ImageOps, PngImagePlugin

try:
    import pillow_jxl  # Registers JPEG XL support with Pillow.
except ImportError:
    pillow_jxl = None

MODELS = {
    "fast": {
        "display_name": "mlx-community/Real-ESRGAN-general-x4v3",
        "kind": "mlx",
        "variant": "realesr-general-x4v3",
        "download_dir": "mlx/Real-ESRGAN-general-x4v3",
    },
    "normal": {
        "display_name": "mlx-community/Real-ESRGAN-x4plus",
        "kind": "mlx",
        "variant": "RealESRGAN_x4plus",
        "download_dir": "mlx/Real-ESRGAN-x4plus",
    },
    "normal-hq": {
        "display_name": "4xNomosWebPhoto_esrgan",
        "kind": "spandrel",
        "files": {
            "main": {
                "filename": "4xNomosWebPhoto_esrgan.safetensors",
                "url": "https://huggingface.co/Phips/4xNomosWebPhoto_esrgan/resolve/main/4xNomosWebPhoto_esrgan.safetensors",
            }
        },
        "download_dir": "nomos-webphoto-esrgan",
    },
}

DEBLUR_MODELS = {
    "deblur-motion": {
        "display_name": "Restormer Motion Deblurring",
        "filename": "motion_deblurring.pth",
        "download_dir": "restormer/motion",
    },
    "deblur-defocus": {
        "display_name": "Restormer Single-Image Defocus Deblurring",
        "filename": "single_image_defocus_deblurring.pth",
        "download_dir": "restormer/defocus",
    },
}

EXTRA_ARCHES_INSTALLED = False


class ProgressBar:
    def __init__(self, label: str):
        self.label = label
        self.last_percent = -5

    def __call__(self, block_num: int, block_size: int, total_size: int) -> None:
        if total_size <= 0:
            return
        downloaded = block_num * block_size
        percent = min(100, int(downloaded * 100 / total_size))
        if percent == 100 or percent >= self.last_percent + 5:
            self.last_percent = percent
            print(f"      {self.label}: {percent}%", flush=True)


def download_if_missing(url: str, destination: Path) -> None:
    if destination.exists():
        return
    destination.parent.mkdir(parents=True, exist_ok=True)
    print(f"      Downloading {destination.name}", flush=True)
    urllib.request.urlretrieve(url, destination, ProgressBar(destination.name))


def choose_device() -> torch.device:
    if torch.backends.mps.is_available():
        return torch.device("mps")
    if torch.cuda.is_available():
        return torch.device("cuda")
    return torch.device("cpu")


def load_checkpoint(path: Path) -> dict:
    try:
        return torch.load(path, map_location="cpu", weights_only=True)
    except TypeError:
        return torch.load(path, map_location="cpu")


def checkpoint_state(checkpoint: dict) -> tuple[str | None, dict[str, torch.Tensor]]:
    if "params_ema" in checkpoint:
        return "params_ema", checkpoint["params_ema"]
    if "params" in checkpoint:
        return "params", checkpoint["params"]
    return None, checkpoint


def blended_model_path(main: Path, wdn: Path, strength: float, model_dir: Path) -> Path:
    if strength >= 0.9999:
        return main
    if strength <= 0.0001:
        return wdn

    destination = model_dir / f"realesr-general-x4v3-dn-{strength:.3f}.pth"
    if destination.exists():
        return destination

    print(f"      Preparing denoise blend {strength:.3f}...", flush=True)
    main_checkpoint = load_checkpoint(main)
    wdn_checkpoint = load_checkpoint(wdn)
    main_key, main_state = checkpoint_state(main_checkpoint)
    _, wdn_state = checkpoint_state(wdn_checkpoint)

    blended: dict[str, torch.Tensor] = {}
    for key, main_value in main_state.items():
        wdn_value = wdn_state[key]
        if torch.is_tensor(main_value) and torch.is_floating_point(main_value):
            blended[key] = main_value.mul(strength).add(wdn_value, alpha=1.0 - strength)
        else:
            blended[key] = main_value

    payload: dict | dict[str, torch.Tensor]
    if main_key is None:
        payload = blended
    else:
        payload = {main_key: blended}
    torch.save(payload, destination)
    return destination


def compute_target_size(width: int, height: int, short_edge: int, max_long_edge: int) -> tuple[int, int]:
    current_short = min(width, height)
    current_long = max(width, height)
    scale = short_edge / current_short
    if current_long * scale > max_long_edge:
        scale = max_long_edge / current_long
    return max(1, round(width * scale)), max(1, round(height * scale))


def choose_tile_size(
    tile_mode: str,
    width: int,
    height: int,
    native_scale: int,
    mode: str,
    system_ram_gb: int,
) -> int:
    if tile_mode == "off":
        return 0
    if tile_mode == "on":
        return 512 if mode == "fast" else 384

    # Restormer keeps large full-resolution feature maps alive throughout its
    # encoder/decoder. Even a roughly 4 MP source can exceed MPS's working-set
    # limit on an otherwise supported Mac, so automatic mode must tile deblur
    # passes independently of the later upscaler's memory policy.
    if mode == "deblur":
        return 512 if system_ram_gb >= 24 else 384

    native_megapixels = width * height * native_scale * native_scale / 1_000_000
    long_edge = max(width, height) * native_scale

    if mode == "fast":
        if native_megapixels > 80 or long_edge > 10000:
            return 384
        if native_megapixels > 24 or long_edge > 6500:
            return 512
        return 0

    if native_megapixels > 60 or long_edge > 9000:
        if system_ram_gb >= 24:
            return 512
        return 320
    if native_megapixels > 18 or long_edge > 5500:
        if system_ram_gb >= 24:
            return 512
        return 384
    return 0


def pil_to_tensor(image: Image.Image) -> torch.Tensor:
    array = np.asarray(image, dtype=np.float32) / 255.0
    array = np.ascontiguousarray(array.transpose(2, 0, 1))
    return torch.from_numpy(array).unsqueeze(0)


def tensor_to_uint8_rgb(tensor: torch.Tensor) -> np.ndarray:
    tensor = tensor.squeeze(0).detach().clamp_(0, 1).permute(1, 2, 0).cpu()
    return (tensor.numpy() * 255.0 + 0.5).astype(np.uint8)


def infer_full(model: ImageModelDescriptor, input_tensor: torch.Tensor, device: torch.device) -> np.ndarray:
    with torch.inference_mode():
        output = model(input_tensor.to(device))
    return tensor_to_uint8_rgb(output)


def infer_tiled(
    model: ImageModelDescriptor,
    input_tensor: torch.Tensor,
    device: torch.device,
    scale: int,
    tile_size: int,
    tile_pad: int = 24,
) -> np.ndarray:
    _, channels, height, width = input_tensor.shape
    output = np.empty((height * scale, width * scale, channels), dtype=np.uint8)
    tiles_x = math.ceil(width / tile_size)
    tiles_y = math.ceil(height / tile_size)
    total = tiles_x * tiles_y
    completed = 0

    # Upload the source once, then take each overlapping tile as an MPS view.
    # Copying every padded tile separately repeats the overlap transfer and
    # forces an avoidable allocation for every model invocation.
    input_tensor = input_tensor.to(device)

    with torch.inference_mode():
        for tile_y in range(tiles_y):
            y0 = tile_y * tile_size
            y1 = min(y0 + tile_size, height)
            py0 = max(0, y0 - tile_pad)
            py1 = min(height, y1 + tile_pad)

            for tile_x in range(tiles_x):
                x0 = tile_x * tile_size
                x1 = min(x0 + tile_size, width)
                px0 = max(0, x0 - tile_pad)
                px1 = min(width, x1 + tile_pad)

                patch = input_tensor[:, :, py0:py1, px0:px1]
                prediction = model(patch)

                crop_top = (y0 - py0) * scale
                crop_left = (x0 - px0) * scale
                crop_bottom = crop_top + (y1 - y0) * scale
                crop_right = crop_left + (x1 - x0) * scale
                prediction = prediction[:, :, crop_top:crop_bottom, crop_left:crop_right]

                output[y0 * scale:y1 * scale, x0 * scale:x1 * scale] = tensor_to_uint8_rgb(prediction)

                del patch, prediction
                completed += 1
                print(f"      Tiles: {completed}/{total}", flush=True)

    return output


def run_spandrel_model(weight_path: Path, image: Image.Image, tile_size: int) -> tuple[np.ndarray, int]:
    global torch, ImageModelDescriptor, ModelLoader, EXTRA_ARCHES_INSTALLED
    import torch
    import spandrel_extra_arches
    from spandrel import ImageModelDescriptor, ModelLoader

    if not EXTRA_ARCHES_INSTALLED:
        spandrel_extra_arches.install()
        EXTRA_ARCHES_INSTALLED = True

    if not weight_path.exists():
        raise RuntimeError(f"Model is not installed: {weight_path.name}")
    device = choose_device()
    print(f"      Device: {device}", flush=True)
    print("      Loading model...", flush=True)
    model = ModelLoader().load_from_file(weight_path)
    if not isinstance(model, ImageModelDescriptor):
        raise RuntimeError("The downloaded model is not an image-to-image model")
    model.to(device).eval()
    scale = int(model.scale)
    input_tensor = pil_to_tensor(image)
    if tile_size:
        output = infer_tiled(model, input_tensor, device, scale, tile_size)
    else:
        print("      Processing full image...", flush=True)
        output = infer_full(model, input_tensor, device)
    return output, scale


def deblur_image(
    image: Image.Image,
    mode: str,
    model_root: Path,
    tile_mode: str,
    system_ram_gb: int,
) -> Image.Image:
    spec = DEBLUR_MODELS[mode]
    weight_path = model_root / spec["download_dir"] / spec["filename"]
    width, height = image.size
    tile_size = choose_tile_size(tile_mode, width, height, 1, "deblur", system_ram_gb)
    tile_note = "off" if tile_size == 0 else f"on ({tile_size}px)"
    print("      Deblurring before upscale", flush=True)
    print(f"      Model:  {spec['display_name']} via PyTorch MPS", flush=True)
    print(f"      Tiling: {tile_note}", flush=True)
    output, scale = run_spandrel_model(weight_path, image, tile_size)
    if scale != 1:
        raise RuntimeError(f"Restormer reported an unexpected {scale}x output scale")
    return Image.fromarray(output, mode="RGB")


def jxl_distance_from_quality(quality: int) -> float:
    # Match libjxl's JxlEncoderDistanceFromQuality mapping. pyjpegxl's
    # `quality` argument is actually visual distance, where lower is better.
    if quality >= 100:
        return 0.0
    if quality >= 30:
        return 0.1 + (100 - quality) * 0.09
    return (53.0 / 3000.0 * quality * quality) - (23.0 / 20.0 * quality) + 25.0


def jxl_exif_box(exif: Image.Exif | None) -> bytes | None:
    if not exif:
        return None
    exif[274] = 1
    payload = exif.tobytes()
    if payload.startswith(b"Exif\x00\x00"):
        payload = payload[6:]
    # ISO/IEC 18181-2 stores a four-byte TIFF-header offset before the TIFF
    # payload. Pillow's bytes use JPEG APP1 framing instead.
    return b"\x00\x00\x00\x00" + payload


def cjxl_executable() -> Path | None:
    candidates = [
        os.environ.get("CJXL"),
        shutil.which("cjxl"),
        "/opt/homebrew/bin/cjxl",
        "/usr/local/bin/cjxl",
    ]
    for candidate in candidates:
        if candidate and os.access(candidate, os.X_OK):
            return Path(candidate)
    return None


def save_color_managed_jxl(
    image: Image.Image,
    destination: Path,
    quality: int,
    exif: Image.Exif | None,
    icc_profile: bytes,
    xmp: bytes | None,
) -> None:
    executable = cjxl_executable()
    if executable is None:
        raise RuntimeError(
            "JPEG XL output cannot retain this image's ICC color profile because cjxl is not installed. "
            "Install it with: brew install jpeg-xl"
        )

    with tempfile.TemporaryDirectory(prefix="vivid-jxl-") as temporary_directory:
        temporary_root = Path(temporary_directory)
        pixels_path = temporary_root / "pixels.png"
        image.save(pixels_path, format="PNG", icc_profile=icc_profile)
        arguments = [
            str(executable),
            str(pixels_path),
            str(destination),
            "-q",
            # cjxl maps this JPEG-like percentage to visual distance; every
            # quality exposed by the app (60-90) selects lossy VarDCT encoding.
            str(quality),
            "--container=1",
        ]

        if exif_box := jxl_exif_box(exif):
            exif_path = temporary_root / "exif.tiff"
            exif_path.write_bytes(exif_box[4:])
            arguments += ["-x", f"exif={exif_path}"]
        if xmp:
            xmp_path = temporary_root / "xmp.xml"
            xmp_path.write_bytes(xmp)
            arguments += ["-x", f"xmp={xmp_path}"]

        completed = subprocess.run(arguments, capture_output=True, text=True)
        if completed.returncode != 0:
            message = completed.stderr.strip() or completed.stdout.strip()
            raise RuntimeError(message or "cjxl failed to encode the output image")


def save_image(
    image: Image.Image,
    destination: Path,
    quality: int,
    exif: Image.Exif | None,
    icc_profile: bytes | None,
    xmp: bytes | None,
    source_info: dict[str, object] | None = None,
) -> None:
    destination.parent.mkdir(parents=True, exist_ok=True)
    source_info = source_info or {}
    if isinstance(xmp, str):
        xmp = xmp.encode("utf-8")
    save_kwargs: dict[str, object] = {}
    ext = destination.suffix.lower()
    dpi = source_info.get("dpi")
    if dpi and isinstance(dpi, tuple) and len(dpi) == 2:
        if exif is None:
            exif = Image.Exif()
        if 282 not in exif:
            exif[282] = float(dpi[0])
        if 283 not in exif:
            exif[283] = float(dpi[1])
        if 296 not in exif:
            exif[296] = 2
    exif_bytes = None
    if exif:
        # The pixels have already been physically transposed, so retain the
        # source metadata while preventing viewers from rotating them again.
        exif[274] = 1
        exif_bytes = exif.tobytes()
    if ext == ".jxl":
        if icc_profile:
            save_color_managed_jxl(image, destination, quality, exif, icc_profile, xmp)
            return
        # pyjpegxl uses libjxl container boxes that remain readable by Apple's
        # ImageIO decoder while retaining the source EXIF and XMP payloads.
        pyjpegxl.write_from_numpy(
            destination,
            np.asarray(image),
            lossless=quality >= 100,
            quality=jxl_distance_from_quality(quality),
            exif=jxl_exif_box(exif),
            xmp=xmp,
        )
        return
    if ext in {".jpg", ".jpeg"}:
        save_kwargs["quality"] = quality
        save_kwargs["subsampling"] = 0
    elif ext == ".webp":
        save_kwargs["quality"] = quality
    elif ext == ".png":
        pnginfo = PngImagePlugin.PngInfo()
        for key, value in source_info.items():
            if key not in {"exif", "icc_profile", "xmp", "dpi"} and isinstance(value, str):
                pnginfo.add_text(key, value)
            elif key == "comment" and isinstance(value, bytes):
                pnginfo.add_text(key, value.decode("utf-8", errors="replace"))
        if xmp:
            pnginfo.add_itxt("XML:com.adobe.xmp", xmp.decode("utf-8", errors="replace"))
        save_kwargs["pnginfo"] = pnginfo
    if exif_bytes:
        save_kwargs["exif"] = exif_bytes
    if icc_profile:
        save_kwargs["icc_profile"] = icc_profile
    if xmp and ext != ".png":
        save_kwargs["xmp"] = xmp
    if dpi:
        save_kwargs["dpi"] = dpi
    if source_info.get("comment") and ext in {".jpg", ".jpeg", ".webp"}:
        save_kwargs["comment"] = source_info["comment"]
    image.save(destination, **save_kwargs)


def main() -> int:
    parser = argparse.ArgumentParser(description="Photo upscaling for Vivid")
    parser.add_argument("input")
    parser.add_argument("output")
    parser.add_argument("--model-root", required=True)
    parser.add_argument("--mode", choices=["fast", "normal", "normal-hq"], required=True)
    parser.add_argument("--deblur", choices=["none", "deblur-motion", "deblur-defocus"], default="none")
    parser.add_argument("--short-edge", type=int, required=True)
    parser.add_argument("--max-long-edge", type=int, required=True)
    parser.add_argument("--tile", choices=["auto", "on", "off"], default="auto")
    parser.add_argument("--system-ram-gb", type=int, default=0, help=argparse.SUPPRESS)
    parser.add_argument("--denoise-strength", type=float, default=0.5)
    parser.add_argument("--quality", type=int, choices=range(1, 101), default=90, metavar="1-100")
    parser.add_argument("--finalize-only", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--deblur-only", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--metadata-source", help=argparse.SUPPRESS)
    args = parser.parse_args()

    if not 0 <= args.denoise_strength <= 1:
        parser.error("--denoise-strength must be between 0 and 1")

    input_path = Path(args.input)
    output_path = Path(args.output)
    if args.finalize_only:
        if not args.metadata_source:
            parser.error("--finalize-only requires --metadata-source")
        metadata_path = Path(args.metadata_source)
        with Image.open(metadata_path) as opened:
            exif = opened.getexif()
            icc_profile = opened.info.get("icc_profile")
            xmp = opened.info.get("xmp") or opened.info.get("XML:com.adobe.xmp")
            source_info = dict(opened.info)
            oriented_source = ImageOps.exif_transpose(opened)
            target_size = compute_target_size(*oriented_source.size, args.short_edge, args.max_long_edge)
        with Image.open(input_path) as processed:
            result = processed.convert("RGB")
            if result.size != target_size:
                result = result.resize(target_size, Image.Resampling.LANCZOS)
        save_image(result, output_path, args.quality, exif, icc_profile, xmp, source_info)
        input_path.unlink(missing_ok=True)
        return 0

    metadata_path = Path(args.metadata_source) if args.metadata_source else input_path
    with Image.open(metadata_path) as metadata_source:
        exif = metadata_source.getexif()
        icc_profile = metadata_source.info.get("icc_profile")
        xmp = metadata_source.info.get("xmp") or metadata_source.info.get("XML:com.adobe.xmp")
        source_info = dict(metadata_source.info)

    with Image.open(input_path) as opened:
        image = ImageOps.exif_transpose(opened).convert("RGB")

    if args.deblur_only:
        if args.deblur == "none":
            parser.error("--deblur-only requires a Restormer --deblur mode")
        result = deblur_image(image, args.deblur, Path(args.model_root), args.tile, args.system_ram_gb)
        output_path.parent.mkdir(parents=True, exist_ok=True)
        result.save(output_path, format="PNG")
        return 0

    if args.deblur != "none":
        image = deblur_image(image, args.deblur, Path(args.model_root), args.tile, args.system_ram_gb)

    spec = MODELS[args.mode]
    model_dir = Path(args.model_root) / spec["download_dir"]

    print("[2/3] Upscaling", flush=True)
    print(f"      Mode:   {args.mode}", flush=True)
    backend = "MLX" if spec["kind"] == "mlx" else "PyTorch MPS via Spandrel"
    print(f"      Model:  {spec['display_name']} via {backend}", flush=True)
    print("      Ensuring model weights...", flush=True)

    width, height = image.size
    target_width, target_height = compute_target_size(width, height, args.short_edge, args.max_long_edge)
    tile_size = choose_tile_size(
        args.tile,
        width,
        height,
        4,
        args.mode,
        args.system_ram_gb,
    )
    tile_note = "off" if tile_size == 0 else f"on ({tile_size}px)"
    print(f"      Source: {width}x{height}", flush=True)
    print(f"      Target: {target_width}x{target_height}", flush=True)
    print(f"      Native model output: {width * 4}x{height * 4}", flush=True)
    print(f"      Tiling: {tile_note}", flush=True)
    if args.mode == "fast":
        print(f"      Denoise strength: {args.denoise_strength}", flush=True)

    if spec["kind"] == "mlx":
        from realesrgan_mlx.pipeline_mlx import make_upsampler
        if not (model_dir / "model.safetensors").exists():
            raise RuntimeError(f"{spec['display_name']} is not installed. Run: vvd models install {args.mode}")
        print("      Device: MLX", flush=True)
        print("      Loading model...", flush=True)
        upsampler = make_upsampler(
            spec["variant"],
            denoise_strength=args.denoise_strength if args.mode == "fast" else 1.0,
            tile=tile_size,
            tile_pad=24,
            weights_dir=str(model_dir),
        )
        native_output, _ = upsampler.enhance(np.asarray(image))
    else:
        selected_weight = model_dir / spec["files"]["main"]["filename"]
        if not selected_weight.exists():
            raise RuntimeError(f"{spec['display_name']} is not installed. Run: vvd models install normal-hq")
        native_output, _ = run_spandrel_model(selected_weight, image, tile_size)

    result = Image.fromarray(native_output, mode="RGB")
    if result.size != (target_width, target_height):
        print("      Resizing to requested dimensions...", flush=True)
        result = result.resize((target_width, target_height), Image.Resampling.LANCZOS)

    print("      Saving output...", flush=True)
    save_image(result, output_path, args.quality, exif, icc_profile, xmp, source_info)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY
chmod +x "$INSTALL_ROOT/vivid_upscale.py"

cat > "$BIN_DIR/vvd" <<'WRAPPER'
#!/usr/bin/env bash
set -euo pipefail

INSTALL_ROOT="${VIVID_HOME:-$HOME/.local/share/vivid}"
PYTHON="$INSTALL_ROOT/venv/bin/python"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ -f "$SCRIPT_DIR/vivid_upscale.py" ]]; then
  UPSCALE_HELPER="$SCRIPT_DIR/vivid_upscale.py"
else
  UPSCALE_HELPER="$INSTALL_ROOT/vivid_upscale.py"
fi
MODEL_ROOT="$INSTALL_ROOT/models"
ORIGINAL_CWD="$PWD"

model_is_installed() {
  case "$1" in
    fast)
      [[ -f "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/model.safetensors" && -f "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/model_wdn.safetensors" && -f "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/config.json" ]]
      ;;
    normal)
      [[ -f "$MODEL_ROOT/mlx/Real-ESRGAN-x4plus/model.safetensors" && -f "$MODEL_ROOT/mlx/Real-ESRGAN-x4plus/config.json" ]]
      ;;
    normal-hq)
      [[ -f "$MODEL_ROOT/nomos-webphoto-esrgan/4xNomosWebPhoto_esrgan.safetensors" ]]
      ;;
    deblur-motion)
      [[ -f "$MODEL_ROOT/restormer/motion/motion_deblurring.pth" ]]
      ;;
    deblur-defocus)
      [[ -f "$MODEL_ROOT/restormer/defocus/single_image_defocus_deblurring.pth" ]]
      ;;
    advanced|maximum)
      [[ -f "$MODEL_ROOT/SEEDVR2/seedvr2_ema_3b_fp16.safetensors" && -f "$MODEL_ROOT/SEEDVR2/ema_vae_fp16.safetensors" ]]
      ;;
    *) return 1 ;;
  esac
}

download_model_file() {
  local url="$1"
  local destination="$2"
  if [[ -f "$destination" ]]; then
    echo "Already installed: $(basename "$destination")"
    return
  fi
  mkdir -p "$(dirname "$destination")"
  "$PYTHON" -u - "$url" "$destination" <<'PY'
from pathlib import Path
import sys
import urllib.request

url = sys.argv[1]
destination = Path(sys.argv[2])
partial = destination.with_suffix(destination.suffix + ".part")
last_percent = -5

def progress(block_count: int, block_size: int, total_size: int) -> None:
    global last_percent
    if total_size <= 0:
        return
    percent = min(100, int(block_count * block_size * 100 / total_size))
    if percent == 100 or percent >= last_percent + 5:
        last_percent = percent
        print(f"Downloading {destination.name}: {percent}%", flush=True)

try:
    urllib.request.urlretrieve(url, partial, progress)
    partial.replace(destination)
except BaseException:
    partial.unlink(missing_ok=True)
    raise
PY
}

system_ram_gb() {
  local bytes
  bytes="$(sysctl -n hw.memsize 2>/dev/null || true)"
  if [[ "$bytes" =~ ^[0-9]+$ ]]; then
    echo $((bytes / 1073741824))
  else
    echo 0
  fi
}

minimum_ram_for_model() {
  case "$1" in
    fast) echo 8 ;;
    normal|normal-hq|advanced|deblur-motion|deblur-defocus) echo 16 ;;
    maximum) echo 24 ;;
    *) echo 0 ;;
  esac
}

if [[ "${1:-}" == "models" ]]; then
  case "${2:-}" in
    status)
      if [[ "${3:-}" == "--json" ]]; then
        FAST=false; NORMAL=false; NORMAL_HQ=false; ADVANCED=false; MAXIMUM=false; DEBLUR_MOTION=false; DEBLUR_DEFOCUS=false
        model_is_installed fast && FAST=true
        model_is_installed normal && NORMAL=true
        model_is_installed normal-hq && NORMAL_HQ=true
        model_is_installed advanced && ADVANCED=true
        model_is_installed maximum && MAXIMUM=true
        model_is_installed deblur-motion && DEBLUR_MOTION=true
        model_is_installed deblur-defocus && DEBLUR_DEFOCUS=true
        printf '{"fast":%s,"normal":%s,"normal-hq":%s,"advanced":%s,"maximum":%s,"deblur-motion":%s,"deblur-defocus":%s}\n' "$FAST" "$NORMAL" "$NORMAL_HQ" "$ADVANCED" "$MAXIMUM" "$DEBLUR_MOTION" "$DEBLUR_DEFOCUS"
      else
        for MODEL_ID in fast normal normal-hq advanced maximum deblur-motion deblur-defocus; do
          if model_is_installed "$MODEL_ID"; then
            echo "$MODEL_ID: installed"
          else
            echo "$MODEL_ID: not installed"
          fi
        done
      fi
      exit 0
      ;;
    install)
      if [[ ! -x "$PYTHON" ]]; then
        echo "Vivid's runtime is not installed. Open Vivid Upscaler or run install.sh." >&2
        exit 1
      fi
      MODEL_ID="${3:-}"
      AVAILABLE_RAM="$(system_ram_gb)"
      REQUIRED_RAM="$(minimum_ram_for_model "$MODEL_ID")"
      if (( AVAILABLE_RAM > 0 && REQUIRED_RAM > AVAILABLE_RAM )); then
        echo "$MODEL_ID requires at least $REQUIRED_RAM GB RAM; this Mac has $AVAILABLE_RAM GB." >&2
        exit 1
      fi
      case "$MODEL_ID" in
        fast)
          download_model_file \
            "https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3/resolve/main/model.safetensors" \
            "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/model.safetensors"
          download_model_file \
            "https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3/resolve/main/model_wdn.safetensors" \
            "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/model_wdn.safetensors"
          download_model_file \
            "https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3/resolve/main/config.json" \
            "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3/config.json"
          ;;
        normal)
          download_model_file \
            "https://huggingface.co/mlx-community/Real-ESRGAN-x4plus/resolve/main/model.safetensors" \
            "$MODEL_ROOT/mlx/Real-ESRGAN-x4plus/model.safetensors"
          download_model_file \
            "https://huggingface.co/mlx-community/Real-ESRGAN-x4plus/resolve/main/config.json" \
            "$MODEL_ROOT/mlx/Real-ESRGAN-x4plus/config.json"
          ;;
        normal-hq)
          download_model_file \
            "https://huggingface.co/Phips/4xNomosWebPhoto_esrgan/resolve/main/4xNomosWebPhoto_esrgan.safetensors" \
            "$MODEL_ROOT/nomos-webphoto-esrgan/4xNomosWebPhoto_esrgan.safetensors"
          ;;
        deblur-motion)
          download_model_file \
            "https://github.com/swz30/Restormer/releases/download/v1.0/motion_deblurring.pth" \
            "$MODEL_ROOT/restormer/motion/motion_deblurring.pth"
          ;;
        deblur-defocus)
          download_model_file \
            "https://github.com/swz30/Restormer/releases/download/v1.0/single_image_defocus_deblurring.pth" \
            "$MODEL_ROOT/restormer/defocus/single_image_defocus_deblurring.pth"
          ;;
        advanced|maximum)
          download_model_file \
            "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/seedvr2_ema_3b_fp16.safetensors" \
            "$MODEL_ROOT/SEEDVR2/seedvr2_ema_3b_fp16.safetensors"
          download_model_file \
            "https://huggingface.co/numz/SeedVR2_comfyUI/resolve/main/ema_vae_fp16.safetensors" \
            "$MODEL_ROOT/SEEDVR2/ema_vae_fp16.safetensors"
          ;;
        *)
          echo "Usage: vvd models install fast|normal|normal-hq|advanced|maximum|deblur-motion|deblur-defocus" >&2
          exit 2
          ;;
      esac
      echo "Installed model: $MODEL_ID"
      exit 0
      ;;
    delete)
      MODEL_ID="${3:-}"
      case "$MODEL_ID" in
        fast) rm -rf "$MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3" ;;
        normal) rm -rf "$MODEL_ROOT/mlx/Real-ESRGAN-x4plus" ;;
        normal-hq) rm -rf "$MODEL_ROOT/nomos-webphoto-esrgan" ;;
        deblur-motion) rm -rf "$MODEL_ROOT/restormer/motion" ;;
        deblur-defocus) rm -rf "$MODEL_ROOT/restormer/defocus" ;;
        advanced|maximum) rm -rf "$MODEL_ROOT/SEEDVR2" ;;
        *) echo "Usage: vvd models delete fast|normal|normal-hq|advanced|maximum|deblur-motion|deblur-defocus" >&2; exit 2 ;;
      esac
      echo "Deleted model: $MODEL_ID"
      exit 0
      ;;
    *)
      echo "Usage: vvd models status [--json] | vvd models install MODEL | vvd models delete MODEL" >&2
      exit 2
      ;;
  esac
fi

if [[ $# -lt 1 || "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<'HELP'
Usage:
  vvd INPUT [OUTPUT] [options]

Examples:
  vvd photo.jpg
  vvd photo.jpg enhanced.png --scale 2
  vvd photo.jpg enhanced.png --mode fast --scale 2
  vvd photo.jpg enhanced.png --mode normal --scale 2
  vvd photo.jpg enhanced.png --mode advanced --scale 2
  vvd models status
  vvd models install normal

Modes:
  fast      Quickest upscaling with Real-ESRGAN general x4v3 via MLX.
  normal    Main quality/speed balance with Real-ESRGAN x4plus via MLX. Default.
  normal-hq Photographic restoration with 4xNomosWebPhoto_esrgan via Spandrel MPS.
  advanced  Native MLX SeedVR2 3B restoration with 8-bit quantization.
  maximum   Native MLX SeedVR2 3B restoration at source precision.

Optional preprocessing:
  deblur-motion   Restormer correction for camera shake, movement, and directional blur.
  deblur-defocus  Restormer correction for out-of-focus and lens blur.

Options:
  --mode MODE                  fast, normal, normal-hq, advanced, or maximum
  --fast                       Alias for --mode fast
  --normal                     Alias for --mode normal
  --advanced                   Alias for --mode advanced
  --deblur none|deblur-motion|deblur-defocus
                               Optional Restormer pass before upscaling. Default: none
  --scale N                    Multiply the source width and height by N. Files only.
  --resolution N               Target short edge in pixels. Default: 2048
  --max-resolution N           Maximum long edge. Default: 4096
  --tile auto|on|off           Tiling behavior. Default: auto
  --denoise-strength N         Fast mode denoise balance from 0 to 1. Default: 0.5
  --quality N                  JPG, JPEG XL, or WebP quality from 1 to 100. Default: 90
  --seed N                     Random seed for SeedVR2 modes. Default: 42
  --progress-interval N        Seconds between elapsed-time updates. Default: 10
  --no-progress                Disable wrapper progress messages
  --help                       Show this help

A bare output filename such as output.jpg is saved beside the input file.
Use ./output.jpg to explicitly save in the current working directory.
The first run downloads model weights and can use significant disk space.
Models are stored under ~/.local/share/vivid/models by default.
HELP
  exit 0
fi

if [[ ! -x "$PYTHON" || ! -f "$UPSCALE_HELPER" ]]; then
  echo "Vivid's runtime is not installed. Open Vivid Upscaler or run install.sh." >&2
  exit 1
fi

make_abs_path() {
  local path="$1"
  if [[ "$path" = /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ORIGINAL_CWD" "$path"
  fi
}

INPUT="$1"
shift

OUTPUT=""
if [[ $# -gt 0 && "$1" != --* ]]; then
  OUTPUT="$1"
  shift
fi

MODE="normal"
RESOLUTION="2048"
MAX_RESOLUTION="4096"
SCALE=""
SEED="42"
SHOW_PROGRESS="1"
PROGRESS_INTERVAL="10"
TILE_MODE="auto"
DENOISE_STRENGTH="0.5"
QUALITY="90"
DEBLUR="none"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="${2:?Missing value for --mode}"
      shift 2
      ;;
    --fast)
      MODE="fast"
      shift
      ;;
    --normal)
      MODE="normal"
      shift
      ;;
    --advanced)
      MODE="advanced"
      shift
      ;;
    --normal-hq)
      MODE="normal-hq"
      shift
      ;;
    --maximum)
      MODE="maximum"
      shift
      ;;
    --deblur)
      DEBLUR="${2:?Missing value for --deblur}"
      shift 2
      ;;
    --model)
      echo "Vivid only supports SeedVR2 3B; --model is not available." >&2
      exit 2
      ;;
    --scale|--multiplier)
      SCALE="${2:?Missing value for $1}"
      shift 2
      ;;
    --resolution)
      RESOLUTION="${2:?Missing value for --resolution}"
      shift 2
      ;;
    --max-resolution)
      MAX_RESOLUTION="${2:?Missing value for --max-resolution}"
      shift 2
      ;;
    --tile)
      TILE_MODE="${2:?Missing value for --tile}"
      shift 2
      ;;
    --denoise-strength)
      DENOISE_STRENGTH="${2:?Missing value for --denoise-strength}"
      shift 2
      ;;
    --quality)
      QUALITY="${2:?Missing value for --quality}"
      shift 2
      ;;
    --seed)
      SEED="${2:?Missing value for --seed}"
      shift 2
      ;;
    --progress-interval)
      PROGRESS_INTERVAL="${2:?Missing value for --progress-interval}"
      shift 2
      ;;
    --no-progress)
      SHOW_PROGRESS="0"
      shift
      ;;
    --help|-h)
      exec "$0"
      ;;
    *)
      echo "Unknown option: $1" >&2
      exit 2
      ;;
  esac
done

case "$MODE" in
  fast|normal|normal-hq|advanced|maximum) ;;
  *)
    echo "--mode must be fast, normal, normal-hq, advanced, or maximum" >&2
    exit 2
    ;;
esac

case "$DEBLUR" in
  none|deblur-motion|deblur-defocus) ;;
  *)
    echo "--deblur must be none, deblur-motion, or deblur-defocus" >&2
    exit 2
    ;;
esac

AVAILABLE_RAM="$(system_ram_gb)"
REQUIRED_RAM="$(minimum_ram_for_model "$MODE")"
if (( AVAILABLE_RAM > 0 && REQUIRED_RAM > AVAILABLE_RAM )); then
  echo "$MODE requires at least $REQUIRED_RAM GB RAM; this Mac has $AVAILABLE_RAM GB." >&2
  exit 1
fi
if [[ "$DEBLUR" != "none" ]]; then
  DEBLUR_REQUIRED_RAM="$(minimum_ram_for_model "$DEBLUR")"
  if (( AVAILABLE_RAM > 0 && DEBLUR_REQUIRED_RAM > AVAILABLE_RAM )); then
    echo "$DEBLUR requires at least $DEBLUR_REQUIRED_RAM GB RAM; this Mac has $AVAILABLE_RAM GB." >&2
    exit 1
  fi
  if ! model_is_installed "$DEBLUR"; then
    echo "$DEBLUR is not installed. Run: vvd models install $DEBLUR" >&2
    exit 1
  fi
fi
if [[ "$MODE" == "fast" && "$TILE_MODE" == "auto" && "$AVAILABLE_RAM" -gt 0 && "$AVAILABLE_RAM" -le 8 ]]; then
  TILE_MODE="on"
fi

case "$TILE_MODE" in
  auto|on|off) ;;
  *)
    echo "--tile must be auto, on, or off" >&2
    exit 2
    ;;
esac

if ! [[ "$PROGRESS_INTERVAL" =~ ^[0-9]+$ ]] || [[ "$PROGRESS_INTERVAL" == "0" ]]; then
  echo "--progress-interval must be a positive whole number." >&2
  exit 2
fi

if ! [[ "$QUALITY" =~ ^[0-9]+$ ]] || (( QUALITY < 1 || QUALITY > 100 )); then
  echo "--quality must be a whole number from 1 to 100." >&2
  exit 2
fi

INPUT="$(make_abs_path "$INPUT")"

if [[ -n "$OUTPUT" ]]; then
  if [[ "$OUTPUT" != */* && -f "$INPUT" ]]; then
    INPUT_DIR="$(cd "$(dirname "$INPUT")" && pwd -P)"
    OUTPUT="$INPUT_DIR/$OUTPUT"
  else
    OUTPUT="$(make_abs_path "$OUTPUT")"
  fi
fi
if [[ ! -f "$INPUT" ]]; then
  echo "Vivid currently requires a single input image." >&2
  exit 2
fi
if [[ -z "$OUTPUT" ]]; then
  OUTPUT="$($PYTHON - "$INPUT" <<'PY'
from pathlib import Path
import sys
p = Path(sys.argv[1])
print(str(p.with_name(f"{p.stem}_upscaled{p.suffix}")))
PY
)"
fi

mkdir -p "$MODEL_ROOT"

if [[ -n "$SCALE" ]]; then
  if [[ ! -f "$INPUT" ]]; then
    echo "--scale currently supports a single input image, not a directory." >&2
    exit 2
  fi

  if ! [[ "$SCALE" =~ ^[0-9]+([.][0-9]+)?$ ]] || [[ "$SCALE" == "0" ]] || [[ "$SCALE" == "0.0" ]]; then
    echo "--scale must be a positive number such as 2 or 4." >&2
    exit 2
  fi

  DIMENSIONS="$($PYTHON - "$INPUT" "$SCALE" <<'PY'
from pathlib import Path
import sys
from PIL import Image

path = Path(sys.argv[1])
scale = float(sys.argv[2])
if scale <= 0:
    raise SystemExit("--scale must be greater than zero")

with Image.open(path) as image:
    width, height = image.size

short_edge = max(1, round(min(width, height) * scale))
long_edge = max(1, round(max(width, height) * scale))
print(short_edge, long_edge)
PY
)"
  read -r RESOLUTION MAX_RESOLUTION <<< "$DIMENSIONS"
fi

ADVANCED_TILE_NOTE="off"
if [[ "$MODE" == "advanced" || "$MODE" == "maximum" ]]; then
  ADVANCED_TILE_NOTE="$($PYTHON - "$TILE_MODE" "$RESOLUTION" "$MAX_RESOLUTION" <<'PY'
import sys
tile_mode = sys.argv[1]
short_edge = int(sys.argv[2])
long_edge = int(sys.argv[3])
megapixels = short_edge * long_edge / 1_000_000
if tile_mode == 'on':
    print('on')
elif tile_mode == 'off':
    print('off')
else:
    # MFLUX low-RAM mode releases the transformer before VAE decode. Keep auto
    # mode safe on unified-memory Macs.
    print('on')
PY
)"
fi

PROCESSING_OUTPUT="$OUTPUT"
if [[ ( "$MODE" == "advanced" || "$MODE" == "maximum" ) && -n "$OUTPUT" ]]; then
  PROCESSING_OUTPUT="${OUTPUT%.*}.vivid-temp.png"
fi

# A value of 0.0 disables PyTorch's MPS allocation guard and can make macOS
# unresponsive under unified-memory pressure. These defaults retain most of the
# recommended Metal working set while leaving room for macOS and other apps.
export PYTORCH_MPS_HIGH_WATERMARK_RATIO="${PYTORCH_MPS_HIGH_WATERMARK_RATIO:-0.90}"
export PYTORCH_MPS_LOW_WATERMARK_RATIO="${PYTORCH_MPS_LOW_WATERMARK_RATIO:-0.80}"
export PYTHONUNBUFFERED="1"
export PYTORCH_ENABLE_MPS_FALLBACK="${PYTORCH_ENABLE_MPS_FALLBACK:-1}"

# Keep CPU-side decoding, color conversion, and tensor helpers from occupying
# every performance core. VIVID_CPU_THREADS remains an explicit escape hatch.
if [[ -z "${VIVID_CPU_THREADS:-}" ]]; then
  CPU_COUNT="$(sysctl -n hw.logicalcpu 2>/dev/null || printf '4')"
  if ! [[ "$CPU_COUNT" =~ ^[0-9]+$ ]] || (( CPU_COUNT < 1 )); then
    CPU_COUNT=4
  fi
  VIVID_CPU_THREADS=$((CPU_COUNT * 3 / 4))
  (( VIVID_CPU_THREADS < 1 )) && VIVID_CPU_THREADS=1
fi
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-$VIVID_CPU_THREADS}"
export MKL_NUM_THREADS="${MKL_NUM_THREADS:-$VIVID_CPU_THREADS}"
export VECLIB_MAXIMUM_THREADS="${VECLIB_MAXIMUM_THREADS:-$VIVID_CPU_THREADS}"
export NUMEXPR_NUM_THREADS="${NUMEXPR_NUM_THREADS:-$VIVID_CPU_THREADS}"

if [[ "$SHOW_PROGRESS" == "1" ]]; then
  echo "[1/3] Preparing Vivid"
  echo "      Input:  $INPUT"
  if [[ -n "$OUTPUT" ]]; then
    echo "      Output: $OUTPUT"
  else
    echo "      Output: auto-generated beside the input"
  fi
  echo "      Mode:   $MODE"
  case "$MODE" in
    advanced)
      echo "      Model:  SeedVR2 3B 8-bit via native MLX"
      echo "      SeedVR2 models: $MODEL_ROOT/SEEDVR2"
      echo "      Tiling: $ADVANCED_TILE_NOTE"
      ;;
    maximum)
      echo "      Model:  SeedVR2 3B source precision via native MLX"
      echo "      SeedVR2 models: $MODEL_ROOT/SEEDVR2"
      echo "      Tiling: $ADVANCED_TILE_NOTE"
      ;;
    normal)
      echo "      Model:  mlx-community/Real-ESRGAN-x4plus"
      echo "      Model files: $MODEL_ROOT/mlx/Real-ESRGAN-x4plus"
      echo "      Tiling: $TILE_MODE"
      ;;
    normal-hq)
      echo "      Model:  4xNomosWebPhoto_esrgan via PyTorch MPS/Spandrel"
      echo "      Model files: $MODEL_ROOT/nomos-webphoto-esrgan"
      echo "      Tiling: $TILE_MODE"
      ;;
    fast)
      echo "      Model:  mlx-community/Real-ESRGAN-general-x4v3"
      echo "      Model files: $MODEL_ROOT/mlx/Real-ESRGAN-general-x4v3"
      echo "      Tiling: $TILE_MODE"
      echo "      Denoise strength: $DENOISE_STRENGTH"
      ;;
  esac
  echo "      Target: short edge $RESOLUTION px, long edge up to $MAX_RESOLUTION px"
fi

START_SECONDS=$SECONDS

PROCESSING_INPUT="$INPUT"
DEBLUR_OUTPUT=""
if [[ "$DEBLUR" != "none" ]]; then
  DEBLUR_OUTPUT="${OUTPUT%.*}.vivid-deblur-temp.png"
  set +e
  "$PYTHON" -u "$UPSCALE_HELPER" \
    "$INPUT" "$DEBLUR_OUTPUT" \
    --model-root "$MODEL_ROOT" \
    --mode fast \
    --deblur "$DEBLUR" \
    --deblur-only \
    --short-edge "$RESOLUTION" \
    --max-long-edge "$MAX_RESOLUTION" \
    --tile "$TILE_MODE" \
    --system-ram-gb "$AVAILABLE_RAM"
  STATUS=$?
  set -e
  if [[ "$STATUS" -ne 0 ]]; then
    rm -f "$DEBLUR_OUTPUT"
    exit "$STATUS"
  fi
  PROCESSING_INPUT="$DEBLUR_OUTPUT"
fi

if [[ "$MODE" == "fast" || "$MODE" == "normal" || "$MODE" == "normal-hq" ]]; then
  set +e
  "$PYTHON" -u "$UPSCALE_HELPER" \
    "$PROCESSING_INPUT" "$OUTPUT" \
    --model-root "$MODEL_ROOT" \
    --mode "$MODE" \
    --short-edge "$RESOLUTION" \
    --max-long-edge "$MAX_RESOLUTION" \
    --tile "$TILE_MODE" \
    --system-ram-gb "$AVAILABLE_RAM" \
    --denoise-strength "$DENOISE_STRENGTH" \
    --quality "$QUALITY" \
    --metadata-source "$INPUT"
  STATUS=$?
  set -e
else
  cd "$INSTALL_ROOT"

  if [[ "$SHOW_PROGRESS" == "1" ]]; then
    echo "[2/3] Upscaling"
  fi

  MFLUX_ARGS=(
    --image-path "$PROCESSING_INPUT"
    --model "$MODEL_ROOT/SEEDVR2"
    --resolution "$RESOLUTION"
    --seed "$SEED"
    --output "$PROCESSING_OUTPUT"
  )
  if [[ "$MODE" == "advanced" ]]; then
    MFLUX_ARGS+=(--quantize 8)
  fi
  if [[ "$ADVANCED_TILE_NOTE" == "on" ]]; then
    MFLUX_ARGS+=(--low-ram)
  fi
  "$PYTHON" -u -m mflux.models.seedvr2.cli.seedvr2_upscale "${MFLUX_ARGS[@]}" &
  CHILD_PID=$!

  forward_signal() {
    kill -TERM "$CHILD_PID" 2>/dev/null || true
  }
  trap forward_signal INT TERM

  while kill -0 "$CHILD_PID" 2>/dev/null; do
    sleep 1
    if [[ "$SHOW_PROGRESS" == "1" ]] && kill -0 "$CHILD_PID" 2>/dev/null; then
      ELAPSED=$((SECONDS - START_SECONDS))
      if (( ELAPSED > 0 && ELAPSED % PROGRESS_INTERVAL == 0 )); then
        printf '      Still working: %02d:%02d elapsed\n' "$((ELAPSED / 60))" "$((ELAPSED % 60))"
      fi
    fi
  done

  set +e
  wait "$CHILD_PID"
  STATUS=$?
  set -e
  trap - INT TERM

  if [[ "$STATUS" -eq 134 ]]; then
    echo "SeedVR was stopped after Metal rejected an unsafe memory allocation." >&2
    echo "Try a smaller scale/resolution; Vivid's memory guard prevented macOS from exhausting unified memory." >&2
  fi

  if [[ "$STATUS" -eq 0 ]]; then
    set +e
    "$PYTHON" -u "$UPSCALE_HELPER" \
      "$PROCESSING_OUTPUT" "$OUTPUT" \
      --model-root "$MODEL_ROOT" \
      --mode fast \
      --short-edge "$RESOLUTION" \
      --max-long-edge "$MAX_RESOLUTION" \
      --quality "$QUALITY" \
      --finalize-only \
      --metadata-source "$INPUT"
    STATUS=$?
    set -e
  fi
fi

if [[ -n "$DEBLUR_OUTPUT" ]]; then
  rm -f "$DEBLUR_OUTPUT"
fi

ELAPSED=$((SECONDS - START_SECONDS))
if [[ "$STATUS" -eq 0 ]]; then
  printf '[3/3] Complete — total elapsed: %02d:%02d:%02d\n' \
    "$((ELAPSED / 3600))" "$(((ELAPSED % 3600) / 60))" "$((ELAPSED % 60))"
  if [[ "$SHOW_PROGRESS" == "1" ]]; then
    if [[ -n "$OUTPUT" ]]; then
      echo "      Saved: $OUTPUT"
    fi
  fi
else
  if [[ "$SHOW_PROGRESS" == "1" ]]; then
    echo "[3/3] Vivid failed with exit code $STATUS" >&2
  fi
fi

exit "$STATUS"
WRAPPER

chmod +x "$BIN_DIR/vvd"
printf '%s\n' "$RUNTIME_VERSION" > "$INSTALL_ROOT/runtime-version"

echo
echo "Installed: $BIN_DIR/vvd"
echo "Venv:      $VENV_DIR"
echo "Models:    $MODEL_ROOT"
if [[ ":$PATH:" != *":$BIN_DIR:"* ]]; then
  echo "Add this to your shell configuration:"
  echo "  set -Ux fish_user_paths $BIN_DIR \$fish_user_paths"
fi

echo
echo "Try:"
echo "  vvd photo.jpg enhanced.png --mode normal --scale 2"
echo "  vvd photo.jpg enhanced.png --mode advanced --scale 2"
