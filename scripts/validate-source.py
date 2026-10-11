"""Structural/syntax checks only; never a substitute for xcodebuild or device tests."""
from pathlib import Path
import json, plistlib, re, sys, xml.etree.ElementTree as ET

root=Path(__file__).resolve().parents[1]
failures=[]
project=root/'AirPodsTracker.xcodeproj/project.pbxproj'
text=project.read_text(encoding='utf-8')
defined=set(re.findall(r'^\s*([A-F0-9]{24})\s*=\s*\{',text,re.M))
referenced=set(re.findall(r'\b[A-F0-9]{24}\b',text))
for missing in referenced-defined: failures.append('Unresolved project identifier: '+missing)
for source in (root/'AirPodsTracker').rglob('*.swift'):
    if json.dumps(source.relative_to(root).as_posix()) not in text:
        failures.append('Source missing from Xcode project: '+str(source.relative_to(root)))
for test in (root/'AirPodsTrackerTests').glob('*.swift'):
    if json.dumps(test.relative_to(root).as_posix()) not in text: failures.append('Test missing from project: '+test.name)
for path in list(root.rglob('*.plist'))+list(root.rglob('*.xcprivacy')):
    try: plistlib.loads(path.read_bytes())
    except Exception as error: failures.append(f'{path.name}: {error}')
for path in root.rglob('*.xcscheme'):
    try:
        tree=ET.parse(path)
        for ref in tree.findall('.//BuildableReference'):
            if ref.attrib['BlueprintIdentifier'] not in defined: failures.append('Scheme target missing')
    except Exception as error: failures.append(str(error))
for path in root.rglob('Contents.json'):
    try:
        data=json.loads(path.read_text(encoding='utf-8'))
        for entry in data.get('images',[]):
            if entry.get('filename') and not (path.parent/entry['filename']).is_file(): failures.append('Missing image: '+entry['filename'])
    except Exception as error: failures.append(str(error))
syntax='not run (install tree-sitter and tree-sitter-swift)'
try:
    import tree_sitter, tree_sitter_swift
    parser=tree_sitter.Parser(tree_sitter.Language(tree_sitter_swift.language()))
    files=[p for p in root.rglob('*.swift') if '.build' not in p.parts]
    for path in files:
        data=path.read_bytes(); tree=parser.parse(data)
        if tree.root_node.has_error:
            def errors(node):
                if node.type=='ERROR' or node.is_missing:
                    yield node
                else:
                    for child in node.children: yield from errors(child)
            for node in errors(tree.root_node):
                failures.append(f'{path.relative_to(root)}:{node.start_point.row+1}: Swift parse error: '+data[node.start_byte:node.end_byte][:100].decode('utf-8','replace'))
    syntax=f'parsed {len(files)} Swift files (syntax only, no type checking)'
except ImportError: pass
print(json.dumps({'swiftSyntax':syntax,'projectObjects':len(defined),'failures':failures},ensure_ascii=False,indent=2))
sys.exit(1 if failures else 0)
