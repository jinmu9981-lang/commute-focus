import fs from 'node:fs';
import path from 'node:path';
import Parser from 'web-tree-sitter';

const root = path.resolve(import.meta.dirname, '..');
await Parser.init();
const parser = new Parser();
parser.setLanguage(await Parser.Language.load(path.join(root, 'node_modules/tree-sitter-wasms/out/tree-sitter-swift.wasm')));
function walk(dir) {
  return fs.readdirSync(path.join(root, dir), { withFileTypes: true }).flatMap(entry =>
    entry.isDirectory() ? walk(`${dir}/${entry.name}`) : [`${dir}/${entry.name}`]);
}
const files = [...walk('CommuteFocus'), ...walk('CommuteFocusTests')].filter(file => file.endsWith('.swift'));
let errors = 0;
for (const file of files) {
  // This grammar predates Swift macros. Parse the surrounding expression as an
  // ordinary identifier; only Xcode can validate/expand #Predicate itself.
  const source = fs.readFileSync(path.join(root, file), 'utf8').replaceAll('#Predicate', ' Predicate');
  const tree = parser.parse(source);
  function visit(node) {
    if (node.type === 'ERROR' || node.isMissing()) {
      console.error(`${file}:${node.startPosition.row + 1}:${node.startPosition.column + 1}: ${node.type} ${node.text.slice(0, 100)}`);
      errors++;
    }
    for (const child of node.children) visit(child);
  }
  visit(tree.rootNode);
  tree.delete();
}
parser.delete();
if (errors) process.exitCode = 1;
else console.log(`PASS: Swift grammar parsed ${files.length} files (#Predicate expansion excluded). No type checking or SDK compilation was performed.`);
