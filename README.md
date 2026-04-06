# Noter

Noter is a macOS SwiftUI app for turning pasted text and imported files into structured, editable notes that can later be previewed and exported as Markdown, TXT, HTML, RTF, DOCX, or PDF.

This repository is safe to clone and run locally. It does not include real API keys, user databases, local app bundles, or personal cache files. If you want to use hosted AI providers, add your own API key locally in the app's Settings screen or through environment variables on your machine.

## Getting Started

Clone the repo:

```bash
git clone https://github.com/ycl-2004/Noter.git
cd Noter
```

Build the app:

```bash
swift build
```

Run tests:

```bash
swift test
```

Package a local macOS app bundle:

```bash
./scripts/package_app.sh debug
```

The packaged app will be created at:

```bash
dist/Noter.app
```

## API Keys

Hosted provider keys are intentionally not stored in this repository.

Use one of these approaches locally:

1. Open the app and paste your key into `Settings`.
2. Set an environment variable on your own machine before launching the app.

Supported environment variables:

- `NOTESCURATOR_NVIDIA_API_KEY`
- `NOTESCURATOR_OPENAI_API_KEY`
- `NOTESCURATOR_ZHIPU_API_KEY`
- `NOTESCURATOR_MISTRAL_API_KEY`
- `NOTESCURATOR_ANTHROPIC_API_KEY`
- `NOTESCURATOR_GEMINI_API_KEY`

The app is built around a staged workflow:

1. Intake
2. Processing
3. Editing
4. Preview
5. Export

It now uses a progressive refinement pipeline:

1. The app generates an interactive draft first.
2. The user can start editing as soon as the draft is ready.
3. Background refinement continues with polish and normalization.
4. A refined upgrade is offered as a safe version, not an automatic overwrite.

## Current Product Flow

### Interactive Lane

- Parse source text and files.
- Extract OCR text from attached images.
- Chunk and merge long inputs when needed.
- Generate the first structured draft.
- Localize the visible output language.
- Generate image suggestions.
- Save the draft as the current editable version.

This lane is optimized for speed and editor readiness.

### Background Refinement Lane

- Start after the interactive draft is already saved.
- Run polish when needed for formal output or language changes.
- Run repair / normalization to tighten structure.
- Save the result as a new refined version.
- Surface the result in the UI as a safe upgrade.

This lane is optimized for quality, not first-paint latency.

## Version Upgrade Model

Each draft can now move through refinement states:

- `none`
- `refining`
- `refined`
- `failed`

When a refined version is ready, the editor offers:

- `Compare Versions`
- `Apply Refined Version`
- `Dismiss Upgrade`

This keeps user edits safe. Background refinement never replaces the current version automatically.

## AI Routing and Provider Setup

The app supports multiple provider paths:

- Local Ollama
- Custom API
- Heuristic fallback

When using hosted APIs, the app can route different steps to different models:

- Main model
- Chunk model
- Polish model
- Repair model

Settings support separate API keys and model names through `AppPreferences`. Hosted API keys are now stored per service, so you can save one key for NVIDIA, another for Gemini, another for OpenAI, and switch providers without pasting the key again. For hosted providers, the UI exposes:

- Provider selection
- Hosted service presets
- Base URL
- Current service API key
- Saved API key fields for each hosted provider
- Main model
- Workflow routing toggle
- Chunk / polish / repair model assignments

Current workflow routing assumes:

- Long inputs may use chunk summarization before final merging.
- Formal documents or translation-like tasks may use polish.
- Repair is used to normalize structured output quality.

Stored per-service keys take priority, and environment variables act as a fallback.

## Main UI Areas

- Home dashboard
- Workspace list
- Draft list
- Template library
- Export history
- Settings

Inside a workspace, the active draft flows through:

- Intake form
- Processing view with visible stages
- Editing view with source drawer, AI suggestions, image suggestions, and refinement status
- Preview page
- Export page

## Project Structure

- `Sources/NotesCurator/AppModel.swift`
  App state, workflow orchestration, persistence coordination, background refinement tasks.
- `Sources/NotesCurator/Processing.swift`
  AI pipeline, chunking, draft generation, polish, repair, and provider routing.
- `Sources/NotesCurator/Views.swift`
  SwiftUI screens and editor workflow.
- `Sources/NotesCurator/Models.swift`
  Shared models, workflow states, versions, items, templates, exports, and preferences.
- `Sources/NotesCurator/Persistence.swift`
  SQLite-backed repository layer.
- `Sources/NotesCurator/Providers.swift`
  Provider adapters and provider-specific behavior.

## Functional Highlights

- Long-document chunking with concurrent chunk digest generation.
- Progressive refinement with safe version upgrades.
- OCR-assisted note generation from images.
- Structured notes, summaries, formal documents, and action-item outputs.
- Export-ready rendering across multiple formats.
- Template-driven content and visual styling.

## Stability Notes

The current codebase is organized around a single active workflow model:

- UI status badges
- app-level processing state
- background refinement state
- draft version history

All recent updates are connected to the same layout and runflow. The intended behavior is:

- one active editable version
- optional pending refined upgrade
- explicit user-controlled application of upgrades

## Development

Run tests with:

```bash
swift test
```

The test suite covers:

- processing pipeline behavior
- chunking and refinement flow
- app model workflow transitions
- persistence
- export behavior
- provider parsing
