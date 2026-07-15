# Vivid Upscaler Models

This is the definitive model reference for the app. The catalog below mirrors `ModelInfo.choices` in [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift), including the wording shown in the model manager. RAM values are the app's install-eligibility and usage guidance in GB.

| Mode | Model used by the app | Backend | Minimum RAM | Recommended RAM | Large-image RAM | Source URL | Description used in the app |
| --- | --- | --- | ---: | ---: | ---: | --- | --- |
| `fast` | `mlx-community/Real-ESRGAN-general-x4v3` | MLX | 8 GB | 16 GB | 24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-general-x4v3) | Quickest option: a compact native FP16 MLX upscaler for Apple Silicon. |
| `normal` | `mlx-community/Real-ESRGAN-x4plus` | MLX | 16 GB | 16 GB | 24 GB | [Hugging Face model](https://huggingface.co/mlx-community/Real-ESRGAN-x4plus) | The main quality and speed balance with a more powerful conventional single-pass upscaler. |
| `normal-hq` | `4xNomosWebPhoto_esrgan` | PyTorch MPS via Spandrel | 16 GB | 16 GB | 24 GB | [Hugging Face model](https://huggingface.co/Phips/4xNomosWebPhoto_esrgan) | Fast photographic restoration trained for compression, lens blur, noise, and Web/JPEG sources. |
| `advanced` | `SeedVR2 3B 8-bit` | Native MLX | 16 GB | 24 GB | 32 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI) | Difficult restoration jobs where a longer wait is acceptable, using the 3B model at 8-bit precision. |
| `maximum` | `SeedVR2 3B source precision` | Native MLX | 24 GB | 32 GB | 48 GB | [Hugging Face model files](https://huggingface.co/numz/SeedVR2_comfyUI) | Highest-quality, slowest SeedVR2 option using the 3B model at source precision. |

## Implementation notes

- The five entries above cover every `UpscaleMode` case: `fast`, `normal`, `normal-hq`, `advanced`, and `maximum`.
- `advanced` and `maximum` use the same SeedVR2 3B source weights. Advanced loads them at 8-bit precision; Maximum keeps source precision.
- The installer downloads the model files from the URLs and paths defined in [`install.sh`](install.sh). The MLX model pages are the source repositories for the two Real-ESRGAN variants; the installer uses their `resolve/main` files.
- RAM compatibility is enforced using the minimum value: a model is installable when detected system RAM is greater than or equal to its minimum requirement.
- The app's default tiling value for every model is `auto`; tiling can reduce memory pressure for larger inputs.

## Code references

- Catalog and app-facing descriptions: [`Sources/VividUpscaler/Models/ModelInfo.swift`](Sources/VividUpscaler/Models/ModelInfo.swift)
- Mode titles, details, and minimum-RAM policy: [`Sources/VividUpscaler/Models/UpscaleOptions.swift`](Sources/VividUpscaler/Models/UpscaleOptions.swift)
- Download sources and model file layout: [`install.sh`](install.sh)
- Catalog regression tests: [`Tests/VividUpscalerTests/ModelCatalogTests.swift`](Tests/VividUpscalerTests/ModelCatalogTests.swift)
