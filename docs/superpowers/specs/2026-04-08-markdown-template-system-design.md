# Markdown Template System Design

## Status

- Approved direction: `Section-DSL Markdown` for content templates
- Scope: first release of user-editable content templates with strong product boundaries
- Locked editing boundary: content templates are editable only inside `Template Library`
- Locked intake boundary: `New Note` only chooses content template, visual template, and language
- Locked edit boundary: changing the selected content template does not auto-regenerate the draft
- Locked regeneration rule: users must explicitly trigger `Regenerate with Template`

## Goal

Make content templates into real product assets that can define output structure, layout order, and section visibility instead of acting like fixed labels with light prompt guidance. The first release should let users create and edit markdown-based content templates in `Template Library`, then select those templates during note creation and draft regeneration without allowing template editing to leak into other surfaces.

## Why This Pass Exists

The current app exposes a template library, but the content templates do not actually behave like independently editable templates. They are mostly preset names plus lightweight configuration that feed prompt guidance and sample previews. The result is that different templates can feel visually and structurally similar even when they are intended to serve different use cases.

Current product issues:

- Content templates are defined in code, not as editable template bodies.
- Template preview content is sample data rendered through a fixed SwiftUI preview surface, so most content templates share the same layout rhythm.
- `New Note` correctly restricts the user to selecting templates, but the selected content template does not fully control the output structure.
- `Edit`, `Preview`, and `Export` do not clearly separate "current draft editing" from "template definition editing".
- Visual templates already act as a separate concept from content templates, but content templates are not structurally independent enough to justify their own library.

## Current Implementation Baseline

These areas define the current template pipeline and are the anchor points for the redesign:

- `Sources/NotesCurator/Models.swift`
  - `Template` currently stores `kind`, `scope`, `name`, and a generic `config` dictionary.
  - `IntakeRequest` carries `contentTemplateName` and `visualTemplateName`.
  - `ExportMetadata` stores template names on the generated draft.
- `Sources/NotesCurator/AppModel.swift`
  - `defaultTemplates` defines all system templates in code.
  - `saveUserTemplate(kind:name:config:)` only persists a very lightweight user template.
  - `contentTemplates` and `visualTemplates` are simple filters over the template list.
- `Sources/NotesCurator/Views.swift`
  - `NewNoteIntakeView` only lets the user choose templates before generation.
  - `TemplateLibraryView` shows template cards and preview pages, but not a full template editor.
  - `TemplatePreviewPage` uses sample draft data, not editable markdown template sources.
  - `EditDocumentView` edits the current draft but has no content-template switching or regeneration affordance.
- `Sources/NotesCurator/Processing.swift`
  - Provider requests are influenced by selected template names.
  - The generated draft receives both structured data and a provider-produced `renderedDocument`.
- `Sources/NotesCurator/Providers.swift`
  - Template influence is mostly prompt guidance derived from template name and goal.
- `Sources/NotesCurator/DocumentRendering.swift`
  - The in-app visual preview is a fixed structured-document renderer.
- `Sources/NotesCurator/Exporting.swift`
  - Markdown, HTML, DOCX, and PDF export derive from fixed rendering logic or structured-document serialization.

## Product Constraints

These constraints are hard requirements for the first release:

- Keep `Template Library` as the only place where template definitions can be created or edited.
- Keep `New Note` focused on source input and template selection, not template authoring.
- Keep `Edit` focused on the current draft content, not template definition editing.
- Do not auto-regenerate a draft when the content template selection changes after generation.
- Require explicit user action before replacing an existing draft with a regenerated result.
- Preserve the current distinction between content templates and visual templates.
- Avoid turning v1 into a full general-purpose templating language or arbitrary scripting system.
- Prefer localized changes to the current app structure over a full rewrite of the workflow model.

## Design Principles

1. Template definitions live in one place and only one place.
2. AI generates semantic content; the app controls structural rendering.
3. A content template must be able to produce obviously different output shapes.
4. The selected template must affect both generation guidance and the final rendered markdown.
5. Draft editing and template editing are separate responsibilities.
6. Invalid templates should fail safely inside `Template Library` and never corrupt a live draft.

## Product Boundary

### 1. Template Library

`Template Library` becomes the exclusive home for content-template authoring.

Responsibilities:

- create a new content template
- duplicate a system or user content template
- edit content template metadata
- edit markdown template source
- preview the template with sample data
- delete user-owned content templates

Non-responsibilities:

- starting a note-generation run
- editing current draft text
- exporting a document

### 2. New Note

`New Note` remains the intake surface for a generation request.

Responsibilities:

- collect pasted text and files
- choose output language
- choose content template
- choose visual template
- start the curation run

Non-responsibilities:

- editing template source
- editing template metadata
- configuring template structure inline

### 3. Edit

