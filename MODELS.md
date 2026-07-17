# Vivid Upscaler Models

This is the definitive model reference for the app. The catalog below mirrors `ModelInfo.choices` in [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift), including the wording shown in the model manager. RAM values are the app's install-eligibility and usage guidance in GB.

| Mode                   | Model used by the app                       | Backend                       | Accepts seed | Minimum RAM | Recommended RAM | Large-image RAM | Source URL                                                                                   | Description used in the app                                                                                                                                    |
| ---------------------- | ------------------------------------------- | ----------------------------- | :----------: | ----------: | --------------: | --------------: | -------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fast`                 | `mlx-community/Real-ESRGAN-general-x4v3`    | MLX                           |      No      |        8 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3)          | Quickest option: a compact native FP16 MLX upscaler for Apple Silicon.                                                                                         |
| `normal`               | `mlx-community/Real-ESRGAN-x4plus`          | MLX                           |      No      |       16 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-x4plus)                | The main quality and speed balance with a more powerful conventional single-pass upscaler.                                                                     |
| `normal-hq`            | `4xNomosWebPhoto_esrgan`                    | PyTorch MPS via Spandrel      |      No      |       16 GB |           16 GB |           24 GB | [Hugging Face model](https://huggingface.co/Phips/4xNomosWebPhoto_esrgan)                    | Fast photographic restoration trained for compression, lens blur, noise, and Web/JPEG sources.                                                                 |
| `advanced`             | `SeedVR2 3B 8-bit`                          | Native MLX                    |      Yes     |       16 GB |           24 GB |           32 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI)                      | Difficult restoration jobs where a longer wait is acceptable, using the 3B model at 8-bit precision.                                                           |
| `maximum`              | `SeedVR2 3B source precision`               | Native MLX                    |      Yes     |       24 GB |           32 GB |           48 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI)                      | Highest-quality, slowest SeedVR2 option using the 3B model at source precision.                                                                                |
| `maximum-experimental` | `HYPIR-SD2`                                 | PyTorch MPS, experimental     |      Yes     |       24 GB |           32 GB |           48 GB | [Official HYPIR model files](https://huggingface.co/lxq007/HYPIR)                            | Maximum-tier experimental generative restoration using a single-pass diffusion-derived model for strong detail reconstruction and adjustable texture richness. |
| `deblur-motion`        | `Restormer Motion Deblurring`               | PyTorch MPS                   |      No      |       16 GB |           24 GB |           32 GB | [Official Restormer pretrained models](https://github.com/swz30/Restormer/releases/tag/v1.0) | Removes camera shake, subject movement, and directional motion blur while preserving the original image dimensions.                                            |
| `deblur-defocus`       | `Restormer Single-Image Defocus Deblurring` | PyTorch MPS                   |      No      |       16 GB |           24 GB |           32 GB | [Official Restormer pretrained models](https://github.com/swz30/Restormer/releases/tag/v1.0) | Reduces out-of-focus and lens-related blur while preserving the original image dimensions.                                                                     |
| `face-restore`         | `CodeFormer v0.1.0`                         | PyTorch MPS via Vivid adapter |      No      |        8 GB |           16 GB |           24 GB | [Official CodeFormer repository](https://github.com/sczhou/CodeFormer)                       | Restores detected faces with an adjustable balance between stronger reconstruction and closer identity preservation.                                           |

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

## HYPIR restoration presets

The following presets apply only to:

* `maximum-experimental`

Each HYPIR preset controls restoration strength, the text prompt, and the tiling configuration. The variation seed and requested output dimensions remain independently configurable.

The prompt controls the desired restoration style. Patch size and patch stride primarily control memory use, scene context, tile overlap, seam consistency, and processing time.

Restoration strength is a Vivid-specific postprocessing control that blends HYPIR-generated high-frequency detail with the source image's high-frequency detail. It provides a more predictable natural-to-enhanced adjustment than prompt wording alone.

The default HYPIR preset is `balanced`.

| Preset     | Restoration strength | Patch size | Patch stride | Approximate overlap | Description                                                                                                                 |
| ---------- | -------------------: | ---------: | -----------: | ------------------: | --------------------------------------------------------------------------------------------------------------------------- |
| `natural`  |               `0.45` |     `1024` |        `768` |               `25%` | Applies restrained generated detail while preserving more of the source image's natural texture.                            |
| `balanced` |               `0.70` |      `768` |        `512` |               `33%` | Balances generated detail, source fidelity, processing speed, memory use, and tile consistency. Recommended as the default. |
| `enhanced` |               `1.00` |      `512` |        `256` |               `50%` | Applies the full HYPIR-generated detail result with stronger overlap and a more aggressive restoration prompt.              |

### Natural

```text
Restoration strength: 0.45
Patch size:          1024
Patch stride:        768
Prompt:              a natural photograph, realistic skin texture, accurate facial features, subtle detail, soft photographic sharpness
```

Use for:

* Modern photographs
* Portraits and family photos
* Identity-sensitive images
* Images that already contain usable detail
* Results that should remain subtle and photographic
* Faster processing when the larger patch fits available memory

The Natural preset blends more of the source image's existing high-frequency information into the result. It uses a restrained prompt and a larger patch to give HYPIR more surrounding image context.

### Balanced

```text
Restoration strength: 0.70
Patch size:          768
Patch stride:        512
Prompt:              a detailed realistic photograph, natural textures, clear facial features, balanced photographic sharpness
```

Use for:

* General HYPIR restoration
* Moderate blur, noise, or compression
* Old photographs without extreme physical damage
* Images that need clearer detail without maximum reconstruction
* A practical balance between performance and tile consistency

This is the recommended default HYPIR preset.

### Enhanced

```text
Restoration strength: 1.00
Patch size:          512
Patch stride:        256
Prompt:              a highly detailed professional photograph, sharp facial features, clear fine textures, crisp hair, detailed clothing
```

Use for:

* Heavily degraded images
* Very small or poorly resolved source photographs
* Severe compression and missing fine texture
* Images where perceived detail matters more than strict fidelity
* Cases where the user accepts a substantially longer processing time

The Enhanced preset uses the full HYPIR-generated high-frequency result without blending source high-frequency detail back into the image.

It also uses 50 percent overlap in both dimensions. Interior image regions may be processed by multiple overlapping patches, so this preset can be dramatically slower than Natural or Balanced.

The Enhanced preset may reconstruct plausible details that were not clearly present in the source. Faces, text, clothing patterns, hair, architecture, and other identity-sensitive details should be reviewed closely.

### Custom HYPIR settings

The app may also provide a `custom` preset that exposes:

| Setting              | Supported values                                         | Default                |
| -------------------- | -------------------------------------------------------- | ---------------------- |
| Restoration strength | `0.00` to `1.00`                                         | `0.70`                 |
| Patch size           | `512` to `1024`, in increments of `128`                  | `768`                  |
| Patch stride         | `256` to the selected patch size, in increments of `128` | `512`                  |
| Prompt               | User-provided text                                       | Balanced preset prompt |

The variation seed remains independently configurable and should not be reset when the user changes restoration strength, the HYPIR preset, patch configuration, or prompt.

#### Restoration strength behavior

| Strength | Behavior                                                                                          |
| -------: | ------------------------------------------------------------------------------------------------- |
|   `0.00` | Uses the source image's high-frequency detail without HYPIR-generated high-frequency enhancement. |
|   `0.25` | Very conservative restoration that remains close to the source.                                   |
|   `0.45` | Natural restoration with restrained generated detail.                                             |
|   `0.70` | Balanced restoration and recommended default.                                                     |
|   `1.00` | Uses the full HYPIR-generated high-frequency detail result.                                       |

Restoration strength should be implemented by blending source and generated high-frequency components while retaining the source image's low-frequency structure:

```text
Output =
  Source low frequencies
  + mix(
      Source high frequencies,
      HYPIR high frequencies,
      Restoration strength
    )
