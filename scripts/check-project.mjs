import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';

const root = path.resolve(import.meta.dirname, '..');
const project = fs.readFileSync(path.join(root, 'CommuteFocus.xcodeproj/project.pbxproj'), 'utf8');
const references = [...project.matchAll(/path = "([^"]+)"; sourceTree = SOURCE_ROOT/g)].map(match => match[1]);
for (const file of references) assert.ok(fs.existsSync(path.join(root, file)), `Missing project file: ${file}`);
function walk(dir) {
  return fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? walk(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
}
const sources = [...walk('CommuteFocus'), ...walk('CommuteFocusTests')].filter(file => file.endsWith('.swift'));
for (const file of sources) assert.ok(references.includes(file), `Unwired Swift source: ${file}`);
const definitions = new Set([...project.matchAll(/^([A-F0-9]{24}) = /gm)].map(match => match[1]));
for (const match of project.matchAll(/\b[A-F0-9]{24}\b/g)) assert.ok(definitions.has(match[0]), `Undefined PBX object: ${match[0]}`);
for (const file of ['CommuteFocus/Info.plist', 'CommuteFocus/PrivacyInfo.xcprivacy', 'CommuteFocus.xcodeproj/project.pbxproj']) {
  execFileSync('plutil', ['-lint', path.join(root, file)], { stdio: 'inherit' });
}
console.log(`PASS: ${sources.length} Swift files wired; ${definitions.size} PBX objects resolved. This is not a Swift compilation.`);
