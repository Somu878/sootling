const portInput = document.querySelector("#port");
const secretInput = document.querySelector("#secret");
const saveButton = document.querySelector("#save");
const statusText = document.querySelector("#status");

async function load() {
  const { sootlingPort, sootlingSecret } = await chrome.storage.local.get([
    "sootlingPort",
    "sootlingSecret"
  ]);
  if (sootlingPort) portInput.value = sootlingPort;
  if (sootlingSecret) secretInput.value = sootlingSecret;
}

async function save() {
  const port = Number.parseInt(portInput.value, 10);
  const secret = secretInput.value.trim();

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    statusText.textContent = "Enter a valid port.";
    return;
  }
  if (!secret) {
    statusText.textContent = "Enter the bridge secret.";
    return;
  }

  await chrome.storage.local.set({
    sootlingPort: port,
    sootlingSecret: secret
  });
  statusText.textContent = "Saved.";
}

saveButton.addEventListener("click", save);
load();

