# TemplatePack And LaTeX Import Design

Date: 2026-04-08
Status: Approved for implementation planning
Scope: V1 product and architecture design

## Summary

This design introduces a new `TemplatePack` model for Noter and a V1 LaTeX import flow that turns structured LaTeX note templates into editable in-product templates.

The product goal is to support:

- high visual quality
- stable AI output
- user-editable templates

The key decision is to stop treating LaTeX as a runtime authoring format for generation and instead treat it as an import source for high-quality template assets. Imported templates become `TemplatePack` objects inside the app.

## Product Goals

- Let users import a structured LaTeX template and get a usable in-app template draft.
- Preserve the feel of strong editorial and instructional layouts such as box-based study notes.
- Keep AI generation stable by separating content structure from visual rendering.
- Allow end users to edit templates without requiring them to touch LaTeX, raw JSON, or raw markdown DSL.
- Support multiple template styles so users can pick a format that fits their use case.

## Non-Goals For V1

- Full LaTeX compatibility.
- Arbitrary free-form AI schema authoring by end users.
- A full drag-anything visual page builder.
- Exporting imported templates back into complete editable LaTeX source.
- Support for complex LaTeX constructs such as TikZ, math-heavy environments, tables, references, and custom package ecosystems.

## User Decisions Captured

- Priority order:
  - visual ceiling
  - output stability
- Template editing target:
  - end users should be able to edit templates
- Semantic flexibility:
  - users should eventually be able to define custom semantic blocks
- AI contract strictness:
  - core fields should be strict
  - custom or template-specific fields can be left empty when unsupported by the source
- Empty-state handling:
  - template authors control block-specific empty behavior
- V1 importer scope:
  - import should generate visual style, layout, and recommended schema
  - V1 archetypes are:
    - technical note
    - meeting brief
    - formal brief
- Import UX:
  - imported templates first land on an import review page

## Core Design Decision

The system will use a two-layer architecture:

1. Content layer
   - AI generates structured content objects against a controlled schema.
2. Presentation layer
   - the app renders those objects through a user-editable layout and style system.

This means:

- AI does not generate final LaTeX.
- AI does not directly author layout.
- LaTeX is an import source, not the internal template language.

## TemplatePack Model

Each template becomes a `TemplatePack`.

### 1. TemplateIdentity

Stores metadata:

- `id`
- `name`
- `description`
- `category`
- `version`
- `authoringMode`
- `sourceKind`

### 2. RecommendedSchema

Defines the structured content fields the template expects.

Each field contains:

- `key`
- `label`
- `type`
- `requiredLevel`
- `repeatable`
- `maxItems`
- `emptyBehaviorDefaults`
- `aiPriority`

Required levels in V1:

- `coreRequired`
- `templateRequired`
- `preferredOptional`
- `decorative`

Example fields:

- `title`
- `overview`
- `key_points`
- `warnings`
- `code_examples`
- `faq`
- `exercises`
- `action_items`

### 3. LayoutSpec

Defines where schema fields appear in the output.

This is a structured block tree, not raw markdown or LaTeX.

Example blocks:

- `HeroTitle`
- `SummaryBox`
- `KeyBoxList`
- `WarningBoxList`
- `CodeExampleBlock`
- `ExamQuestionBlock`
- `ExerciseBlock`

Each block stores:

- `blockId`
- `blockType`
- `fieldBinding`
- `order`
- `visibilityRules`
- `emptyBehavior`
- `styleVariant`

### 4. StyleKit

Defines visual appearance.

V1 style kit contains:

- tokens
  - accent color
  - surface color
  - border color
  - spacing density
  - title hierarchy
- block variants
  - summary
  - key emphasis
  - warning
  - exam
  - code
  - result

This is the main place where imported LaTeX color and `tcolorbox` styles land.

### 5. BehaviorRules

Defines how template blocks behave across surfaces.

V1 surfaces:

- `authoring`
- `preview`
- `export`

Each block can define:

- `hide`
- `placeholder`
- `softNote`

per surface.

### 6. AIContract

V1 keeps this simple and mostly archetype-driven.

The importer does not invent a fully custom AI prompt policy per template. Instead it stores:

- `archetype`
- `coreFields`
- `optionalFields`
- `doNotInventPolicy`
- `fallbackPolicy`

Actual prompting behavior comes primarily from built-in archetype strategies.

## Archetypes In V1

V1 supports three archetypes:

### Technical Note

Examples:

- teaching notes
- technical lessons
- study guides
- implementation walkthroughs

Likely fields:

- `title`
- `overview`
- `key_points`
- `concept_explanation`
- `warnings`
- `code_examples`
- `faq`
- `exercises`

### Meeting Brief

Examples:

- meeting notes
- action summaries
- decision logs
- project briefings

Likely fields:

- `title`
- `overview`
- `decisions`
- `action_items`
- `risks`
- `open_questions`
- `next_steps`

### Formal Brief

Examples:

- structured memos
- reports
- concise proposals
- status updates

Likely fields:

- `title`
- `overview`
- `background`
- `key_findings`
- `recommendations`
- `risks`
- `appendixNotes`

## LaTeX Import Pipeline

V1 importer should operate as a constrained pipeline, not a general LaTeX interpreter.

### Stage A: Static Extraction

This stage does not depend on AI.

Recognized inputs in V1:

- `\definecolor`
- `\newtcolorbox`
- `\section`
- `\subsection`
- `\subsubsection`
- `\titleformat`
- common spacing and geometry declarations

Outputs a `SourceFingerprint`.

Example extracted signals:

- palette
- heading hierarchy
- box types
- layout density
- recurring section order

### Stage B: Semantic Generalization

This stage uses AI to map concrete document structures into a reusable archetype and recommended schema.

Example mappings:

- "一句话总结" -> `overview`
- "常见坑" -> `warnings`
- "Q&A / 自测" -> `faq` or `exam_questions`
- "小作业" -> `exercises`

This stage outputs:

- inferred archetype
- recommended schema fields
- suggested layout block mapping
- confidence score

### Stage C: TemplatePack Draft Assembly

This stage combines:

- `SourceFingerprint`
- inferred archetype
- recommended schema
- default AI contract for that archetype

into a `TemplatePack` draft that enters review.

## Import Review Page

Imported templates do not go directly into the main builder in V1.

They first land on an Import Review Page containing:

### Imported Type

- inferred archetype
- confidence score

### Visual Extraction

- primary color
- supporting colors
- detected box styles
- heading hierarchy

### Recommended Schema

Show fields grouped as:

- core
- recommended
- optional

### Next-Step Guidance

Explain that the template is now editable and that unsupported fields may stay empty at generation time.

### Primary Actions

- `Use Template`
- `Adjust Type`
- `Cancel Import`

`Adjust Type` is required in V1 as a correction and safety valve.

## Template Builder Lite

V1 builder is intentionally limited.

Supported editing actions:

- reorder blocks
- enable or disable blocks
- rename block titles
- switch style variants
- tweak theme colors
- configure empty behavior

Unsupported in V1:

- arbitrary visual canvas editing
- fully custom field type authoring
- arbitrary custom renderer scripting

## AI Generation Contract

The generation system should be half-strict.

### Core Rules

- `coreRequired` fields must be filled when the source supports them.
- missing core fields trigger repair or fallback.
- `templateRequired` fields may remain empty if the source does not support them strongly.
- `preferredOptional` fields are best-effort.
- decorative fields are template-driven, not AI-driven.

### Output Shape

Each field should carry both value and state.

Possible states in V1:

- `filled`
- `empty`
- `lowConfidence`
- `unsupportedBySource`

This allows:

- empty blocks to hide cleanly
- placeholders in authoring mode
- user-facing confidence hints when needed

## Empty-State Rules

Empty behavior is configurable by template authors per block and per surface.

Recommended V1 default:

- in `authoring`
  - prefer `placeholder`
- in `preview`
  - prefer `hide` or `softNote`
- in `export`
  - prefer `hide`

This preserves template readability while keeping final exports polished.

## Migration From Current System

The current app already contains the rough ingredients needed for this direction:

- content templates
- visual templates
- local rendering
- preview and export paths

V1 should migrate in phases instead of replacing everything at once.

### Phase 1: Introduce TemplatePack As A Wrapper Model

- keep current templates working
- map current content and visual templates into a `TemplatePack` representation
- avoid breaking persistence or current preview/export

### Phase 2: Ship Builder Lite On Top Of Existing Template Capability

- expose block ordering
- expose block toggles
- expose visual variants
- expose empty behavior rules

### Phase 3: Add LaTeX Import

- import into `TemplatePack` draft
- route through import review page
- enter builder lite for refinement

This avoids a rewrite and builds on already-working rendering infrastructure.

## Success Criteria For V1

V1 is successful if:

1. The importer correctly converts supported LaTeX templates into editable `TemplatePack` drafts.
2. Imported templates visually resemble the source style strongly enough to feel recognizable.
3. AI generation remains stable because content generation still targets a controlled schema.
4. End users can edit imported templates without touching LaTeX, JSON, or raw DSL.
5. Preview and export stay aligned through the same rendering model.

## Risks

### Over-ambitious LaTeX support

Risk:

- importer scope expands too early

Mitigation:

- restrict V1 to supported LaTeX subset

### Beautiful but semantically weak templates

Risk:

- importer preserves appearance but produces bad schema suggestions

Mitigation:

- archetype-based schema defaults
- import review page with `Adjust Type`

### Builder complexity grows too quickly

Risk:

- V1 tries to become a full page design tool

Mitigation:

- keep builder lite intentionally constrained

### AI overfitting to imported template details

Risk:

- generation becomes brittle

Mitigation:

- AI contract remains archetype-driven in V1

## Open Questions

- Which existing block types should become first-class reusable variants in the new builder?
- Whether imported templates should support multiple export-specific style overrides in V1 or later.
- Whether schema fields need a richer type system in V1.5 for more advanced educational or checklist-style templates.
- Whether template suitability scoring should surface during normal note creation in V1 or wait until later.

## Recommended V1 Build Order

1. Define `TemplatePack` model and adapters from current templates.
2. Build block and style abstractions needed by preview and export.
3. Build Import Review Page.
4. Build Builder Lite.
5. Build constrained LaTeX extractor.
6. Add archetype inference and recommended schema generation.
7. Wire imported templates into current note creation and edit flows.

## Final Recommendation

Treat LaTeX as a source of premium design patterns, not as the app's long-term generation format.

Internally unify imported and native templates into `TemplatePack = schema + layout + style + behavior`.

Use LaTeX import to bootstrap high-quality editable templates while preserving stable AI generation through controlled archetype-driven schemas.
