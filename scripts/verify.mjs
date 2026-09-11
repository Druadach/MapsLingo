import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFile, readdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const version = (await readFile(path.join(root, 'VERSION'), 'utf8')).trim();
assert.match(version, /^\d+\.\d+\.\d+$/);
const digest = data => createHash('sha256').update(data).digest('hex');
const cString = (data, offset, length = data.length - offset) =>
  data.subarray(offset, offset + length).toString('utf8').split('\0')[0];
const decodeVersion = value => [value >>> 16, (value >>> 8) & 255, value & 255].join('.');

function verifySignature(data, signature) {
  const blob = data.subarray(signature.offset, signature.offset + signature.size);
  assert.equal(blob.length, signature.size);
  assert.equal(blob.readUInt32BE(0), 0xfade0cc0);
  assert.ok(blob.readUInt32BE(4) <= blob.length);
  const directories = [];
  for (let index = 0; index < blob.readUInt32BE(8); index++) {
    const slot = blob.readUInt32BE(12 + index * 8);
    const offset = blob.readUInt32BE(16 + index * 8);
    if (blob.readUInt32BE(offset) !== 0xfade0c02) continue;
    const directory = blob.subarray(offset, offset + blob.readUInt32BE(offset + 4));
    const hashOffset = directory.readUInt32BE(16);
    const count = directory.readUInt32BE(28);
    const limit = directory.readUInt32BE(32);
    const pageSize = 2 ** directory[39];
    assert.ok(directory.readUInt32BE(12) & 2, 'Expected an ad-hoc signature');
    assert.equal(directory[36], 32);
    assert.equal(directory[37], 2, 'Expected SHA-256 signing');
    assert.equal(limit, signature.offset);
    assert.equal(count, Math.ceil(limit / pageSize));
    for (let page = 0; page < count; page++) {
      const actual = digest(data.subarray(page * pageSize, Math.min((page + 1) * pageSize, limit)));
      const expected = directory.subarray(hashOffset + page * 32, hashOffset + (page + 1) * 32).toString('hex');
      assert.equal(actual, expected, 'Code signature page mismatch');
    }
    directories.push({ slot, pages: count, pageSize });
  }
  assert.ok(directories.some(directory => directory.slot === 0));
  return directories;
}

