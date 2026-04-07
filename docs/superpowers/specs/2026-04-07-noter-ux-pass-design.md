# Noter UX Pass Design

## Status

- Approved direction: `Workspace Shell + Focus Canvas`
- Scope: full UX pass across `Home`, `Workspaces`, `Edit`, `Preview`, and `Export`
- Locked workflow: keep `Intake -> Processing -> Edit -> Preview -> Export`
- Locked IA: `Hybrid`, with the product organized by workspace but daily use centered on the current active note
- Visual intensity: moderate upgrade, still clearly macOS-native

## Goal

Make Noter feel more focused, premium, and coherent without changing the core product model. The redesign should reduce navigation duplication, increase editing and preview immersion, and make the active note feel like the center of the app while preserving workspace context.

## Why This Pass Exists

The current app already has a strong product idea: a workspace-based note tool with a staged pipeline from intake through export. The friction is not the workflow itself. The friction comes from how many layers compete for attention at once.

Current issues observed in the code and UI:

- Global sidebar navigation and workspace-local category navigation overlap in purpose.
- Workspace overview and active-note workbench are mixed into the same screen shape.
- The five-stage workflow is correct conceptually but too visually expensive in the current layout.
- Editing repeats title/context information in multiple places.
- Preview and export controls are too stacked above the document surface instead of being moved to an inspector model.
- List cards surface too much content and too many destructive controls by default.

## Current Implementation Baseline

These code areas define the current structure and are the primary design anchors for the redesign:

- `Sources/NotesCurator/AppModel.swift`
  - `currentFlow` already models the five-stage workflow cleanly.
  - `showPreview()`, `showExport()`, `goBackToEditing()`, and `showWorkspaceOverview()` provide the main transition hooks.
- `Sources/NotesCurator/Views.swift`
  - `NotesCuratorRootView` defines the top-level `NavigationSplitView`.
  - `DashboardHomeView` currently acts as a broad dashboard.
  - `WorkspaceDetailView` currently mixes workspace overview and inner navigation.
  - `ProjectWorkspaceView` currently hosts the focused draft experience.
  - `WorkspaceFlowContainer` renders the workflow strip and stage-specific content.
  - `EditDocumentView`, `PreviewView`, and `ExportPageView` define the core editing and output experience.
  - `DraftRowCard` defines the current list card density and destructive action visibility.

## Product Constraints

These are hard constraints for the redesign:

- Keep the five-stage workflow and its semantics.
- Do not redesign the product into a note app without workspaces.
- Do not turn the app into a multi-document studio or multi-window workflow.
- Do not introduce new AI workflow features in this pass.
- Do not rewrite persistence or data models as part of the redesign.
- Prefer UI composition changes over state-machine changes.

## Design Principles

1. The active note is always the visual center.
2. Workspace context stays available, but it must sit behind the primary task.
3. Navigation should exist once per level, not be repeated in multiple places.
4. Controls should move to the edge of the canvas instead of sitting above the content.
5. The app should feel calmer, with fewer cards and less always-on chrome.
6. The redesign should look intentionally refined, not flashy or brand-reinvented.

## Target Information Architecture

### 1. Global Navigation

The left sidebar remains the only global navigation surface:

- `Home`
- `Workspaces`
- `Drafts`
- `Templates`
- `Exports`
- `Settings`

No workspace-local control should duplicate these destinations.

### 2. Workspace Shell

The workspace page becomes an environment shell, not a second dashboard and not a second navigation system.

Its responsibilities:

- identify the current workspace
- show high-value workspace context
- present the active note entry point
- show a compact history rail for nearby items

Its responsibilities do not include:

- replacing the global sidebar
- re-listing app-wide categories like templates or exports as local tabs
- becoming a fully separate page type from the focused note canvas

### 3. Focus Canvas

When a draft is opened, the right-hand workspace area becomes a single continuous focused canvas. This canvas hosts every stage of the five-step note lifecycle.

The user should feel that they are still working inside one stable surface while the tools around the document change by stage.

## Page Responsibilities

### Home

Home becomes a recovery-and-resume screen instead of a second broad dashboard.

Primary jobs:

- resume the current or last active note
- surface recent activity
- offer quick actions such as new workspace, new note, and resume session

Secondary jobs:

- show at most one small supporting context block, but not another large overview of the entire app

### Workspaces

The workspace view becomes the main environment context.

Primary jobs:

- show workspace identity and light summary
- show the active note as the primary focal object
- show recent or related items in a compact history treatment

Explicit removal:

- remove the current workspace-local segmented category control for `Drafts / Notes / Exports / Templates`

### Drafts / Templates / Exports

These remain app-wide library views accessible from the global sidebar. They should not be mirrored inside the workspace shell.

### Active Note Experience

The active note should always feel like the app's operational center. The surrounding workspace exists to orient the user, not to compete with the document.

## Layout System

### Workspace Shell + Focus Canvas

The redesign introduces two clear inner layers:

- `Workspace Shell`: context and surrounding items
- `Focus Canvas`: the active note and stage-specific tools

This is an evolutionary change, not a new architecture. Existing state transitions can remain intact.

### Canvas Header

The focused note canvas should have a stable top header with:

- back to workspace
- workspace name
- current note identity
- low-noise utility actions

