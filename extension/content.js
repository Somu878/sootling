const SOOTLING_SENT_ATTR = "data-sootling-seen";

function estimateTokens(text) {
  return Math.max(1, Math.round(text.trim().length / 4));
}

function currentSource() {
  const host = window.location.hostname;
  if (host.includes("claude")) return "claudeWeb";
  if (host.includes("gemini")) return "geminiWeb";
  return "chatgptWeb";
}

async function connectionHint() {
  const { sootlingPort, sootlingSecret } = await chrome.storage.local.get([
    "sootlingPort",
    "sootlingSecret"
  ]);
  if (!sootlingPort || !sootlingSecret) return null;
  return { port: sootlingPort, secret: sootlingSecret };
}

async function sendUsage({ tokensIn, tokensOut }) {
  const hint = await connectionHint();
  if (!hint) return;

  await fetch(`http://127.0.0.1:${hint.port}/usage`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "Authorization": `Bearer ${hint.secret}`
    },
    body: JSON.stringify({
      timestamp: new Date().toISOString(),
      source: currentSource(),
      model: "browser-estimate",
      tokensIn,
      tokensOut,
      cachedInputTokens: 0
    })
  });
}

function roleFor(node) {
  const roleNode = node.closest("[data-message-author-role]");
  const role = roleNode?.getAttribute("data-message-author-role");
  if (role === "user" || role === "assistant") return role;

  const aria = (node.getAttribute("aria-label") || "").toLowerCase();
  if (aria.includes("user")) return "user";
  if (aria.includes("assistant") || aria.includes("claude") || aria.includes("gemini")) {
    return "assistant";
  }
  return "assistant";
}

function scanMessages() {
  const candidates = document.querySelectorAll("main [data-message-author-role], main article, main .message");
  for (const node of candidates) {
    if (node.hasAttribute(SOOTLING_SENT_ATTR)) continue;
    const text = node.textContent || "";
    if (text.trim().length < 8) continue;
    node.setAttribute(SOOTLING_SENT_ATTR, "true");

    const tokens = estimateTokens(text);
    const role = roleFor(node);
    sendUsage({
      tokensIn: role === "user" ? tokens : 0,
      tokensOut: role === "assistant" ? tokens : 0
    }).catch(() => {});
  }
}

const observer = new MutationObserver(scanMessages);
observer.observe(document.documentElement, { childList: true, subtree: true });
scanMessages();
