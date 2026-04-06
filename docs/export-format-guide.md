# Export Format Guide

## Purpose
Notes Curator now supports a broader set of export targets so users can move between note apps, office suites, and shareable documents without rebuilding the same content by hand.

## Supported Formats

### Markdown (`.md`)
- Best for Obsidian, Logseq, git-based notes, and plain structured editing.
- Keeps headings, bullets, glossary items, and study cards readable in text-first tools.

### Plain Text (`.txt`)
- Best for universal portability and lightweight note transfer.
- Useful when the user wants clean copy/paste into chat apps, terminals, or simple editors.

### HTML (`.html`)
- Best for styled browser output and lightweight publishing.
- Preserves more of the visual template language than plain text formats.

### RTF (`.rtf`)
- Best for rich-text editing in TextEdit, many macOS apps, and office tools with RTF support.
- Good middle ground between plain text and office documents.

### DOCX (`.docx`)
- Best for Microsoft Word workflows.
- Also the most practical bridge for Google Docs, since Google Docs imports DOCX well.

### PDF (`.pdf`)
- Best for fixed layout, print-ready sharing, and high visual consistency.
- Uses the same rendering layer as the in-app visual preview so output stays much closer to what the user sees before exporting.

## Product Guidance
- Use `Markdown` or `TXT` when the user cares most about editable notes.
- Use `HTML`, `RTF`, or `DOCX` when the user wants continued editing with richer formatting.
- Use `PDF` when the user wants a polished final handoff.
- Refer to Google Docs support as `DOCX-compatible` instead of implying a direct Google-native export pipeline.