The header should orient the user without overshadowing the document.

### Stage Control

The five-stage workflow should remain visible, but it should be presented as a compact flow control rather than a large standalone block.

Requirements:

- keep all five stages visible
- clearly show current stage, completed stages, and future stages
- take less vertical space than the current strip
- visually behave like canvas navigation, not like a second headline section

### Stage Surface

The stage content below the header should reuse one stable canvas structure. The layout should not feel like entering a completely different page each time.

## Stage-Specific Design

### Intake

Keep the current split between main input and lighter configuration, but simplify the chrome.

Requirements:

- large primary text/file intake area
- smaller side controls for language, templates, and output choices
- faster scanability than the current card stack

### Processing

Keep visible pipeline progress, but compress the presentation.

Requirements:

- preserve stage transparency
- reduce card fragmentation
- show progress and elapsed timing in a compact status-oriented layout
- keep "the app is still working" legible for long-running stages

### Edit

Edit should be the most immersive state in the app.

Requirements:

- remove redundant title presentation between the project header and the editor content area
- keep the document editor as the largest visual object
- keep inspector content present but secondary
- keep refinement status visible without dominating the editing surface

Preferred direction:

- the top header acts as breadcrumb and context
- the editor body owns the content identity

### Preview

Preview should evolve from a stacked settings-plus-document page into a review surface.

Requirements:

- left side or main area dedicated to the previewed document
- right-side inspector for format and visual settings
- bottom sticky action bar for navigation and CTA
- controls should not sit above the document unless they are truly global to the canvas

### Export

Export should feel like the final state of the same review surface used in preview, not a totally different page.

Requirements:

- preserve document preview dominance
- reuse the inspector pattern
- swap inspector content from "style review" to "output confirmation"
- keep the export CTA persistently available

## Inspector Model

Preview and export both move toward a right-side inspector model.

The inspector should own:

- format selection
- visual template selection
- language display
- export readiness messaging
- export destination and result messaging

Benefits:

- frees vertical space for document reading
- scales better as export options grow
- makes preview and export feel like one continuous tool

## List and Card Behavior

List cards should become quieter.

Requirements:

- prioritize title over summary
- clamp summaries to at most two lines in dense contexts
- keep timestamps visible but low contrast
- treat status as supportive metadata, not the main event
- hide destructive actions by default and reveal them on hover

Danger-action rule:

- delete and stop/delete affordances should not be always-on red accents in the resting state

## Sidebar Treatment

The `Active Workspace` area in the sidebar should become more compact and utility-oriented.

Requirements:

- keep it as a lightweight current-context indicator
- reduce explanatory copy
- reduce vertical weight
- avoid making it feel like a second content card inside navigation

## Visual Direction

This pass should feel more premium through restraint, not through louder branding.

Requirements:

- preserve strong macOS-native familiarity
- reduce repeated white cards where simple grouped layout will do
- keep one dominant accent language
- improve spacing, hierarchy, and contrast before adding decorative treatment
- favor calm surfaces and strong content hierarchy over dashboard chrome

## Interaction Decisions

- The focused note should remain open inside the workspace context rather than feeling like a separate app mode.
- The workspace history should stay visible in compact form when useful, but it should never dominate the active note.
- The primary CTA in preview and export must remain reachable during long-document scrolling.
- Dangerous actions should become contextual rather than ambient.

## Non-Goals

This redesign does not include:

- new workflow stages
- collaborative features
- multi-note comparison workflows
- new provider settings behavior
- export-format expansion
- large state-model refactors

## Risks

### 1. Too Much Shell, Not Enough Focus

If the workspace shell remains visually heavy, the redesign will not deliver the intended immersion even if the active note area improves.

### 2. Too Much Focus, Not Enough Context

If the redesign hides workspace context too aggressively, the app could lose the product identity that makes it distinct from generic note editors.

### 3. Preview and Export Divergence

If preview and export are redesigned independently, the user will still experience them as two disconnected pages.

### 4. Scope Creep

There is a real risk of letting this redesign turn into a product-model rewrite. The implementation plan must keep the work on IA, layout, and interaction structure.

## Acceptance Criteria

The redesign is successful when all of the following are true:

- A user can quickly identify the current workspace, the active note, and the current workflow stage.
- The workspace screen no longer includes a local category navigation that duplicates the global sidebar.
- The active note experience feels like one continuous canvas from edit through export.
- The edit page no longer repeats the note title in a confusing way.
- Preview and export clearly read as the same review/output surface with different inspector states.
- The document or preview surface is visually dominant in edit, preview, and export.
- List views are calmer, with shorter summaries and contextual destructive actions.
- The redesign can be implemented without changing the core five-stage state model.

## Implementation Guidance For Planning

The implementation plan should break the work into slices that can be validated independently:

1. information architecture and shell cleanup
2. focused canvas frame and compact stage control
3. edit-page immersion improvements
4. preview/export review surface unification
5. list-card and sidebar polish

The plan should prefer incremental changes to existing view boundaries unless a component extraction clearly reduces complexity.

## Planning Readiness Review

This spec is ready for implementation planning if:

- there are no remaining questions about whether the workflow is changing
- there are no remaining questions about whether workspace-based hybrid organization remains
- there is agreement that this is a layout and IA redesign, not a product-model rewrite
