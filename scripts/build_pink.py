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
       ('Config', 'ModeDetector', 'Selection', 'Prediction', 'Overlay', 'Runtime', 'ShotAdapter', 'Session', 'Bootstrap')},
}
WEAPON_MODULES = {name: ROOT / f'src/pink_weapon/{name}.luau' for name in
                  ('WeaponSettings', 'WeaponProfiles', 'ClientController', 'ServerController',
                   'Spread', 'ProjectileTracker', 'WeaponManager', 'NativeVerification')}
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
        '-- SEDWARE v4 | validated weapon-profile and muzzle APIs. Edit Config below; X/Y are seconds.',
        '-- The dot shows the observed part, never the predicted aim point.',
        '-- Camera stays free. Public client APIs only; no weapon integration for Da Hood.',
        'local function bootTraceback(problem)',
        ' local message=tostring(problem)',
        ' local available,traceback=pcall(function() return debug and debug.traceback end)',
        ' if available and type(traceback)=="function" then local ok,trace=pcall(traceback,message,2);if ok then return trace end end',
        ' return message',
        'end',
        'local function bootLog(phase,status,detail)',
        ' local logger=if status=="FAIL" and type(warn)=="function" then warn elseif type(print)=="function" then print else warn',
        ' if type(logger)=="function" then pcall(logger,"[SEDWARE]["..phase.."]["..status.."] "..tostring(detail)) end',
        'end',
        'bootLog("Execution","START","SEDWARE v4 payload began execution; LockKey normalization and owned-weapon APIs enabled")',
        'local Config',
        'local configBuilt,headerError=xpcall(function() Config = '+ config_literal+' end,bootTraceback)',
        'if configBuilt then headerError=nil else bootLog("Configuration","FAIL",headerError) end',
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
        'local built,API=xpcall(function()',
        ' return loadModule("Bootstrap").new(Config,loadModule,{'+', '.join(json.dumps(name) for name in MODULES)+'},headerError)',
        'end,bootTraceback)',
        'if not built then',
        ' bootLog("Modules","FAIL",API)',
        ' local problem=tostring(API)',
        ' local shown,issue=pcall(function()',
        '  local players=game:GetService("Players")',
        '  local player=players.LocalPlayer',
        '  return loadModule("Overlay").showFailure(player and player:FindFirstChild("PlayerGui"),"Modules: "..problem)',
        ' end)',
        ' if not shown then bootLog("FailureNotification","FAIL",issue) end',
        ' return {compatibility={ready=false,missing={tostring(API)}},error=tostring(API)}',
        'end',
        'if not PINK_DOT_NO_AUTOSTART then',
        ' local started,problem=xpcall(function() return API.tryInit() end,bootTraceback)',
        ' if not started then',
        '  bootLog("AutoInit","FAIL",problem)',
        '  local notified,issue=pcall(function() loadModule("Session").notifyFailure(API.compatibility,problem) end)',
        '  if not notified then bootLog("FailureNotification","FAIL",issue) end',
        ' end',
        'else bootLog("AutoInit","SKIPPED","PINK_DOT_NO_AUTOSTART=true; call API.init() to start") end',
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
        modules,_=item(storage,'Folder','SEDWAREWeaponModules')
        for name,path in WEAPON_MODULES.items():
            code(modules,'ModuleScript',name,path)
        code(scripts,'LocalScript','SEDWAREWeaponClient',ROOT/'src/pink_demo/Probe.client.luau')
        servers,_=item(document,'ServerScriptService','ServerScriptService')
        code(servers,'Script','SEDWAREWeaponServer',ROOT/'src/pink_demo/Probe.server.luau')
    else:
        code(scripts,'LocalScript','PinkDotLock',source_path)
    item(document,'Players','Players');item(document,'Lighting','Lighting')
    ET.indent(document,space='  ')
    output=ROOT/('build/PinkDotLockTest.rbxlx' if demo else 'build/PinkDotLock.rbxlx')
    ET.ElementTree(document).write(output,encoding='utf-8',xml_declaration=True)
    loaded=ET.parse(output).findall('.//ProtectedString[@name="Source"]')
    expected=[source_path]+([*WEAPON_MODULES.values(), ROOT/'src/pink_demo/Probe.client.luau',
                            ROOT/'src/pink_demo/Probe.server.luau'] if demo else [])
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
