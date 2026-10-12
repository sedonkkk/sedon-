#!/usr/bin/env python3
"""Embed existing Luau modules in one executable LocalScript, without loadstring.

Only require expressions are rewritten into an in-memory, lazy module loader.
Math/Memory implementations are copied unchanged. Source hashes document inputs.
"""
from pathlib import Path
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MODULES = {
    **{name: ROOT / f'src/shared/{name}.luau' for name in
       ('Settings', 'Weapons', 'Latency', 'MotionHistory', 'Ballistics', 'Predictor', 'Geometry', 'Diagnostics')},
    **{name: ROOT / f'src/standalone/{name}.luau' for name in
       ('Configuration', 'Calibration', 'Interface', 'Runtime', 'Session')},
}
IMPORT = re.compile(r'if script then require\(script\.[A-Za-z0-9_.]+\) else require\("(?:\./|\.\./shared/)([A-Za-z0-9_]+)"\)')


def source_bundle(check=False):
    manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in MODULES.items()}
    lines = [
        '--!nonstrict',
        '-- DH PREDICTION LAB — generated standalone version of the modular project.',
        '-- Requires native Roblox client APIs; checks capabilities before creating its GUI.',
        '-- External hosts are not certified; no security bypasses or protected remote calls.',
        '-- Payload makes no external HTTP requests and has no local-file dependencies.',
        '-- Source modules and reproducible generator remain in the original project.',
        '-- Set INITIAL_CONFIGURATION below to a plain configuration table, or import JSON in Settings.',
        'local INITIAL_CONFIGURATION = {targetMode="OwnCharacters", useSimulatedPing=false}',
        'local factories, cache, loading = {}, {}, {}',
        'local function loadModule(name)',
        ' if cache[name] then return cache[name] end',
        ' assert(factories[name], "Unknown embedded module: " .. tostring(name))',
        ' assert(not loading[name], "Circular embedded dependency: " .. name)',
        ' loading[name] = true',
        ' local ok, value = pcall(factories[name], loadModule)',
        ' loading[name] = nil',
        ' if not ok then error("Module " .. name .. ": " .. tostring(value), 2) end',
        ' assert(type(value)=="table", "Embedded module must return a table: " .. name)',
        ' cache[name] = value',
        ' return value',
        'end',
    ]
    for name, path in MODULES.items():
        original = path.read_text(encoding='utf-8')
        def replace(match):
            target = match.group(1)
            if target not in MODULES:
                raise RuntimeError(f'{name}: unknown dependency {target}')
            return f'loadModule("{target}")'
        source = IMPORT.sub(replace, original)
        if re.search(r'\brequire\s*\(', source):
            raise RuntimeError(f'{name}: unrecognized import; update the generator explicitly')
        lines.extend((f'-- BEGIN {name} | sha256 {manifest[name]}', f'factories["{name}"] = function(loadModule)', source.rstrip(), 'end', f'-- END {name}'))
    lines.extend((
        'local Modules = setmetatable({}, {__index=function(_, name) return loadModule(name) end})',
        'local API = {Modules=Modules, getModule=loadModule}',
        'function API.checkCompatibility() return loadModule("Runtime").check() end',
        'function API.tryInit(options)',
        ' local report = API.checkCompatibility()',
        ' API.compatibility = report',
        ' if not report.ready then return nil, report end',
        ' local ok, session = pcall(function() return loadModule("Session").init(options) end)',
        ' if not ok then',
        '  report.ready = false',
        '  table.insert(report.missing, "Inicializacion: " .. tostring(session))',
        '  return nil, report',
        ' end',
        ' API.session = session',
        ' return session, report',
        'end',
        'function API.init(options)',
        ' local session, report = API.tryInit(options)',
        ' if not session then error(loadModule("Runtime").errorMessage(report), 2) end',
        ' return session',
        'end',
        '-- Pure Luau CLI can import the mathematical modules; Roblox auto-starts once.',
        'if game and not DHPREDICTION_NO_AUTOSTART then',
        ' local session, report = API.tryInit({configuration=INITIAL_CONFIGURATION})',
        ' if not session then loadModule("Runtime").reportFailure(loadModule("Runtime").errorMessage(report)) end',
        'end',
        'return API',
        '',
    ))
    output = ROOT / 'DaHoodPrediction.lua'
    rendered = '\n'.join(lines)
    if check:
        if not output.is_file() or output.read_text(encoding='utf-8') != rendered:
            raise RuntimeError('Standalone source differs from its modules. Run python3 scripts/build_standalone.py explicitly to regenerate it; verification does not overwrite source.')
    else:
        output.write_text(rendered, encoding='utf-8')
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/standalone-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'{"Verified" if check else "Embedded"} {len(MODULES)} embedded modules: {output}')
    return output


