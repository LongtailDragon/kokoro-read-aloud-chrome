const DEFAULTS = {
  serverUrl: 'http://127.0.0.1:8765',
  apiToken: '',
  voice: 'af_heart',
  speed: 1.0,
  // 0 means unlimited.
  maxChars: 0
};

const fields = {
  serverUrl: document.getElementById('serverUrl'),
  apiToken: document.getElementById('apiToken'),
  voice: document.getElementById('voice'),
  speed: document.getElementById('speed'),
  maxChars: document.getElementById('maxChars')
};
const statusEl = document.getElementById('status');

load();

document.getElementById('save').addEventListener('click', save);
document.getElementById('test').addEventListener('click', testServer);

async function load() {
  const settings = await chrome.storage.sync.get(DEFAULTS);
  fields.serverUrl.value = settings.serverUrl;
  fields.apiToken.value = settings.apiToken;
  fields.voice.value = settings.voice;
  fields.speed.value = settings.speed;
  fields.maxChars.value = settings.maxChars === 4000 ? 0 : settings.maxChars;
}

async function save() {
  const serverUrl = fields.serverUrl.value.trim() || DEFAULTS.serverUrl;
  await chrome.storage.sync.set({
    serverUrl,
    apiToken: fields.apiToken.value.trim(),
    voice: fields.voice.value || DEFAULTS.voice,
    speed: Number(fields.speed.value || DEFAULTS.speed),
    maxChars: Number(fields.maxChars.value || 0)
  });
  setStatus('Saved.');
}

async function testServer() {
  await save();
  try {
    const serverUrl = fields.serverUrl.value.replace(/\/$/, '');
    const headers = fields.apiToken.value.trim()
      ? { Authorization: `Bearer ${fields.apiToken.value.trim()}` }
      : {};
    const response = await fetch(`${serverUrl}/health`, { headers });
    const body = await response.json();
    if (!response.ok || !body.ok) throw new Error(body.error || `HTTP ${response.status}`);
    setStatus(`Server OK. Device: ${body.device}. Voice loaded on first read.`);
  } catch (error) {
    setStatus(`Server test failed: ${error.message || error}`, true);
  }
}

function setStatus(message, isError = false) {
  statusEl.textContent = message;
  statusEl.style.color = isError ? '#b00020' : '#0a7b28';
}
