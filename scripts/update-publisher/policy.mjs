export const immutableCache = 'public, max-age=31536000, immutable';
export const mutableCache = 'no-cache, max-age=0, must-revalidate';

export function checkExistingObject(existing, file) {
  if (!existing) return false;
  if (existing.ContentLength !== file.size || existing.Metadata?.sha256 !== file.sha256) {
    throw new Error(`Refusing to overwrite published file ${file.name}. Increment the version.`);
  }
  return true;
}

export function checkAdvance(existing, incoming, feedHash) {
  if (!Number.isSafeInteger(incoming.build) || incoming.build < 1) throw new Error('Incoming build must be a positive safe integer.');
  if (!existing) return;
  const build = Number(existing.Metadata?.build);
  if (!Number.isSafeInteger(build) || build < 1) throw new Error('Existing feed has no valid build metadata. Inspect it before publishing.');
  if (incoming.build < build) throw new Error('Refusing to roll the update feed back to an older build.');
  if (incoming.build === build && existing.Metadata?.sha256 !== feedHash) {
    throw new Error('This build is already published with different feed bytes. Increment the version.');
  }
}
