# Contributing to Vivid Upscaler

Thanks for helping improve Vivid Upscaler.

## Development setup

Vivid requires an Apple Silicon Mac running macOS 14 or newer and Xcode Command Line Tools with Swift 6.

```bash
git clone https://github.com/ericcirone/Vivid-Upscaler.git
cd Vivid-Upscaler
swift test
./script/build_and_run.sh
```

The first processing run installs a Python 3.12 environment and downloads the selected model. These files live outside the repository under `~/.local/share/vivid` by default.

## Making changes

1. Create a focused branch from `main`.
2. Keep the Swift app and `vvd` behavior aligned. `install.sh` is the source of truth for the CLI wrapper and Python helper bundled into the app.
3. Add or update tests for behavior changes.
4. Run the checks below before opening a pull request.
5. Explain the user-visible result, testing performed, and any model or memory implications in the pull request.

```bash
swift test
bash -n install.sh script/build_and_run.sh
./script/build_and_run.sh build
```

Do not commit downloaded models, virtual environments, generated app bundles, credentials, or personal image files.

## Bug reports and feature requests

Use GitHub Issues for reproducible bugs and focused feature proposals. Include the macOS version, Mac model, memory size, Vivid mode, input dimensions and format, command or app steps, and complete error output where relevant. Do not attach private images or secrets.

Report security vulnerabilities privately as described in [SECURITY.md](SECURITY.md).