`Edit` remains the working surface for the current draft.

Responsibilities:

- edit the current draft markdown text
- save manual versions
- switch the currently bound content template
- explicitly regenerate the draft using the newly selected template

Non-responsibilities:

- editing the definition of the selected template
- auto-regenerating content on every template selection change

### 4. Preview

`Preview` only reviews the current draft result. It must not become a template-authoring surface.

### 5. Export

`Export` only confirms format and produces output files. It must not own template editing.

## Content Template Format

The approved v1 content-template format is a markdown-based template with a small front-matter header and a restricted templating DSL.

### Format Shape

Each content template consists of:

- metadata fields stored with the template record
- a markdown template body
- a small front-matter block embedded at the top of the body

Example:

```md
---
goal: actionItems
generation_hint: |
  Generate a task-first document.
  Put next steps early.
  Keep glossary optional.
sample_data: action_plan
---

# {{title}}

{{summary}}

{{#if actionItems}}
## Next Steps
{{#each actionItems}}
- {{item}}
{{/each}}
{{/if}}

{{#each sections}}
### {{title}}
{{body}}
{{/each}}
```

### Supported DSL in v1

The first release should support only a deliberately small set of template features:

- scalar variables
  - `{{title}}`
  - `{{summary}}`
- conditional blocks
  - `{{#if actionItems}} ... {{/if}}`
  - `{{#if glossary}} ... {{/if}}`
- repeated collection blocks
  - `{{#each actionItems}} ... {{/each}}`
  - `{{#each sections}} ... {{/each}}`
  - `{{#each keyPoints}} ... {{/each}}`
  - `{{#each cueQuestions}} ... {{/each}}`
  - `{{#each glossary}} ... {{/each}}`
  - `{{#each studyCards}} ... {{/each}}`
  - `{{#each reviewQuestions}} ... {{/each}}`
- collection item fields
  - generic repeated items use `{{item}}`
  - section items use `{{title}}`, `{{body}}`, `{{bulletPoints}}`
  - glossary items use `{{term}}`, `{{definition}}`
  - study-card items use `{{question}}`, `{{answer}}`

### Supported Front-Matter Fields

V1 front matter should stay intentionally small:

- `goal`
  - maps to `GoalType`
- `generation_hint`
  - extra prompt guidance appended to provider instructions
- `sample_data`
  - selects a preview sample preset in `Template Library`

Unsupported in v1:

- arbitrary expressions
- nested conditionals beyond one level
- custom helper functions
- user-defined variables
- arbitrary code execution

## How Content Templates Affect Generation

The template must influence both the provider prompt and the final app-side markdown rendering.

### Provider Role

The provider remains responsible for generating semantic content:

- title
- summary
- sections
- key points
- cue questions
- glossary
- study cards
- review questions
- action items

### App Role

The app becomes responsible for structural rendering.

This is the key architectural shift:

- the provider-generated `renderedDocument` is no longer the source of truth for the editable markdown document
- instead, the app renders `editorDocument` locally from:
  - the structured provider response
  - the selected content template definition

This makes content templates real structure owners instead of prompt-only labels.

## End-to-End Data Flow

### 1. Template Selection During New Note

`New Note` collects:

- source text / files
- output language
- content template name
- visual template name

The request is then submitted without any inline template editing.

### 2. Processing Pipeline

When processing starts:

1. load the selected content template definition
2. parse its front matter and markdown body
3. infer which content blocks the template depends on
4. derive prompt guidance from:
   - `goal`
   - `generation_hint`
   - used content blocks
5. call the provider to generate structured content
6. render final markdown locally using the template and the structured result
7. save that rendered markdown as `editorDocument`

### 3. Edit Page After Generation

The generated draft opens in `Edit`.

The user can:

- edit the current markdown text
- save a manual version
- open preview
- change the content template binding

Changing the content template binding:

- does not auto-regenerate
- does not immediately overwrite `editorDocument`
- marks the draft as out of sync with the selected content template

### 4. Explicit Regenerate

When the user clicks `Regenerate with Template`:

1. the app confirms replacement if current draft edits would be overwritten
2. the app re-runs generation from the original source text and draft settings
3. the app uses the newly selected template for both prompt guidance and local markdown rendering
4. the new rendered markdown replaces the current draft content

### 5. Preview and Export

`Preview` and `Export` should consume the already-rendered draft content and selected visual theme. They should not re-author the content template or compile user template source live at the final output step.

## UI Design Changes

### Template Library

Add a content-template editor with:

- template name
- subtitle
- description
- goal picker
- sample data preset picker
- generation hint editor
- markdown template body editor
- live validation panel
- live sample preview panel

Required actions:

- `New Template`
- `Duplicate Template`
- `Save Template`
- `Delete Template`

System templates should be duplicable but not directly overwritten.

