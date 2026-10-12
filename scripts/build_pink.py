#!/usr/bin/env python3
"""Reproducibly embed Pink modules; never rewrite DH PREDICTION LAB."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MODULES = {
    **{name: ROOT / f'src/shared/{name}.luau' for name in
       ('Settings', 'Latency', 'MotionHistory', 'Ballistics')},
    **{name: ROOT / f'src/pink/{name}.luau' for name in
       ('Config', 'ModeDetector', 'Selection', 'Prediction', 'Overlay', 'Runtime', 'ShotAdapter', 'Session')},
}
IMPORT = re.compile(r'if script then require\(script\.[A-Za-z0-9_.]+\) else require\("(?:\./|\.\./shared/)([A-Za-z0-9_]+)"\)')


def source_bundle(check=False):
    config_source = MODULES['Config'].read_text(encoding='utf-8')
    match = re.search(r'Config\.sourceLiteral\s*=\s*\[(=*)\[([\s\S]*?)\]\1\]', config_source)
    if not match:
        raise RuntimeError('Config.sourceLiteral missing')
    config_literal = match.group(2).replace('Enum.KeyCode.C', '(Enum and Enum.KeyCode.C or "C")')
    config_literal = re.sub(r'Color3.fromRGB\((\d+),\s*(\d+),\s*(\d+)\)',
        lambda m: f'(Color3 and Color3.fromRGB({m[1]},{m[2]},{m[3]}) or {{R={m[1]}/255,G={m[2]}/255,B={m[3]}/255}})', config_literal)
    manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in MODULES.items()}
    lines = [
        '--!nonstrict',
        '-- PINK DOT LOCK | edit Config here. X/Y and all offsets are seconds.',
        '-- The dot shows the observed part, never the predicted aim point.',
        '-- Camera stays free. Public client APIs only; no weapon integration for Da Hood.',
        'local Config = ' + config_literal,
        '-- Generated from src/pink and existing shared algorithms. No remote dependencies.',
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
        def replace(match):
            target = match.group(1)
            if target not in MODULES:
                raise RuntimeError(f'{name}: unknown dependency {target}')
            return f'loadModule("{target}")'
        source = IMPORT.sub(replace, path.read_text(encoding='utf-8'))
        if re.search(r'\brequire\s*\(', source):
            raise RuntimeError(f'{name}: unrecognized dependency')
        lines.extend((f'-- BEGIN {name} | sha256 {manifest[name]}',
                      f'factories["{name}"] = function(loadModule)', source.rstrip(), 'end', f'-- END {name}'))
    lines.extend((
        'local Modules = setmetatable({}, {__index=function(_, name) return loadModule(name) end})',
        'local API = {Modules=Modules, getModule=loadModule, Config=Config}',
        'function API.checkCompatibility(options) return loadModule("Runtime").check(options or Config) end',
        'function API.tryInit(options)',
        ' local normalized, problem = loadModule("Config").new(options or Config)',
        ' local report = API.checkCompatibility(normalized or Config)',
        ' API.compatibility = report',
        ' if not normalized then report.ready=false;table.insert(report.missing,tostring(problem)) end',
        ' if not report.ready then return nil, report end',
        ' local ok, session = pcall(function() return loadModule("Session").init(normalized,report) end)',
        ' if not ok then report.ready=false;table.insert(report.missing,"Initialization: "..tostring(session));return nil,report end',
        ' API.session=session',
        ' return session, report',
        'end',
        'function API.init(options)',
        ' local session, report=API.tryInit(options)',
        ' if not session then error(loadModule("Runtime").errorMessage(report),2) end',
        ' return session',
        'end',
        'for _, name in {"GetLockedTarget","GetPredictedPosition","GetPrediction","LockTarget","UnlockTarget","IsValidTarget","CreateShotAdapter","SetEnabled","Unload"} do',
        ' API[name]=function(...)',
        '  if not API.session then return nil,"Not initialized" end',
        '  return API.session[name](API.session,...)',
        ' end',
        'end',
        'if game and not PINK_DOT_NO_AUTOSTART then',
        ' local session,report=API.tryInit(Config)',
        ' if not session then loadModule("Session").notifyFailure(report,loadModule("Runtime").errorMessage(report)) end',
        'end',
        'return API', '',
    ))
    output = ROOT / 'PinkDotLock.lua'
    rendered = '\n'.join(lines)
    if check:
        if not output.is_file() or output.read_text(encoding='utf-8') != rendered:
            raise RuntimeError('PinkDotLock.lua differs from its modules: run python3 scripts/build_pink.py')
    else:
        output.write_text(rendered, encoding='utf-8')
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/pink-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
    print(f'{"Verified" if check else "Embedded"} {len(MODULES)} Pink modules: {output}')
    return output


def studio_place(source_path, demo=False):
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
        for axis,value in zip(('X','Y','Z'),(x,y,z)):
            ET.SubElement(node, axis).text=str(value)
    def cframe(props,x,y,z):
        node=ET.SubElement(props,'CoordinateFrame',name='CFrame')
        for key,value in {'X':x,'Y':y,'Z':z,'R00':1,'R01':0,'R02':0,'R10':0,'R11':1,'R12':0,'R20':0,'R21':0,'R22':1}.items():
            ET.SubElement(node,key).text=str(value)
    def code(parent,cls,name,path):
        _,props=item(parent,cls,name)
        ET.SubElement(props,'ProtectedString',name='Source').text=path.read_text(encoding='utf-8')
    world,props=item(document,'Workspace','Workspace')
    ET.SubElement(props,'float',name='Gravity').text='196.2'
    _,props=item(world,'Part','Baseplate')
    ET.SubElement(props,'bool',name='Anchored').text='true'
    vector(props,'size',400,1,400);cframe(props,0,-0.5,0)
    for i,(x,z) in enumerate(((-10,0),(10,-25))):
        _,props=item(world,'SpawnLocation',f'Spawn{i+1}')
        ET.SubElement(props,'bool',name='Anchored').text='true'
        ET.SubElement(props,'bool',name='Neutral').text='true'
        ET.SubElement(props,'int',name='Duration').text='0'
        vector(props,'size',8,0.2,8);cframe(props,x,0.1,z)
    starter,_=item(document,'StarterPlayer','StarterPlayer')
    scripts,_=item(starter,'StarterPlayerScripts','StarterPlayerScripts')
    if demo:
        storage,_=item(document,'ReplicatedStorage','ReplicatedStorage')
        code(storage,'ModuleScript','PinkDotLock',source_path)
        code(scripts,'LocalScript','PinkDotLockProbe',ROOT/'src/pink_demo/Probe.client.luau')
        servers,_=item(document,'ServerScriptService','ServerScriptService')
        code(servers,'Script','PinkDotLockProbe',ROOT/'src/pink_demo/Probe.server.luau')
    else:
        code(scripts,'LocalScript','PinkDotLock',source_path)
    item(document,'Players','Players');item(document,'Lighting','Lighting')
    ET.indent(document,space='  ')
    output=ROOT/('build/PinkDotLockTest.rbxlx' if demo else 'build/PinkDotLock.rbxlx')
    ET.ElementTree(document).write(output,encoding='utf-8',xml_declaration=True)
    loaded=ET.parse(output).findall('.//ProtectedString[@name="Source"]')
    expected=[source_path]+([ROOT/'src/pink_demo/Probe.client.luau',ROOT/'src/pink_demo/Probe.server.luau'] if demo else [])
    assert len(loaded)==len(expected)
    assert sorted(node.text for node in loaded)==sorted(path.read_text(encoding='utf-8') for path in expected)
    print(f'Packaged Studio place: {output} (runtime validation still required)')
    return output


if __name__=='__main__':
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check',action='store_true')
    args=parser.parse_args()
    path=source_bundle(args.check)
    for demo in (False,True):
        output=studio_place(path,demo)
        delivery=ROOT/'studio'/output.name
        if args.check:
            if not delivery.is_file() or delivery.read_bytes()!=output.read_bytes():
                raise RuntimeError(f'{delivery} differs from its sources: regenerate with scripts/build_pink.py')
        else:
            delivery.parent.mkdir(exist_ok=True)
            delivery.write_bytes(output.read_bytes())
