import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstat, readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { deflateRawSync } from 'node:zlib';
import './verify.mjs';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'VERSION'), 'utf8')).trim();
const digest = data => createHash('sha256').update(data).digest('hex');

function crc32(data) {
  let checksum = 0xffffffff;
  for (const byte of data) {
    checksum ^= byte;
    for (let bit = 0; bit < 8; bit++) checksum = (checksum >>> 1) ^ ((checksum & 1) ? 0xedb88320 : 0);
  }
  return (checksum ^ 0xffffffff) >>> 0;
}

function zipArchive(entries) {
  assert.ok(entries.length < 65536);
  const localParts = [];
  const centralParts = [];
  let offset = 0;
  for (const entry of entries) {
    assert.ok(!entry.name.startsWith('/') && !entry.name.split('/').includes('..'));
    const name = Buffer.from(entry.name, 'utf8');
    const compressed = deflateRawSync(entry.data);
    const checksum = crc32(entry.data);
    const local = Buffer.alloc(30);
    local.writeUInt32LE(0x04034b50, 0);
    local.writeUInt16LE(20, 4);
    local.writeUInt16LE(0x800, 6);
    local.writeUInt16LE(8, 8);
    local.writeUInt16LE(0x21, 12);
    local.writeUInt32LE(checksum, 14);
    local.writeUInt32LE(compressed.length, 18);
    local.writeUInt32LE(entry.data.length, 22);
    local.writeUInt16LE(name.length, 26);
    const central = Buffer.alloc(46);
    central.writeUInt32LE(0x02014b50, 0);
    central.writeUInt16LE(0x0314, 4);
    central.writeUInt16LE(20, 6);
    central.writeUInt16LE(0x800, 8);
    central.writeUInt16LE(8, 10);
    central.writeUInt16LE(0x21, 14);
    central.writeUInt32LE(checksum, 16);
    central.writeUInt32LE(compressed.length, 20);
    central.writeUInt32LE(entry.data.length, 24);
    central.writeUInt16LE(name.length, 28);
    central.writeUInt32LE(((entry.name.endsWith('.sh') ? 0o100755 : 0o100644) << 16) >>> 0, 38);
    central.writeUInt32LE(offset, 42);
    localParts.push(local, name, compressed);
    centralParts.push(central, name);
    offset += local.length + name.length + compressed.length;
  }
  const directory = Buffer.concat(centralParts);
  const end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(entries.length, 8);
  end.writeUInt16LE(entries.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...localParts, directory, end]);
}

async function collectSource(relative) {
  const absolute = path.join(root, relative);
  const info = await lstat(absolute);
  assert.ok(!info.isSymbolicLink(), 'Refusing to package a symlink: ' + relative);
  if (info.isDirectory()) {
    const entries = [];
    for (const name of (await readdir(absolute)).sort()) {
      entries.push(...await collectSource(relative + '/' + name));
    }
    return entries;
  }
  assert.ok(info.isFile());
  return [{ name: relative, data: await readFile(absolute) }];
}

const sourceEntries = [];
for (const name of ['VERSION', 'README.md', 'README.zh.md', 'CHANGELOG.md', 'PUBLISHING.md',
  '.gitignore', '.gitattributes', 'build.sh', 'src', 'scripts', '.github']) {
  sourceEntries.push(...await collectSource(name));
}
try {
  sourceEntries.push(...await collectSource('LICENSE'));
} catch (error) {
  if (error.code !== 'ENOENT') throw error;
  console.log('No LICENSE file is present. Choose a license before publishing as open source.');
}
const artifactNames = ['MapsLingo-' + version + '.dylib', 'MapsLingoRestore-' + version + '.dylib',
  'BUILD-INFO-' + version + '.txt', 'VERIFICATION-' + version + '.json'];
const releaseEntries = [];
for (const name of artifactNames) {
  releaseEntries.push({ name, data: await readFile(path.join(root, 'dist', name)) });
}
for (const name of ['README.md', 'README.zh.md', 'CHANGELOG.md', 'LICENSE']) {
  releaseEntries.push({ name, data: await readFile(path.join(root, name)) });
}
const archives = [
  { name: 'MapsLingo-' + version + '-source.zip', entries: sourceEntries, prefix: 'MapsLingo-' + version + '-source/' },
  { name: 'MapsLingo-' + version + '-release.zip', entries: releaseEntries, prefix: 'MapsLingo-' + version + '/' }
];
const checksums = releaseEntries.filter(entry => artifactNames.includes(entry.name)).map(entry => digest(entry.data) + '  ' + entry.name);
for (const archive of archives) {
  const data = zipArchive(archive.entries.map(entry => ({ name: archive.prefix + entry.name, data: entry.data })));
  await writeFile(path.join(root, 'dist', archive.name), data);
  checksums.push(digest(data) + '  ' + archive.name);
  console.log('Packaged ' + archive.name + ' (' + data.length + ' bytes)');
}
await writeFile(path.join(root, 'dist', 'SHA256SUMS-' + version + '.txt'), checksums.join('\n') + '\n');