### New Note

Keep the surface simple:

- input area
- language selector
- content-template selector
- visual-template selector
- `Start Curating`

Do not add template-source editing here.

### Edit

Add:

- current content-template indicator
- content-template selector
- status message when selected template differs from the draft's last generated template
- explicit `Regenerate with Template` button

Suggested message:

- `Template changed. Regenerate to apply the new structure.`

### Preview

Continue to present the current draft result, with visual-theme controls only.

### Export

Continue to present format selection and visual-theme controls only.

## Template Preview Strategy

To make templates visibly different in the library, template preview should not reuse a single fixed structured-document layout for all content templates.

Instead:

- each content template preview should render the template body itself
- preview uses sample structured data chosen by `sample_data`
- the preview should clearly reflect:
  - section order
  - block visibility
  - heading style
  - list rhythm
  - document pacing

Example differences expected in v1:

- `Action Plan`
  - `Next Steps` appears near the top
  - execution items dominate
- `Formal Brief`
  - stronger report structure
  - recommendations and context blocks lead the document
- `Study Guide`
  - cue questions, glossary, and study cards are prominent

## Data Model Changes

The current `Template` model should be extended instead of replaced.

Recommended additions:

- `subtitle: String`
- `templateDescription: String`
- `format: TemplateFormat`
- `body: String`

`TemplateFormat` should support at least:

- `legacyConfig`
- `markdownTemplate`

V1 content templates should use `markdownTemplate`.
Visual templates may continue to use the current lightweight configuration style initially.

The app should preserve backward compatibility for existing system templates by migrating or synthesizing markdown template bodies for them on load.

## Rendering Architecture

Add a new localized rendering module, for example:

- `Sources/NotesCurator/TemplateRendering.swift`

Responsibilities:

- parse front matter
- validate allowed fields and tokens
- infer requested content blocks
- render markdown from structured data
- expose template-validation errors suitable for the UI

Optionally add:

- `Sources/NotesCurator/TemplatePreviewSamples.swift`

Responsibilities:

- provide named sample datasets for content-template previews

## Error Handling

### Template Authoring Errors

Invalid templates should fail safely inside `Template Library`.

Expected behaviors:

- invalid front matter shows an error
- unsupported token shows an error
- unclosed control block shows an error
- invalid template disables save
- invalid template preview never updates the saved template definition

### Draft Safety During Regeneration

If the current editable draft contains unsaved or user-modified content, regeneration must show a confirmation before replacement.

Suggested confirmation:

- `This will replace the current draft content with a new result generated from the selected template.`

### Missing Template Safety

If a draft references a content template that was later deleted:

- the draft remains openable
- the existing `editorDocument` remains usable
- the UI shows that the bound template is missing
- regeneration is blocked until the user selects an existing template

### Preview and Export Safety

Preview and export should depend on already-rendered draft content, not on compiling arbitrary content-template source at the last possible step.

## Testing Strategy

The first release should add coverage in four layers.

### 1. Template Parser / Renderer Tests

Add tests for:

- front matter parsing
- scalar interpolation
- `if` blocks
- `each` blocks
- unsupported token failures
- malformed block failures
- structurally different templates producing different markdown output from the same structured input

### 2. Processing Tests

Add tests ensuring:

- content template metadata influences provider request guidance
- local markdown rendering is used to populate `editorDocument`
- provider-produced freeform markdown is not the final source of truth

### 3. AppModel Tests

Add tests for:

- saving user content templates with markdown bodies
- selecting a different content template on an existing draft without auto-regenerating
- explicitly regenerating with a different template
- safe behavior when a referenced template is missing

### 4. View Tests

Add tests or snapshot-equivalent assertions for:

- `New Note` exposing template selection only
- `Template Library` exposing content-template editing controls
- `Edit` surfacing a regeneration affordance rather than inline template editing

## Out of Scope for V1

- LaTeX content templates
- user-authored visual-theme templates with full style-body editing
- full markdown live-preview parity across every export target
- template sharing, import, or marketplace flows
- nested template composition
- arbitrary helper functions or scripting inside templates
- simultaneous inline template editing from `Edit`

## Success Criteria

The first release succeeds if:

- users can create and edit content templates in `Template Library`
- different templates produce obviously different document structures
- `New Note` remains simple and selection-focused
- `Edit` remains draft-focused and requires explicit regeneration
- preview and export stay stable
- invalid templates are contained to authoring workflows

## Recommended Implementation Order

1. extend the template model and persistence shape
2. add the markdown-template parser and renderer
3. migrate or synthesize system content templates into markdown-template definitions
4. connect processing to local template-based markdown rendering
5. build `Template Library` editing UI and preview
6. add `Edit`-page content-template switching and explicit regeneration
7. update tests across renderer, processing, model, and UI
