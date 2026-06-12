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

## Requirements

- macOS 14 (Sonoma) or later
- Swift 5.9+ toolchain (Xcode 15+ or the standalone command-line tools)

## Run

Clone the repo and run from its root:

```sh
git clone https://github.com/<your-org>/sootling.git
cd sootling
swift run Sootling
```

Or open the package in Xcode and run the `Sootling` scheme:

```sh
open Package.swift
```

The SwiftPM executable sets `NSApplication` to accessory mode at runtime. The bundled `Sootling/App/Info.plist` contains the app-bundle settings to reuse when this is wrapped into a signed `.app`.

## Test

```sh
swift test
```

## Browser Chat Test

1. Run Sootling and open Settings.
2. Copy the Browser bridge port and secret.
3. In a Chromium-family browser, load the `extension/` directory from this repo as an unpacked extension (`chrome://extensions` → enable Developer mode → Load unpacked).
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

## Package a `.app` / DMG

To build a distributable disk image from a release binary:

```sh
./scripts/build-dmg.sh
```

This compiles a release build, assembles `Sootling.app`, ad-hoc signs it, and writes `dist/Sootling-<version>.dmg`. The app icon can be regenerated with `swift scripts/make-icon.swift`.

## Contributing

Contributions are welcome — bug fixes, new parsers, and pet personality all help.

### Project layout

- `Sootling/Ingest/` — log watchers and per-tool usage parsers
- `Sootling/Store/` — SQLite persistence (thread-safe serial queue)
- `Sootling/Pet/` — Wattson's overlay, animations, and quip vocabulary
- `Sootling/UI/` — app model, menu bar, settings, and the stats dashboard
- `extension/` — Chromium MV3 extension for browser chats
- `website/` — Vite + React marketing site
- `scripts/` — icon and DMG packaging tooling
- `Tests/` — XCTest suites

### Workflow

1. Fork and create a feature branch.
2. Make your change and add or update tests where it makes sense.
3. Run `swift build` and `swift test` — both must pass.
4. Open a pull request describing the change and how you verified it.

### Adding a new tool parser

Most "trace another CLI" requests come down to a parser plus a log-source definition:

1. Add a `UsageSource` case in `Sootling/UsageEvent.swift` (and its `displayName`).
2. Implement a parser in `Sootling/Ingest/UsageParsers.swift`, following an existing one. Pick `.tailJSONL` for append-only logs or `.wholeFileJSON` for files rewritten in place.
3. Register the log directory and read mode in `Sootling/Ingest/LogDirectoryWatcher.swift`.
4. Add a fixture-backed test under `Tests/`.

Parsers must read **only** token counts and metadata (model, timestamps, source) — never prompt or response text.

## Notes

The carbon numbers are estimates, not measurements. See [docs/methodology.md](docs/methodology.md) for assumptions, formulas, and attribution.
