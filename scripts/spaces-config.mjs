import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

export function validateConfig(value) {
  const { bucket, region, cdnURL, prefix } = value;
  if (!/^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$/.test(bucket ?? '') || !/^[a-z]+[0-9]+$/.test(region ?? '')) {
    throw new Error('Set a valid Spaces bucket and region in distribution/spaces.json.');
  }
  const url = new URL(cdnURL);
  if (url.protocol !== 'https:' || url.username || url.password || url.search || url.hash || url.pathname !== '/') {
    throw new Error('cdnURL must be an HTTPS origin without credentials, path or query.');
  }
  if (!/^[a-zA-Z0-9_-]+(?:\/[a-zA-Z0-9_-]+)*$/.test(prefix ?? '')) {
    throw new Error('Set a non-empty prefix to keep Nook files isolated in the Space.');
  }
  return { bucket, region, cdnURL: url.origin, prefix, feedURL: `${url.origin}/${prefix}/appcast.xml` };
}

export function loadConfig() {
  return validateConfig(JSON.parse(readFileSync(new URL('../distribution/spaces.json', import.meta.url), 'utf8')));
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try { console.log(loadConfig().feedURL); }
  catch (error) { console.error(error.message); process.exitCode = 1; }
}
