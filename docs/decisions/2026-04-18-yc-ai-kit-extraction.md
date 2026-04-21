# 2026-04-18: Extract Hosted AI Setup Into `YCAIKit`

## Status

Accepted

## Context

`Noter` already had a useful hosted-AI integration layer:

- provider presets
- API key management per provider
- environment-variable fallback
- provider health checks
- staged routing for main/chunk/polish/repair models

That logic was valuable beyond this app, but it lived inside app-specific files and note-generation flows. Reusing it in a new project would have required copying settings UI, provider metadata, and transport code by hand.

## Decision

Create a standalone local Swift package at:

- [YCAPIReuse/YCAIKit](</Users/yichenlin/Desktop/App/Notes/YCAPIReuse/YCAIKit>)

The package extracts the reusable hosted-AI layer into a project-agnostic module with:

- `HostedAIConfiguration`
- `HostedAIService`
- `HostedAIClientFactory`
- `HostedAIClient`
- `HostedAISettingsSection`

The package stays generic and exposes text + JSON generation helpers instead of note-specific `ProviderDraftRequest` and `ProviderDraftResponse` types.

## Why This Shape

- New projects can import one folder instead of reassembling several app files.
- The reusable package keeps the "API key + provider + model routing" concern separate from `Noter`'s document schema.
- The package still mirrors the provider choices and recommended presets already proven inside `Noter`.
- A Swift package is easier to copy, version, and test than a loose group of source files.

## Consequences

- `Noter` keeps its app-specific AI workflow code where it is today.
- Future projects can adopt hosted-AI setup faster by importing `YCAIKit`.
- If `Noter` later wants to fully depend on the extracted package, that can be done as a follow-up refactor instead of being bundled into this first extraction step.
