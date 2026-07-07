const DEFAULTS = {
  serverUrl: 'http://127.0.0.1:8765',
  apiToken: '',
  voice: 'af_heart',
  speed: 1.0,
  // 0 means unlimited. The old extension default was 4000, which caused long
  // selections to be clipped before they reached Kokoro.
  maxChars: 0
};

function normalizeServerUrl(url) {
  return String(url || DEFAULTS.serverUrl).replace(/\/$/, '');
}

async function getSelectedText(tab, info) {
  return String(await getFullSelectedText(tab, info) || '').trim();
}

chrome.runtime.onInstalled.addListener(async () => {
  chrome.contextMenus.create({
    id: 'kokoro-read-selection',
    title: 'Read with Kokoro',
    contexts: ['selection']
  });

  await migrateLegacySettings();
});

chrome.runtime.onStartup.addListener(migrateLegacySettings);

chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== 'kokoro-read-selection') return;

  const selectedText = await getSelectedText(tab, info);
  if (!selectedText) {
    notify('Kokoro Read Aloud', 'No selected text found.');
    return;
  }

  const settings = await chrome.storage.sync.get(DEFAULTS);
  const maxChars = Number(settings.maxChars || 0);
  const text = maxChars > 0 ? selectedText.slice(0, maxChars) : selectedText;

  try {
    const response = await fetch(`${normalizeServerUrl(settings.serverUrl)}/speak`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(settings.apiToken ? { Authorization: `Bearer ${settings.apiToken}` } : {})
      },
      body: JSON.stringify({
        text,
        voice: settings.voice || DEFAULTS.voice,
        speed: Number(settings.speed || DEFAULTS.speed)
      })
    });

    const body = await response.json().catch(() => ({}));
    if (!response.ok || !body.ok) {
      throw new Error(body.error || `HTTP ${response.status}`);
    }
  } catch (error) {
    notify(
      'Kokoro server not reachable',
      `Start the local server first, then try again. ${error.message || error}`
    );
  }
});

async function getFullSelectedText(tab, info) {
  // Chrome's context-menu info.selectionText can be truncated on long
  // selections. Ask the active page for window.getSelection().toString() so
  // full passages are sent to the local Kokoro server.
  if (tab && tab.id !== undefined && /^https?:|^file:/.test(tab.url || '')) {
    try {
      const results = await chrome.scripting.executeScript({
        target: { tabId: tab.id },
        func: () => window.getSelection().toString()
      });
      const pageSelection = results && results[0] && results[0].result;
      if (pageSelection) return String(pageSelection);
    } catch (_error) {
      // Some pages, like chrome:// pages and the Chrome Web Store, block script
      // injection. Fall back to the context-menu selection text.
    }
  }

  return info.selectionText || '';
}

async function migrateLegacySettings() {
  const settings = await chrome.storage.sync.get({ maxChars: undefined });
  if (settings.maxChars === 4000) {
    await chrome.storage.sync.set({ maxChars: 0 });
  }
}

function notify(title, message) {
  chrome.notifications.create({
    type: 'basic',
    iconUrl: 'icons/icon128.png',
    title,
    message: String(message).slice(0, 250)
  });
}