async function verifyArtifact(name) {
  const filename = name + '-' + version + '.dylib';
  const fat = await readFile(path.join(root, 'dist', filename));
  assert.equal(fat.readUInt32BE(0), 0xcafebabe);
  assert.equal(fat.readUInt32BE(4), 2);
  const slices = [];
  for (let index = 0; index < 2; index++) {
    const entry = 8 + index * 20;
    const cpuType = fat.readUInt32BE(entry);
    const subtype = fat.readUInt32BE(entry + 4);
    const offset = fat.readUInt32BE(entry + 8);
    const size = fat.readUInt32BE(entry + 12);
    const architecture = subtype === 0x80000002 ? 'arm64e' : 'arm64';
    assert.equal(cpuType, 0x100000c);
    assert.equal(subtype, architecture === 'arm64e' ? 0x80000002 : 0);
    assert.equal(offset % (2 ** fat.readUInt32BE(entry + 16)), 0);
    const data = fat.subarray(offset, offset + size);
    assert.equal(data.length, size);
    const thin = await readFile(path.join(root, 'build', version, architecture, filename));
    assert.ok(data.equals(thin), 'Universal slice differs from its thin build');
    assert.equal(data.readUInt32LE(0), 0xfeedfacf);
    assert.equal(data.readUInt32LE(8), subtype);
    assert.equal(data.readUInt32LE(12), 6);
    let cursor = 32;
    let uuid;
    let minimumOS;
    let sdk;
    let signature;
    let symbols;
    let installName;
    let dylibVersion;
    const commands = [];
    const sections = [];
    const dependencies = [];
    for (let commandIndex = 0; commandIndex < data.readUInt32LE(16); commandIndex++) {
      const command = data.readUInt32LE(cursor);
      const commandSize = data.readUInt32LE(cursor + 4);
      assert.ok(commandSize >= 8 && cursor + commandSize <= 32 + data.readUInt32LE(20));
      commands.push(command);
      if (command === 0x19) {
        for (let sectionIndex = 0; sectionIndex < data.readUInt32LE(cursor + 64); sectionIndex++) {
          const sectionOffset = cursor + 72 + sectionIndex * 80;
          sections.push({ name: cString(data, sectionOffset, 16), size: Number(data.readBigUInt64LE(sectionOffset + 40)) });
        }
      }
      if ([0xc, 0x80000018, 0x8000001f].includes(command)) {
        dependencies.push(cString(data, cursor + data.readUInt32LE(cursor + 8)));
      }
      if (command === 0xd) {
        installName = cString(data, cursor + data.readUInt32LE(cursor + 8));
        dylibVersion = decodeVersion(data.readUInt32LE(cursor + 16));
      }
      if (command === 0x1b) {
        const hex = data.subarray(cursor + 8, cursor + 24).toString('hex');
        uuid = [hex.slice(0, 8), hex.slice(8, 12), hex.slice(12, 16), hex.slice(16, 20), hex.slice(20)].join('-');
      }
      if (command === 0x32) {
        assert.equal(data.readUInt32LE(cursor + 8), 2);
        minimumOS = decodeVersion(data.readUInt32LE(cursor + 12));
        sdk = decodeVersion(data.readUInt32LE(cursor + 16));
      }
      if (command === 2) {
        symbols = { offset: data.readUInt32LE(cursor + 8), count: data.readUInt32LE(cursor + 12),
          strings: data.readUInt32LE(cursor + 16) };
      }
      if (command === 0x1d) {
        signature = { offset: data.readUInt32LE(cursor + 8), size: data.readUInt32LE(cursor + 12) };
      }
      cursor += commandSize;
    }
    assert.equal(cursor, 32 + data.readUInt32LE(20));
    assert.ok(uuid && symbols && signature);
    assert.equal(installName, '@rpath/' + filename);
    assert.equal(dylibVersion, version);
    assert.equal(minimumOS, '15.0.0');
    assert.ok(commands.includes(0x80000022), 'Expected classic dyld metadata');
    assert.ok(!commands.includes(0x80000034), 'Unexpected chained fixups');
    assert.ok(!sections.some(section => section.name === '__cfstring'), 'Static CFString regression');
    const staticObjCSections = ['__objc_classlist', '__objc_nlclslist', '__objc_catlist', '__objc_nlcatlist', '__objc_protolist'];
    assert.ok(!sections.some(section => staticObjCSections.includes(section.name) && section.size > 0),
      'Static Objective-C registration metadata regression');
    assert.ok(sections.some(section => ['__mod_init_func', '__init_offsets'].includes(section.name) && section.size > 0));
    const imports = [];
    for (let symbolIndex = 0; symbolIndex < symbols.count; symbolIndex++) {
      const symbolOffset = symbols.offset + symbolIndex * 16;
      if ((data[symbolOffset + 4] & 0x0e) === 0) {
        imports.push(cString(data, symbols.strings + data.readUInt32LE(symbolOffset)));
      }
    }
    assert.ok(!imports.some(symbol => /CFConstantStringClassReference|CFStringMakeConstantString|MSHook|method_exchangeImplementations|method_setImplementation|class_replaceMethod/.test(symbol)));
    assert.ok(imports.includes('_CFStringCreateWithCString'));
    assert.ok(imports.includes('_CFStringGetCString'));
    const expectedDependencies = ['/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation', '/usr/lib/libSystem.B.dylib'];
    if (name === 'MapsLingo') {
      for (const symbol of ['_objc_allocateClassPair', '_objc_registerClassPair', '_objc_disposeClassPair',
        '_class_addMethod', '_class_addProtocol', '_objc_getProtocol', '_protocol_getMethodDescription']) {
        assert.ok(imports.includes(symbol), 'Missing runtime callback registration: ' + symbol);
      }
      expectedDependencies.push('/System/Library/Frameworks/Foundation.framework/Foundation',
        '/System/Library/Frameworks/UIKit.framework/UIKit', '/usr/lib/libobjc.A.dylib');
    } else {
      assert.ok(!imports.some(symbol => symbol.startsWith('_objc_')));
    }
    assert.deepEqual(dependencies.sort(), expectedDependencies.sort());
    slices.push({ architecture, size, uuid, minimumOS, sdk, dependencies,
      staticCFStrings: false, staticObjCRegistrationMetadata: false, signatures: verifySignature(data, signature) });
  }
  assert.deepEqual(slices.map(slice => slice.architecture).sort(), ['arm64', 'arm64e']);
  return { filename, size: fat.length, sha256: digest(fat), slices };
}

const sourceFiles = ['build.sh', 'VERSION', ...(await readdir(path.join(root, 'src'))).sort().map(name => 'src/' + name)];
const sources = [];
for (const filename of sourceFiles) {
  const data = await readFile(path.join(root, filename));
  const text = data.toString('utf8');
  assert.ok(!/[ \t]+\r?$/m.test(text), filename + ': trailing whitespace');
  if (/\.[cmh]$/.test(filename)) {
    assert.ok(!/\bCFSTR\s*\(|(^|[\s=(,])@"/m.test(text), filename + ': static Objective-C/CF string literal');
    assert.ok(!/@(interface|implementation|protocol)\b/.test(text), filename + ': static Objective-C declaration');
  }
  sources.push({ filename, sha256: digest(data) });
}
const artifacts = [];
for (const name of ['MapsLingo', 'MapsLingoRestore']) artifacts.push(await verifyArtifact(name));
const report = { version, onDeviceVerified: false, sources, artifacts };
await writeFile(path.join(root, 'dist', 'VERIFICATION-' + version + '.json'), JSON.stringify(report, null, 2) + '\n');
for (const artifact of artifacts) console.log(artifact.filename + '  SHA-256: ' + artifact.sha256);
console.log('Verified both architectures, dependencies, runtime-only class registration, no static CFStrings, and every signed code page.');
console.log('These checks do not establish on-device stability or language behavior.');
