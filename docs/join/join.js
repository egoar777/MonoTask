/* Invitation codes stay in the fragment. No analytics, network validation or automatic app launch. */
(function () {
  'use strict';
  function parseCode(input) {
    let value = input.trim();
    if (!/^[0-9a-f]{32}$/i.test(value)) {
      try {
        const url = new URL(value);
        if (url.username || url.password || url.port) return null;
        if (url.protocol === 'https:' && url.hostname === 'egoar777.github.io' &&
            url.pathname === '/MonoTask/join/' && !url.search) value = url.hash.slice(1);
        else if (url.protocol === 'com.monotask.ios:' && url.hostname === 'join') value = url.searchParams.get('code') || '';
        else return null;
      } catch { return null; }
    }
    return /^[0-9a-f]{32}$/i.test(value) ? value.toLowerCase() : null;
  }
  function appURL(code) {
    const valid = parseCode(code);
    return valid ? 'com.monotask.ios://join?code=' + valid : null;
  }
  if (typeof module !== 'undefined' && module.exports) { module.exports = { parseCode, appURL }; return; }
  const open = document.getElementById('open');
  const copy = document.getElementById('copy');
  const status = document.getElementById('status');
  const manual = document.getElementById('manual');
  const input = document.getElementById('code');
  let code;
  function update(value) {
    code = parseCode(value);
    open.setAttribute('aria-disabled', String(!code));
    copy.disabled = !code;
    if (code) {
      open.href = appURL(code);
      status.textContent = 'Нажмите, чтобы открыть приглашение в приложении.';
    } else {
      open.removeAttribute('href');
      manual.hidden = false;
      input.readOnly = false;
      status.textContent = 'В приглашении нет корректного кода. Попросите отправителя прислать новую ссылку или вставьте код ниже.';
    }
  }
  update(window.location.href);
  window.addEventListener('hashchange', () => update(window.location.href));
  input.addEventListener('input', () => update(input.value));
  open.addEventListener('click', (event) => {
    if (!code) { event.preventDefault(); return; }
    status.textContent = 'Подтвердите открытие MonoTask. Если ничего не произошло, используйте код приглашения.';
  });
  copy.addEventListener('click', async () => {
    if (!code) return;
    try {
      await navigator.clipboard.writeText(code);
      status.textContent = 'Код скопирован. В MonoTask: Общие списки → Присоединиться.';
    } catch {
      manual.hidden = false;
      input.value = code;
      input.readOnly = true;
      input.focus();
      input.select();
      status.textContent = 'Выделенный код можно скопировать вручную.';
    }
  });
}());
