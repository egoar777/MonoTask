const { test } = require('node:test');
const assert = require('node:assert/strict');
const { parseCode, appURL } = require('../../docs/join/join.js');
const code = '0123456789abcdef0123456789abcdef';
test('HTTPS fragment and old app links preserve the code', () => {
  for (const value of [code, code.toUpperCase(), `https://egoar777.github.io/MonoTask/join/#${code}`, `com.monotask.ios://join?code=${code}`]) assert.equal(parseCode(value), code);
  assert.equal(appURL(code), `com.monotask.ios://join?code=${code}`);
});
test('untrusted URLs and malformed codes cannot launch the app', () => {
  for (const value of ['', 'short', 'g'.repeat(32), `https://evil.test/MonoTask/join/#${code}`, `https://egoar777.github.io@evil.test/MonoTask/join/#${code}`, `http://egoar777.github.io/MonoTask/join/#${code}`, `https://egoar777.github.io/MonoTask/join/?code=${code}`, `https://egoar777.github.io/wrong/#${code}`, 'javascript:alert(1)', `<script>${code}</script>`]) {
    assert.equal(parseCode(value), null, value);
    assert.equal(appURL(value), null, value);
  }
});
