<div align="center">

# CleanNest

**See where your Mac storage went, then reclaim only what is genuinely safe to remove.**

A native macOS app that brings together Mole and a replaceable on-device MLX model. Core scans and model analysis stay on your Mac, and files go to the Trash by default.

[简体中文](README.md) · **English** · [繁體中文](README.zh-TW.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

[![CI](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/ci.yml)
[![CodeQL](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml/badge.svg?branch=main)](https://github.com/n9896027/CleanNest/actions/workflows/codeql.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-111111?logo=apple)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9%2B-F05138?logo=swift&logoColor=white)
[![MIT License](https://img.shields.io/badge/License-MIT-2F81F7.svg)](LICENSE)

[Documentation](#documentation) · [Releases](https://github.com/n9896027/CleanNest/releases) · [Report an issue](https://github.com/n9896027/CleanNest/issues) · [Security](SECURITY.md)

</div>

![CleanNest overview showing local disk usage, cleanup suggestions, system status, and recent activity](docs/images/overview.png)

CleanNest turns Mac cleanup from a black-box button into an understandable, reversible workflow. It shows where storage is being used and what a directory is generally for, then leaves the decision to you. It is not a “one-click booster,” and a model suggestion can never delete a file on its own.

| See | Understand | Act safely |
| --- | --- | --- |
| Browse directories, caches, apps, and system status | Use deterministic rules, with optional local AI for extra context | Preview and confirm each action; files go to the Trash by default |

> [!IMPORTANT]
> CleanNest is currently distributed as source code only. There is no official Developer ID-signed and Apple-notarized download yet. CI builds verify the project; they are not trusted public release binaries.

## Why CleanNest

| The problem | How CleanNest approaches it |
| --- | --- |
| Your disk is suddenly full, but the cause is unclear | Browse storage by folder and file size, with explanations for common macOS directories |
| Rebuildable caches are mixed with downloads and personal data | Separate low-risk generated data from items that require review or should be kept |
| Activity Monitor is too technical | Explain memory pressure, swap usage, and high-memory processes before you decide whether to quit anything |
| App uninstallers leave files behind | Preview the app and related files matched by its exact Bundle ID |
| You do not want a file inventory sent to a cloud model | Optionally use your chosen MLX model on the Mac with a deliberately limited, redacted metadata snapshot |

## Core capabilities

- **Storage cleanup** — scan developer caches, logs, installers, and other candidates; select items individually and move them to the macOS Trash.
- **Incremental disk browser** — stream partial results while scanning; reuse only unchanged metadata signatures for 15 minutes; disclose cache hits, live scans, and a cache-bypassing deep refresh.
- **Cleanup Decision Center** — combine breadcrumb drill-down and a native treemap with deterministic purpose, growth cause, impact, recoverability, confidence, and a safe next action for every item. You can manually mark an item for review, keep it, or decide later without overriding safety boundaries.
- **System status** — show CPU, memory, disk, battery, temperature, and health information, with 60-second local history plus plain-language memory-pressure and process guidance.
- **Process management** — request a normal process quit only after identity checks, system-process protection, and user confirmation; CleanNest does not automatically force-quit it.
- **App uninstall** — browse installed apps and preview the app bundle plus related files matched by exact Bundle ID.
- **System maintenance** — run selected low-risk maintenance tasks and keep their results in one activity history.
- **Auditable local learning** — explicit choices and successful cleanups create reviewable rule proposals. Nothing affects future ordering until you enable it, and every rule can be paused, resumed, or removed.
- **Model Workbench** — run a minimal streaming request that contains no scan metadata, then see loopback health latency, time to first output, total time, the exact API model ID, and memory-headroom guidance.
- **Data controls** — export or clear the activity log independently; restoring safe defaults resets preferences without silently erasing activity, learning rules, disk indexes, metric history, or macOS permissions.
- **Mole integration** — discover `mo` installed through Apple Silicon or Intel Homebrew, or install/update Mole from inside the app.
- **Update checks** — manually query the latest official GitHub Release from the app menu or About page; CleanNest only compares versions and opens a validated repository page, never silently downloading or installing.
- **Native macOS experience** — SwiftUI/AppKit interface, light and dark appearance, permission recovery guidance, activity history, and a safe demo mode.
- **Read-only MCP** — expose bounded, redacted local evidence to a trusted AI client over bundled stdio only; no HTTP listener, deletion, process control, or settings tools.
- **Three-language resources** — a String Catalog provides English, Simplified Chinese, and Traditional Chinese for core navigation and primary screens.

## Download and run

Requirements:

- macOS 14 Sonoma or later
- Xcode Command Line Tools, only when building from source
- Mole CLI, optional; CleanNest can install it through Homebrew from the app
- Apple Silicon and `mlx-lm`, only for optional local AI

Build from source:

```bash
git clone https://github.com/n9896027/CleanNest.git
cd CleanNest
./build.sh
open build/CleanNest.app
```

After the one-time source build, regular scanning, analysis, cleanup, maintenance, and Mole installation are available in the graphical app.

There is still no official Developer ID-signed and Apple-notarized download. Maintainers can manually create an ad-hoc-signed Universal 2 CI verification artifact with an SBOM, checksums, and provenance, but the workflow does not publish a Release and the artifact is not a trusted end-user installer. Do not trust third-party downloads claiming otherwise.

## Optional, replaceable on-device MLX model

CleanNest can connect to a local `mlx_lm.server` to add purpose explanations, risk notes, and a suggested review order to cleanup candidates and disk directories. The model is an explanation layer, not the cleanup engine. Deterministic scans still work without AI, and an AI failure does not change existing results.

Privacy and execution boundaries:

- Only an explicit `http://127.0.0.1:<port>/v1` endpoint is accepted; LAN and public model endpoints are rejected.
- Requests contain limited metadata such as type, size, age, one-time tokens, and redacted path hints—not file contents.
- Disk explanations use a bounded sample of direct child items rather than the full directory tree.
- The Swift client strictly validates fields, enums, response size, and item identity.
- AI cannot expand a scan, select an item, quit a process, run a command, or delete a file.
- Local learning stores only the item category, normalized display name, a one-way path fingerprint, successful-cleanup count, and model feedback. It excludes full candidate paths and file contents, and can be reviewed or cleared in the app.

In **Settings (`设置`) → Local AI Analysis (`本机 AI 分析`)**, CleanNest can reuse an existing loopback service such as oMLX or launch the selected `mlx_lm.server`. It reads the exact API model ID from `/v1/models` and keeps that short name separate from the local folder used for self-launch, so a filesystem path is never sent to oMLX as `model`. Common folders, including `~/.omlx/models`, are scanned with strict bounds. CleanNest never downloads a large model automatically, changes DFlash settings, or accepts model terms on your behalf.

## Safety model

- System roots, `/System`, `/Library`, the home directory itself, and an allowed root itself cannot become cleanup targets.
- Native cleanup accepts only validated descendant paths and rejects symbolic links.
- Files go to the macOS Trash by default; CleanNest does not use an irreversible `rm -rf` cleanup path.
- Removing system-level apps may require administrator authorization; the current version reports that limitation instead of bypassing it.
- High-risk interactive Mole commands are never auto-confirmed through simulated keyboard input.
- Pull requests run core tests, a complete app-bundle build, architecture checks, dependency review, and CodeQL.
- GitHub Actions use least-privilege permissions and immutable Action references; Dependabot checks dependency and Action updates.

See [SECURITY.md](SECURITY.md) for the disclosure scope and private reporting route.

## Documentation

Detailed maintainer documentation is currently written primarily in Simplified Chinese:

| Document | What it covers |
| --- | --- |
| [Permissions](docs/PERMISSIONS.md) | Full Disk Access, folder authorization, and why code identity affects macOS permissions |
| [Local AI](docs/LOCAL_AI.md) | MLX model discovery, switching, transmitted metadata, and safety boundaries |
| [Metric history](docs/METRICS.md) | 60-second sampling, SQLite WAL, retention, and field boundaries |
| [Read-only MCP](docs/MCP.md) | Local stdio configuration, seven tools, and the read-only trust boundary |
| [Threat model](docs/THREAT_MODEL.md) | Protected assets, attack surfaces, controls, and exclusions |
| [Troubleshooting](docs/TROUBLESHOOTING.md) | Mole, permissions, AI, build, process, and battery-status issues |
| [Architecture](docs/ARCHITECTURE.md) | Modules, data flow, and dangerous-operation boundaries |
| [Privacy](PRIVACY.md) | Local data, network access, retention, and removal |
| [Roadmap](ROADMAP.md) | Completed work, near-term priorities, and explicit non-commitments |
| [0.5.0 verification report](docs/VERIFICATION-0.5.0.md) | Local tests, large-directory incremental scan evidence, and gates that remain closed |
| [Maintainer operations](docs/OPERATIONS.md) | Change control, CI failures, credentials, releases, and security incidents |
| [Changelog](CHANGELOG.md) | Released and unreleased changes |
| [Contributing](CONTRIBUTING.md) | Development, testing, pull requests, and safety requirements |

## CleanNest and Mole

CleanNest is an independently developed graphical client. It is not the official Mole app and does not bundle the Mole binary. It invokes the user's separately installed CLI as an isolated local process and keeps attribution visible in Settings.

[Mole](https://github.com/tw93/Mole) is maintained by tw93 and contributors under GPL-3.0. CleanNest's own source code is available under the [MIT License](LICENSE). See [third-party notices](THIRD_PARTY_NOTICES.md) for MLX and user-selected model details.

## Development and verification

Run the app during development:

```bash
swift run CleanNest
```

Run the deterministic unit and integration checks:

```bash
swift test
swift run CleanNestSelfTest
```

Preview the UI with synthetic data only:

```bash
CLEANNEST_DEMO=1 swift run CleanNest
```

The current development version is **0.5.0 (Build 9)**. CI builds and tests on Apple Silicon and Intel runners. Reproducible bug reports and feature proposals are welcome in [Issues](https://github.com/n9896027/CleanNest/issues); report security vulnerabilities privately.

Core navigation and the main overview, disk, status, and settings surfaces now include English, Simplified Chinese, and Traditional Chinese resources. Some runtime diagnostics and path-dependent copy can still fall back to the source language; Japanese and Korean currently have localized project overviews rather than full UI resources.
