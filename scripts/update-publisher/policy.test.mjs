import { test } from 'node:test';
import assert from 'node:assert/strict';
import { checkAdvance, checkExistingObject } from './policy.mjs';
import { validateConfig } from '../spaces-config.mjs';

test('same version cannot replace a published download with different bytes', () => {
  const file = { name: 'Nook-0.1.7-arm64.dmg', size: 10, sha256: 'abc' };
  assert.equal(checkExistingObject(null, file), false);
  assert.equal(checkExistingObject({ ContentLength: 10, Metadata: { sha256: 'abc' } }, file), true);
  assert.throws(() => checkExistingObject({ ContentLength: 10, Metadata: { sha256: 'different' } }, file));
  assert.throws(() => checkExistingObject({ ContentLength: 9, Metadata: { sha256: 'abc' } }, file));
});

test('feed cannot roll back or rewrite the same build; identical retry is allowed', () => {
  const previous = { Metadata: { build: '8', sha256: 'abc' } };
  assert.throws(() => checkAdvance(previous, { build: 7 }, 'abc'));
  assert.throws(() => checkAdvance(previous, { build: 8 }, 'different'));
  assert.doesNotThrow(() => checkAdvance(previous, { build: 8 }, 'abc'));
  assert.doesNotThrow(() => checkAdvance(previous, { build: 9 }, 'different'));
  assert.throws(() => checkAdvance({ Metadata: {} }, { build: 9 }, 'abc'));
  for (const build of [0, -1, NaN, Infinity, Number.MAX_SAFE_INTEGER + 1]) {
    assert.throws(() => checkAdvance(null, { build }, 'abc'));
  }
});

test('hosting configuration rejects insecure URLs and prefix traversal', () => {
  const config = { bucket: 'nook-test', region: 'lon1', cdnURL: 'https://nook-test.lon1.cdn.digitaloceanspaces.com', prefix: 'nook' };
  assert.equal(validateConfig(config).feedURL, `${config.cdnURL}/nook/appcast.xml`);
  for (const cdnURL of ['http://example.com', 'https://user:password@example.com', 'https://example.com/?token=secret']) {
    assert.throws(() => validateConfig({ ...config, cdnURL }));
  }
  for (const prefix of ['', '../other-app', 'nook/../other', '/nook']) {
    assert.throws(() => validateConfig({ ...config, prefix }));
  }
});
