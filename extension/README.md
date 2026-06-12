# Sootling Browser Extension

M4 scaffold for Chromium-family browsers. The extension estimates tokens from visible chat text and sends usage events to the macOS app over localhost.

The Mac app now starts the app-side loopback bridge. To test it:

1. Open Sootling Settings.
2. Copy the Browser bridge port and secret.
3. Load this folder as an unpacked extension in Chrome, Arc, Brave, or Edge.
4. Open the extension options page and paste the port and secret.
5. Visit `chatgpt.com`, `claude.ai`, or `gemini.google.com`.

Privacy boundary: page text is used locally inside the extension only to estimate token counts. Sootling receives token counts, source/model metadata, and timestamps; it does not receive or store browser prompt text.