```

The interface should explain that restoration strength is a blend control rather than a model quality setting:

* Lower values preserve more source texture and reduce hallucinated detail.
* Higher values use more HYPIR-generated texture and reconstruction.
* Increasing strength does not guarantee a better or sharper result.
* Strength does not affect the variation seed.
* Strength does not reduce the cost of HYPIR inference because the complete HYPIR result must still be generated before blending.
* A strength of `0.00` is primarily useful for comparison and normally provides little reason to run HYPIR.

The interface should validate the following:

* Restoration strength must remain between `0.00` and `1.00`.
* Patch stride must not be greater than patch size.
* Patch size and stride must use values supported by the HYPIR adapter.
* Smaller stride values create more overlap and substantially increase processing time.
* Larger patch sizes use more memory but provide more image context per model call.
* Larger stride values reduce the number of tiled model calls but can increase the risk of visible seams.
* The prompt should describe the desired photographic result rather than provide editing commands.
* Strong prompt terms may increase reconstructed detail but can reduce source fidelity.
* Changing the seed selects a different variation. It does not make the prompt or restoration strength stronger or weaker.

Suggested prompt guidance:

| Goal                 | Suggested prompt wording                                                                                          |
| -------------------- | ----------------------------------------------------------------------------------------------------------------- |
| Natural photography  | `natural photograph, realistic textures, subtle detail, soft photographic sharpness`                              |
| Portrait restoration | `natural portrait photograph, accurate facial features, realistic skin texture, clear eyes, subtle detail`        |
| Old family photo     | `faithfully restored vintage family photograph, natural skin, period-appropriate detail, subtle film grain`       |
| Landscape            | `detailed natural landscape photograph, realistic foliage, clear distant detail, natural atmospheric perspective` |
| Strong enhancement   | `highly detailed professional photograph, crisp realistic textures, clear fine detail`                            |

The interface should discourage prompts containing exaggerated terms such as:

```text
ultra sharp
hyper detailed
perfect face
8K masterpiece
flawless skin
```

These terms can encourage plastic textures, oversharpening, or invented facial details.

## CodeFormer face-restoration presets

CodeFormer is an optional preprocessor that restores detected faces before the selected Vivid upscaling mode runs.

CodeFormer uses a fidelity weight from `0.0` to `1.0`. Lower values favor stronger reconstruction and cleaner-looking facial detail. Higher values favor closer identity preservation and greater similarity to the source.

The default CodeFormer preset is `balanced`.

| Preset     | Fidelity weight | Description                                                                                           |
| ---------- | --------------: | ----------------------------------------------------------------------------------------------------- |
| `enhance`  |           `0.4` | Applies stronger facial reconstruction for heavily degraded, blurry, compressed, or very small faces. |
| `balanced` |           `0.7` | Balances facial cleanup with identity preservation. Recommended as the default.                       |
| `faithful` |           `0.9` | Prioritizes resemblance to the original face and applies more conservative restoration.               |

### Enhance

```text
Fidelity weight: 0.4
```

Use for:

* Very blurry or heavily compressed faces
* Small faces with little usable detail
* Damaged or low-resolution old photographs
* Images where a cleaner result matters more than exact facial fidelity

This preset may reconstruct facial details that were not clearly present in the source. Eye shape, skin texture, teeth, hairlines, and other identity-sensitive features should be reviewed closely.

### Balanced

```text
Fidelity weight: 0.7
```

Use for:

* General face restoration
* Family photographs
* Moderate blur or compression
* Faces that need cleanup without aggressive reconstruction

This is the recommended default because it provides a practical balance between perceived quality and identity preservation.

### Faithful

```text
Fidelity weight: 0.9
```

Use for:

* Identity-sensitive photographs
* Faces that are already reasonably clear
* Subtle cleanup of compression or softness
* Images where resemblance matters more than maximum sharpness

This preset is more conservative and may leave some blur, noise, or degradation visible.

### Custom CodeFormer settings

The app may also provide a `custom` preset that exposes:

| Setting         | Suggested range | Default |
| --------------- | --------------: | ------: |
| Fidelity weight |  `0.0` to `1.0` |   `0.7` |

The interface should explain that fidelity weight is a trade-off rather than a simple strength slider:

* Lower values produce stronger reconstruction and may change facial identity.
* Higher values preserve more source identity but may retain visible degradation.
* A value of `1.0` does not disable processing.
* A value of `0.0` does not guarantee the highest-quality or most accurate face.

## Implementation notes

* The catalog contains six upscaling modes and three optional preprocessors.
* The six upscaling entries cover every `UpscaleMode` case: `fast`, `normal`, `normal-hq`, `advanced`, `maximum`, and `maximum-experimental`.
* The three preprocessing entries are `deblur-motion`, `deblur-defocus`, and `face-restore`.
* `deblur-motion`, `deblur-defocus`, and `face-restore` are preprocessing operations rather than additional upscale modes. They preserve the full image dimensions before the selected upscaling model runs.
* Restormer provides separate pretrained tasks for single-image motion deblurring and single-image defocus deblurring. The app should not use the dual-pixel defocus checkpoint because ordinary imported photographs do not provide the paired dual-pixel input it requires.
* `deblur-motion` is intended for camera movement, subject movement, and directional smearing.
* `deblur-defocus` is intended for images that are uniformly or locally out of focus.
* The Restormer RAM values are Vivid's conservative app guidance for full-resolution PyTorch MPS processing. They are not official upstream system requirements.
* Restormer checkpoints are approximately 100 MB each, but processing memory is primarily determined by image dimensions, intermediate activations, and whether tiling is enabled.
* `face-restore` detects faces, aligns and crops each detected face, restores it with CodeFormer, and blends the restored result back into the original image.
* CodeFormer internally processes aligned face crops at its expected face resolution. The preprocessor should still return an image with the same full dimensions as its input.
* CodeFormer should restore detected face regions only. Vivid should not enable CodeFormer's optional Real-ESRGAN background enhancement because the selected Vivid upscaling mode runs later in the pipeline.
* Vivid should not enable CodeFormer's optional Real-ESRGAN face upsampling by default. CodeFormer should restore the face at preprocessing time, while the selected Vivid model controls final image enlargement.
* CodeFormer fidelity weight must remain between `0.0` and `1.0`.
* Smaller CodeFormer fidelity values favor stronger reconstruction and perceived quality. Larger values favor closer fidelity to the source face.
* The default CodeFormer preset is `balanced`, with a fidelity weight of `0.7`.
* CodeFormer preset settings should be persisted independently from the selected upscale mode.
* CodeFormer is deterministic and does not expose a variation seed.
* CodeFormer should be disabled by default and enabled explicitly by the user.
* The app should warn that CodeFormer may alter identity-sensitive facial details, especially with the `enhance` preset.
* When multiple faces are detected, the selected CodeFormer preset should be applied consistently to every face unless per-face controls are introduced later.
* If no face is detected, the preprocessor should leave the image unchanged and clearly report that no eligible faces were found.
* If a face is extremely small, heavily occluded, or only partially visible, the app should avoid presenting the restored result as an accurate recovery of the original person.
* CodeFormer officially documents CUDA-oriented inference. The `PyTorch MPS via Vivid adapter` backend represents Vivid-specific Apple Silicon integration and should be tested across supported Mac configurations.
* CodeFormer uses the NTU S-Lab License 1.0. Redistribution and commercial use must be reviewed before the model or its code is bundled with Vivid.
* `fast`, `normal`, `normal-hq`, `deblur-motion`, `deblur-defocus`, and `face-restore` are deterministic and do not expose a variation seed.
* `advanced`, `maximum`, and `maximum-experimental` accept a variation seed.
* A higher or lower variation seed does not represent stronger processing or better quality. Different values select different repeatable generative variations.
* `advanced` and `maximum` use the same SeedVR2 3B source weights. Advanced loads them at 8-bit precision; Maximum keeps source precision.
* SeedVR2 presets apply only to `advanced` and `maximum`.
* The default SeedVR2 preset is `faithful`.
* The default SeedVR2 variation seed is `42`.
* SeedVR2 preset settings should be persisted independently from the variation seed so users can try multiple seeds without losing their chosen restoration configuration.
* `maximum-experimental` uses the open-source HYPIR-SD2 model, which is initialized from Stable Diffusion 2.1 and performs restoration using a single forward pass rather than iterative diffusion sampling.
* The HYPIR presets are `natural`, `balanced`, `enhanced`, and `custom`.
* The default HYPIR preset is `balanced`.
* HYPIR restoration strength is a Vivid-specific high-frequency blend control rather than an official HYPIR model argument.
* HYPIR restoration strength must remain between `0.00` and `1.00`.
* The default HYPIR restoration strength is `0.70`.
* The `natural`, `balanced`, and `enhanced` presets use restoration strengths of `0.45`, `0.70`, and `1.00`, respectively.
* Vivid should retain the source image's low-frequency structure and blend between source and HYPIR-generated high-frequency detail using the selected restoration strength.
* Changing HYPIR restoration strength does not avoid or shorten inference because Vivid must generate the complete HYPIR result before blending.
* HYPIR preset settings should be persisted independently from the restoration strength, variation seed, and requested output dimensions.
* HYPIR restoration strength should be persisted independently from the prompt, patch settings, variation seed, and requested output dimensions.
* The HYPIR prompt controls the desired photographic content and texture style. Patch size and stride control tiling behavior rather than generative strength.
* The named HYPIR presets provide fixed restoration-strength, prompt, patch-size, and stride values.
* The `custom` HYPIR preset exposes restoration strength, prompt, patch size, and patch stride.
* HYPIR patch size must remain between `512` and `1024`.
* HYPIR patch stride must remain between `256` and the selected patch size.
* A smaller HYPIR stride creates more overlap, more tiled inference calls, and longer processing times.
* The `enhanced` HYPIR preset intentionally uses `512/256` tiling and may be substantially slower than the other presets.
* A larger HYPIR patch can improve scene context but requires more unified memory.
* HYPIR presets must not change the user's selected variation seed unless the user explicitly requests a new variation.
* Vivid runs HYPIR directly at the requested output dimensions instead of generating a fixed 4x intermediate.
* HYPIR retains its BF16 inference dtype on MPS for output correctness.
* When a named HYPIR preset is active, its restoration strength, patch size, stride, and prompt override the corresponding custom values.
* When the `custom` HYPIR preset is active, Vivid passes the selected patch size, patch stride, and prompt directly to the HYPIR adapter, then applies the selected restoration strength during final wavelet reconstruction.
* The generic `--tile` mapping applies only when no explicit HYPIR preset configuration is provided.
* The original `stabilityai/stable-diffusion-2-1-base` repository referenced by HYPIR is no longer public. Vivid installs the required FP16 Diffusers components from the commit-pinned `sd2-community/stable-diffusion-2-1-base` mirror and runs HYPIR from that local snapshot.
* HYPIR supports generative restoration, adjustable texture richness, optional text-guided control, and variation seeds. It may reconstruct plausible detail that was not present in the original image, so results should be treated as experimental when facial identity, text, or documentary accuracy matters.
* The official HYPIR implementation documents CUDA inference rather than Apple Silicon MPS. The `PyTorch MPS, experimental` backend represents Vivid-specific integration and should remain labeled experimental until tested across supported Mac configurations.
* HYPIR's official repository states that the software is restricted to non-commercial use unless separate permission is obtained. This restriction must be reviewed before HYPIR is distributed or enabled in a commercial release of Vivid.
* The HYPIR Hugging Face repository displays an Apache 2.0 label, but the official source repository separately declares a non-commercial restriction. Vivid should follow the more restrictive official repository terms unless legal review or written permission confirms otherwise.
* The installer downloads the model files from the URLs and paths defined in [`install.sh`](install.sh). The MLX model pages are the source repositories for the two Real-ESRGAN variants; the installer uses their `resolve/main` files.
* RAM compatibility is enforced using the minimum value: a model is installable when detected system RAM is greater than or equal to its minimum requirement.
* The app's default tiling value for every upscale and deblur model is `auto`; tiling can reduce memory pressure for larger inputs.
* CodeFormer processes individual detected face crops and does not use the general image tiling setting.
* When automatic deblur detection is unavailable or uncertain, the app should let the user choose between Motion Blur and Out of Focus rather than silently applying the wrong checkpoint.
* Global deblurring should run before CodeFormer so that the face-restoration model receives cleaner face crops.
* CodeFormer should run before the selected Vivid upscale mode because it is defined as a preprocessor.
* HYPIR should remain opt-in and should not silently replace the regular `maximum` SeedVR2 mode.

## Suggested processing order

```text
Input image
  -> Optional Restormer deblur
  -> Optional CodeFormer face restoration
  -> Selected Vivid upscale mode
  -> Apply model-specific preset, prompt, variation, and restoration settings
  -> Resize to requested dimensions
  -> Preserve metadata and save
