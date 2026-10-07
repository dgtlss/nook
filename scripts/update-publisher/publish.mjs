import { S3Client, HeadObjectCommand, PutObjectCommand } from '@aws-sdk/client-s3';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { readFileSync, mkdirSync, rmSync, writeFileSync } from 'node:fs';
import { resolve, join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { loadConfig } from '../spaces-config.mjs';
import { checkAdvance, checkExistingObject, immutableCache, mutableCache } from './policy.mjs';

const root = fileURLToPath(new URL('../../', import.meta.url));
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');
const missing = error => error.$metadata?.httpStatusCode === 404;

async function publish() {
  if (!process.argv[2]) throw new Error('Pass the completed release directory.');
  const release = resolve(process.argv[2]);
  const config = loadConfig();
  let { SPACES_ACCESS_KEY_ID: accessKeyId, SPACES_SECRET_ACCESS_KEY: secretAccessKey } = process.env;
  if (Boolean(accessKeyId) !== Boolean(secretAccessKey)) throw new Error('Set both Spaces environment variables, or neither to use Keychain.');
  if (!accessKeyId) {
    try {
      ({ accessKeyId, secretAccessKey } = JSON.parse(execFileSync('/usr/bin/swift',
        [join(root, 'tools/spaces-keychain.swift'), 'read'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] })));
    } catch { throw new Error('No publishing credentials available. Run python3 scripts/store-spaces-credentials.py or set both Spaces environment variables locally.'); }
  }
  if (!accessKeyId || !secretAccessKey) throw new Error('Stored publishing credentials are incomplete.');
  // Recheck notarization, code signatures, archive contents and Sparkle signatures.
  execFileSync(join(root, 'scripts/verify-release.sh'), [release], { cwd: root, stdio: 'inherit' });
  const manifest = JSON.parse(readFileSync(join(release, 'verification/update-manifest.json')));
  if (manifest.feedURL !== config.feedURL) throw new Error('Packaged app feed URL differs from the configured Space. Rebuild for the intended feed.');
  const feedFile = manifest.files.find(file => file.name === 'appcast.xml');
  const feedKey = `${config.prefix}/appcast.xml`;
  const client = new S3Client({
    endpoint: `https://${config.region}.digitaloceanspaces.com`, region: 'us-east-1',
    credentials: { accessKeyId, secretAccessKey },
    requestChecksumCalculation: 'WHEN_REQUIRED', responseChecksumValidation: 'WHEN_REQUIRED'
  });
  const origin = `https://${config.bucket}.${config.region}.digitaloceanspaces.com`;
  const head = async key => {
    try { return await client.send(new HeadObjectCommand({ Bucket: config.bucket, Key: key })); }
    catch (error) { if (missing(error)) return null; throw error; }
  };
  const verifyPublic = async (base, key, expected) => {
    const response = await fetch(`${base}/${key}`, { signal: AbortSignal.timeout(120_000), cache: 'no-store' });
    if (!response.ok) throw new Error(`Public download failed: ${response.status} for ${key}`);
    const bytes = Buffer.from(await response.arrayBuffer());
    if (bytes.length !== expected.size || sha256(bytes) !== expected.sha256) {
      throw new Error(`Public download does not match signed local bytes: ${key}`);
    }
  };
  const put = async (key, bytes, { contentType, cache, metadata }) => {
    await client.send(new PutObjectCommand({
      Bucket: config.bucket, Key: key, Body: bytes, ContentLength: bytes.length,
      ContentMD5: createHash('md5').update(bytes).digest('base64'),
      ACL: 'public-read', ContentType: contentType, CacheControl: cache, Metadata: metadata
    }));
  };
  try {
    const previousFeed = await head(feedKey);
    checkAdvance(previousFeed, manifest, feedFile.sha256);
    const prefix = `${config.prefix}/versions/v${manifest.version}`;
    // Immutable downloads first. Verify actual public bytes before advancing metadata.
    for (const file of manifest.files) {
      const key = `${prefix}/${file.name}`;
      if (!checkExistingObject(await head(key), file)) {
        const bytes = readFileSync(join(release, file.name));
        if (bytes.length !== file.size || sha256(bytes) !== file.sha256) throw new Error('Local release changed during publication.');
        const contentType = file.name.endsWith('.dmg') ? 'application/x-apple-diskimage'
          : file.name.endsWith('.zip') ? 'application/zip'
          : file.name.endsWith('.xml') ? 'application/rss+xml' : 'text/plain; charset=utf-8';
        await put(key, bytes, { contentType, cache: immutableCache, metadata: { sha256: file.sha256 } });
      }
      await verifyPublic(origin, key, file);
      await verifyPublic(config.cdnURL, key, file);
      console.log(`Verified ${config.cdnURL}/${key}`);
    }
    // Spaces does not document conditional PUTs. Use one publishing machine;
    // the local lock and second read catch accidental concurrent publications.
    const currentFeed = await head(feedKey);
    if ((currentFeed?.ETag ?? null) !== (previousFeed?.ETag ?? null)) throw new Error('The live feed changed while uploading. Retry against its new state.');
    checkAdvance(currentFeed, manifest, feedFile.sha256);
    const feed = readFileSync(join(release, 'appcast.xml'));
    if (sha256(feed) !== feedFile.sha256) throw new Error('Local feed changed during publication.');
    await put(feedKey, feed, { contentType: 'application/rss+xml', cache: mutableCache,
      metadata: { sha256: feedFile.sha256, build: String(manifest.build), version: manifest.version } });
    await verifyPublic(origin, feedKey, feedFile);
    await verifyPublic(config.cdnURL, feedKey, feedFile);
    const download = manifest.files.find(file => file.name.endsWith('.dmg'));
    const latest = Buffer.from(JSON.stringify({ version: manifest.version, build: manifest.build,
      downloadURL: `${config.cdnURL}/${prefix}/${download.name}`, sha256: download.sha256,
      feedURL: config.feedURL }, null, 2) + '\n');
    await put(`${config.prefix}/latest.json`, latest, { contentType: 'application/json', cache: mutableCache,
      metadata: { sha256: sha256(latest), build: String(manifest.build) } });
    await verifyPublic(config.cdnURL, `${config.prefix}/latest.json`, { size: latest.length, sha256: sha256(latest) });
    writeFileSync(join(release, 'verification/spaces-publication.json'), JSON.stringify({
      version: manifest.version, build: manifest.build, feedURL: config.feedURL,
      downloadURL: `${config.cdnURL}/${prefix}/${download.name}`, publishedAt: new Date().toISOString()
    }, null, 2));
    console.log(`Published signed update feed: ${config.feedURL}`);
  } finally { client.destroy(); }
}

const lock = join(root, 'build/spaces-publish.lock');
let locked = false;
try {
  mkdirSync(join(root, 'build'), { recursive: true });
  mkdirSync(lock); locked = true;
  await publish();
} catch (error) {
  // SDK errors can include request objects; print only their message.
  console.error(error.message); process.exitCode = 1;
} finally { if (locked) rmSync(lock, { recursive: true }); }
