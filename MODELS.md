# Vivid Upscaler Models

This is the definitive model reference for the app. The catalog below mirrors `ModelInfo.choices` in [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift), including the wording shown in the model manager. RAM values are the app's install-eligibility and usage guidance in GB.

| Mode                   | Model used by the app                       | Backend                   | Accepts seed | Minimum RAM | Recommended RAM | Large-image RAM | Source URL                                                                                   | Description used in the app                                                                                                                                    |
| ---------------------- | ------------------------------------------- | ------------------------- | :----------: | ----------: | --------------: | --------------: | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fast`                 | `mlx-community/Real-ESRGAN-general-x4v3`    | MLX                       |      No      |        8 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3)          | Quickest option: a compact native FP16 MLX upscaler for Apple Silicon.                                                                                         |
| `normal`               | `mlx-community/Real-ESRGAN-x4plus`          | MLX                       |      No      |       16 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-x4plus)                | The main quality and speed balance with a more powerful conventional single-pass upscaler.                                                                     |
| `normal-hq`            | `4xNomosWebPhoto_esrgan`                    | PyTorch MPS via Spandrel  |      No      |       16 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/Phips/4xNomosWebPhoto_esrgan)                    | Fast photographic restoration trained for compression, lens blur, noise, and Web/JPEG sources.                                                                 |
| `advanced`             | `SeedVR2 3B 8-bit`                          | Native MLX                |      Yes     |       16 GB |           24 GB |           32 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI)                      | Difficult restoration jobs where a longer wait is acceptable, using the 3B model at 8-bit precision.                                                           |
| `maximum`              | `SeedVR2 3B source precision`               | Native MLX                |      Yes     |       24 GB |           32 GB |           48 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI)                      | Highest-quality, slowest SeedVR2 option using the 3B model at source precision.                                                                                |
| `maximum-experimental` | `HYPIR-SD2`                                 | PyTorch MPS, experimental |      Yes     |       24 GB |           32 GB |           48 GB | [Official HYPIR model files](https://huggingface.co/lxq007/HYPIR)                            | Maximum-tier experimental generative restoration using a single-pass diffusion-derived model for strong detail reconstruction and adjustable texture richness. |
| `deblur-motion`        | `Restormer Motion Deblurring`               | PyTorch MPS               |      No      |       16 GB |           24 GB |           32 GB | [Official Restormer pretrained models](https://github.com/swz30/Restormer/releases/tag/v1.0) | Removes camera shake, subject movement, and directional motion blur while preserving the original image dimensions.                                            |
| `deblur-defocus`       | `Restormer Single-Image Defocus Deblurring` | PyTorch MPS               |      No      |       16 GB |           24 GB |           32 GB | [Official Restormer pretrained models](https://github.com/swz30/Restormer/releases/tag/v1.0) | Reduces out-of-focus and lens-related blur while preserving the original image dimensions.                                                                     |

## Seed support

Seed values select a repeatable generative variation. A higher or lower seed does not represent quality, restoration strength, detail level, or processing intensity.

Given the same model, input image, dimensions, settings, and seed, the result should be reproducible. Small differences may still occur because of backend-level nondeterminism.

Seed controls should only be shown for:

* `advanced`
* `maximum`
* `maximum-experimental`

The app-facing label should be **Variation Seed** rather than simply **Seed**.

The default variation seed is:

```text
42
```

A **Try Another Variation** action may generate a new random seed without changing any other restoration settings.

## SeedVR2 presets

The following presets apply to both SeedVR2 modes:

* `advanced`
* `maximum`

Each preset controls SeedVR2's input noise, latent noise, and color correction settings. The variation seed remains independently configurable.

| Preset                    | Input noise scale | Latent noise scale | Color correction | Description                                                                                                      |
| ------------------------- | ----------------: | -----------------: | ---------------- | ---------------------------------------------------------------------------------------------------------------- |
| `faithful`                |            `0.00` |             `0.00` | `lab`            | Preserves the source as closely as possible while maintaining strong color fidelity. Recommended as the default. |
| `high-resolution-cleanup` |            `0.15` |             `0.00` | `lab`            | Helps reduce ringing, repeated patterns, and unnatural artifacts that can appear at large output dimensions.     |
| `softer-detail`           |            `0.00` |             `0.08` | `wavelet`        | Reduces harsh or overly reconstructed texture while retaining a natural photographic appearance.                 |

### Faithful

```text
Input noise scale:  0.00
Latent noise scale: 0.00
Color correction:   lab
```

Use for:

* Faces and identity-sensitive photographs
* Clean modern photography
* Images where accurate colors matter
* General SeedVR2 processing

### High-Resolution Cleanup

```text
Input noise scale:  0.15
Latent noise scale: 0.00
Color correction:   lab
```

Use for:

* Very large requested output dimensions
* Ringing or repeated high-frequency patterns
* Unnatural texture that appears only at larger scales
* Images where the default result looks overly rigid or artifact-heavy

### Softer Detail

```text
Input noise scale:  0.00
Latent noise scale: 0.08
Color correction:   wavelet
```

Use for:

* Overly sharp skin texture
* Harsh hair, foliage, fabric, or surface detail
* Results that look too processed
* A softer and more photographic appearance

### Custom SeedVR2 settings

The app may also provide a `custom` preset that exposes:

| Setting            |                                                 Suggested range | Default |
| ------------------ | --------------------------------------------------------------: | ------: |
| Input noise scale  |                                                `0.00` to `1.00` |  `0.00` |
| Latent noise scale |                                                `0.00` to `1.00` |  `0.00` |
| Color correction   | `lab`, `wavelet`, `wavelet_adaptive`, `hsv`, `adain`, or `none` |   `lab` |
| Variation seed     |                                           Any supported integer |    `42` |

The interface should warn users that increasing either noise value does not simply increase quality. Noise settings alter how the model reconstructs the image and may reduce fidelity.

## Implementation notes

* The catalog contains six upscaling modes and two optional deblur processors.
* The six upscaling entries cover every `UpscaleMode` case: `fast`, `normal`, `normal-hq`, `advanced`, `maximum`, and `maximum-experimental`.
* `deblur-motion` and `deblur-defocus` are preprocessing operations rather than additional upscale modes. They restore the image at its existing dimensions before the selected upscaling model runs.
* Restormer provides separate pretrained tasks for single-image motion deblurring and single-image defocus deblurring. The app should not use the dual-pixel defocus checkpoint because ordinary imported photographs do not provide the paired dual-pixel input it requires.
* `deblur-motion` is intended for camera movement, subject movement, and directional smearing.
* `deblur-defocus` is intended for images that are uniformly or locally out of focus.
* The Restormer RAM values are Vivid's conservative app guidance for full-resolution PyTorch MPS processing. They are not official upstream system requirements.
* Restormer checkpoints are approximately 100 MB each, but processing memory is primarily determined by image dimensions, intermediate activations, and whether tiling is enabled.
* `fast`, `normal`, `normal-hq`, `deblur-motion`, and `deblur-defocus` are deterministic and do not expose a variation seed.
* `advanced`, `maximum`, and `maximum-experimental` accept a variation seed.
* A higher or lower variation seed does not represent stronger processing or better quality. Different values select different repeatable generative variations.
* `advanced` and `maximum` use the same SeedVR2 3B source weights. Advanced loads them at 8-bit precision; Maximum keeps source precision.
* SeedVR2 presets apply only to `advanced` and `maximum`.
* The default SeedVR2 preset is `faithful`.
* The default SeedVR2 variation seed is `42`.
* SeedVR2 preset settings should be persisted independently from the variation seed so users can try multiple seeds without losing their chosen restoration configuration.
* `maximum-experimental` uses the open-source HYPIR-SD2 model, which is initialized from Stable Diffusion 2.1 and performs restoration using a single forward pass rather than iterative diffusion sampling.
* The original `stabilityai/stable-diffusion-2-1-base` repository referenced by HYPIR is no longer public. Vivid installs the required FP16 Diffusers components from the commit-pinned `sd2-community/stable-diffusion-2-1-base` mirror and runs HYPIR from that local snapshot.
* HYPIR supports generative restoration, adjustable texture richness, optional text-guided control, and variation seeds. It may reconstruct plausible detail that was not present in the original image, so results should be treated as experimental when facial identity, text, or documentary accuracy matters.
* The official HYPIR implementation documents CUDA inference rather than Apple Silicon MPS. The `PyTorch MPS, experimental` backend represents Vivid-specific integration and should remain labeled experimental until tested across supported Mac configurations.
* HYPIR's official repository states that the software is restricted to non-commercial use unless separate permission is obtained. This restriction must be reviewed before HYPIR is distributed or enabled in a commercial release of Vivid.
* The HYPIR Hugging Face repository displays an Apache 2.0 label, but the official source repository separately declares a non-commercial restriction. Vivid should follow the more restrictive official repository terms unless legal review or written permission confirms otherwise.
* The installer downloads the model files from the URLs and paths defined in [`install.sh`](install.sh). The MLX model pages are the source repositories for the two Real-ESRGAN variants; the installer uses their `resolve/main` files.
* RAM compatibility is enforced using the minimum value: a model is installable when detected system RAM is greater than or equal to its minimum requirement.
* The app's default tiling value for every upscale and deblur model is `auto`; tiling can reduce memory pressure for larger inputs.
* When automatic deblur detection is unavailable or uncertain, the app should let the user choose between Motion Blur and Out of Focus rather than silently applying the wrong checkpoint.
* Deblurring should run before upscaling so the upscale model receives cleaner edges and more coherent source detail.
* HYPIR should remain opt-in and should not silently replace the regular `maximum` SeedVR2 mode.

## Suggested processing order

```text
Input image
  -> Optional Restormer deblur
  -> Selected Vivid upscale mode
  -> Apply model-specific variation and restoration settings
  -> Resize to requested dimensions
  -> Preserve metadata and save
```

## Code references

* Catalog and app-facing descriptions: [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift)
* Mode titles, details, experimental labeling, and minimum-RAM policy: [`Sources/VividUpscaler/Models/UpscaleOptions.swift`](Sources/VividUpscaler/Models/UpscaleOptions.swift)
* SeedVR2 presets and advanced restoration controls: [`Sources/VividUpscaler/Models/SeedVR2Options.swift`](Sources/VividUpscaler/Models/SeedVR2Options.swift)
* Variation-seed support and persistence: [`Sources/VividUpscaler/Models/GenerativeOptions.swift`](Sources/VividUpscaler/Models/GenerativeOptions.swift)
* Deblur choices and preprocessing configuration: [`Sources/VividUpscaler/Models/DeblurOptions.swift`](Sources/VividUpscaler/Models/DeblurOptions.swift)
* Download sources, licensing notices, and model file layout: [`install.sh`](install.sh)
* Catalog regression tests: [`Tests/VividUpscalerTests/ModelCatalogTests.swift`](Tests/VividUpscalerTests/ModelCatalogTests.swift)
