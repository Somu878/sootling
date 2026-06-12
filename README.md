# Sootling

Sootling is a macOS menu bar pet that turns AI usage into estimated energy and carbon impact. The pet — **Wattson**, a little watt-detective — reacts in realtime to every chat it traces: it sparkles for near-free prompts, coughs out soot puffs for heavier ones, and gets dizzy after token-monster prompts, each with a one-liner like `+21g — tell the GPUs I'm sorry`. Click it for the running carbon estimate and equivalents.

The app tracks exact token counts where local tools expose them, and estimated counts where they do not:

- Claude Code: `~/.claude/projects/**/*.jsonl`
- Codex CLI: `~/.codex/sessions/**/*.jsonl`
- Gemini CLI: `~/.gemini/tmp/**/*.{json,jsonl,log}` with a tolerant parser while the exact schema settles
- OpenCode: `~/.local/share/opencode/storage/message/**/*.json` (whole-file parse; messages dedupe by id)
- Browser chats: `chatgpt.com`, `claude.ai`, and `gemini.google.com` through the companion Chromium extension

Native desktop chat apps (Claude Desktop, ChatGPT for Mac) keep no local token logs — tracing them would require a TLS proxy, so they are deferred.

The app is a native SwiftUI menu bar process with an always-on-top transparent `NSPanel` pet. It stores usage metadata, file offsets, and cumulative Codex token snapshots in SQLite under Application Support.

Sootling does not store prompt or response text. CLI parsers read token usage metadata from local logs. The browser extension estimates token counts inside the page and sends only counts, source/model metadata, and timestamps to the Mac app.

## Run

```sh
cd /Users/somukandula/workspace/sootling
swift run Sootling
```

Open the package in Xcode with:

```sh
open Package.swift
```

The SwiftPM executable sets `NSApplication` to accessory mode at runtime. The bundled `Sootling/App/Info.plist` contains the app-bundle settings to reuse when this is wrapped into a signed `.app`.

## Test

```sh
cd /Users/somukandula/workspace/sootling
swift test
```

## Browser Chat Test

1. Run Sootling and open Settings.
2. Copy the Browser bridge port and secret.
3. In a Chromium-family browser, load `/Users/somukandula/workspace/sootling/extension` as an unpacked extension.
4. Open the extension options page and paste the port and secret.
5. Send a message on `chatgpt.com`, `claude.ai`, or `gemini.google.com`.

The pet should react as messages appear. Browser counts are estimates based on visible text length.

## What is implemented

- Realtime ingest: `FSEventStream` per log root (sub-second reactions) with a slow polling safety net; incremental tail parsing with persisted byte offsets.
- Claude Code, Codex CLI, OpenCode, and tolerant Gemini CLI parsers.
- EcoLogits-inspired LLM inference engine with min/mean/max ranges.
- Static model registry JSON with common OpenAI, Anthropic, and Gemini model aliases plus conservative fallback.
- SQLite event history and daily totals.
- SwiftUI menu bar popover, settings, equivalents, and a floating pet overlay.
- Optional full-screen smoke: each prompt fogs the display in proportion to its CO₂e and fades over ~5s. Click-through, pauses rendering when clear, toggleable in Settings → Pet.
- Localhost browser bridge plus Chrome MV3 extension scaffold for ChatGPT, Claude, and Gemini web chats.

## Notes

The carbon numbers are estimates, not measurements. See [docs/methodology.md](docs/methodology.md) for assumptions, formulas, and attribution.