def studio_place(source_path):
    document = ET.Element('roblox', version='4')
    ET.SubElement(document, 'External').text = 'null'
    ET.SubElement(document, 'External').text = 'nil'
    sequence = 0
    def item(parent, cls, name):
        nonlocal sequence
        sequence += 1
        node = ET.SubElement(parent, 'Item', {'class': cls, 'referent': f'RBX{sequence}'})
        props = ET.SubElement(node, 'Properties')
        ET.SubElement(props, 'string', name='Name').text = name
        return node, props
    def vector(props, name, x, y, z):
        node = ET.SubElement(props, 'Vector3', name=name)
        for axis, value in zip(('X','Y','Z'), (x,y,z)):
            ET.SubElement(node, axis).text = str(value)
    def cframe(props, x,y,z):
        node = ET.SubElement(props, 'CoordinateFrame', name='CFrame')
        for key,value in {'X':x,'Y':y,'Z':z,'R00':1,'R01':0,'R02':0,'R10':0,'R11':1,'R12':0,'R20':0,'R21':0,'R22':1}.items():
            ET.SubElement(node,key).text=str(value)
    world, props = item(document, 'Workspace', 'Workspace')
    ET.SubElement(props, 'float', name='Gravity').text = '196.2'
    floor,props = item(world, 'Part', 'Baseplate')
    ET.SubElement(props,'bool',name='Anchored').text='true'
    # Roblox XML serializes BasePart.Size as lowercase `size`.
    vector(props,'size',400,1,400)
    ET.SubElement(props,'Color3uint8',name='Color3uint8').text=str((16<<16)+(24<<8)+38)
    cframe(props,0,-0.5,0)
    spawn,props = item(world, 'SpawnLocation', 'Spawn')
    ET.SubElement(props,'bool',name='Anchored').text='true'
    ET.SubElement(props,'bool',name='Neutral').text='true'
    ET.SubElement(props,'int',name='Duration').text='0'
    vector(props,'size',8,0.2,8)
    cframe(props,0,0.1,0)
    starter,_=item(document,'StarterPlayer','StarterPlayer')
    scripts,_=item(starter,'StarterPlayerScripts','StarterPlayerScripts')
    code,props=item(scripts,'LocalScript','DaHoodPrediction')
    ET.SubElement(props,'ProtectedString',name='Source').text=source_path.read_text(encoding='utf-8')
    item(document,'Players','Players')
    item(document,'Lighting','Lighting')
    ET.indent(document, space='  ')
    output=ROOT / 'build/DHPredictionLab.rbxlx'
    ET.ElementTree(document).write(output,encoding='utf-8',xml_declaration=True)
    loaded=ET.parse(output).findall('.//ProtectedString[@name="Source"]')
    assert len(loaded)==1 and loaded[0].text==source_path.read_text(encoding='utf-8')
    print(f'Standalone Studio place (one LocalScript): {output}')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='Verify the existing standalone source without overwriting it')
    args = parser.parse_args()
    studio_place(source_bundle(check=args.check))