```

## Code references

* Catalog and app-facing descriptions: [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift)
* Mode titles, details, experimental labeling, and minimum-RAM policy: [`Sources/VividUpscaler/Models/UpscaleOptions.swift`](Sources/VividUpscaler/Models/UpscaleOptions.swift)
* SeedVR2 presets and advanced restoration controls: [`Sources/VividUpscaler/Models/SeedVR2Options.swift`](Sources/VividUpscaler/Models/SeedVR2Options.swift)
* HYPIR presets, restoration strength, prompt, and tiling controls: [`Sources/VividUpscaler/Models/HYPIROptions.swift`](Sources/VividUpscaler/Models/HYPIROptions.swift)
* Variation-seed support and persistence: [`Sources/VividUpscaler/Models/GenerativeOptions.swift`](Sources/VividUpscaler/Models/GenerativeOptions.swift)
* Deblur choices and preprocessing configuration: [`Sources/VividUpscaler/Models/DeblurOptions.swift`](Sources/VividUpscaler/Models/DeblurOptions.swift)
* CodeFormer presets and face-restoration configuration: [`Sources/VividUpscaler/Models/CodeFormerOptions.swift`](Sources/VividUpscaler/Models/CodeFormerOptions.swift)
* Preprocessor ordering and composition: [`Sources/VividUpscaler/Processing/PreprocessingPipeline.swift`](Sources/VividUpscaler/Processing/PreprocessingPipeline.swift)
* Download sources, licensing notices, and model file layout: [`install.sh`](install.sh)
* Catalog regression tests: [`Tests/VividUpscalerTests/ModelCatalogTests.swift`](Tests/VividUpscalerTests/ModelCatalogTests.swift)
