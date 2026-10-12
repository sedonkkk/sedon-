#!/usr/bin/env python3
"""Build the separate Cam Lock variant without changing previous projects."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
MODULES = {
    **{name: ROOT / f'src/shared/{name}.luau' for name in ('Settings', 'Latency', 'Ballistics')},
    'MemoryTracker': ROOT / 'src/shared/MotionHistory.luau',
    'PinkConfig': ROOT / 'src/pink/Config.luau',
    'PinkPrediction': ROOT / 'src/pink/Prediction.luau',
    **{name: ROOT / f'src/pink/{name}.luau' for name in ('Selection', 'Runtime', 'Overlay')},
    **{name: ROOT / f'src/cam/{name}.luau' for name in
       ('Config', 'Branding', 'NotificationSystem', 'UI', 'TargetSelector',
        'CameraController', 'PredictionEngine', 'Cleanup', 'Session', 'Bootstrap')},
}
BY_PATH = {path.resolve(): name for name, path in MODULES.items()}
IMPORT = re.compile(r'if script then require\(script\.[A-Za-z0-9_.]+\) else require\("([./A-Za-z0-9_]+)"\)')


def source_bundle(check=False):
    match = re.search(r'Config\.sourceLiteral\s*=\s*\[(=*)\[([\s\S]*?)\]\1\]',
                      MODULES['Config'].read_text(encoding='utf-8'))
    if not match:
        raise RuntimeError('Config.sourceLiteral missing')
    manifest = {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in MODULES.items()}
    lines = [
        '--!nonstrict',
        '-- SEDWARE CAM LOCK v1 | zero-roll yaw/pitch correction; edit Config below.',
        '-- Prediction X/Y are seconds. CamPrediction is a gain: value / 13.80.',
        '-- Enabled=false opens the GUI without controlling the camera.',
        '-- Public client APIs only. No remote weapon integration or bypass.',
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
        'bootLog("CamExecution","START","SEDWARE CAM LOCK v1 payload began execution")',
        'local Config',
        'local configBuilt,headerError=xpcall(function() Config = '+match.group(2)+' end,bootTraceback)',
        'if configBuilt then headerError=nil else bootLog("CamConfiguration","FAIL",headerError) end',
        '-- Embedded from src/cam plus existing shared/Pink modules. No HTTP dependencies.',
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
        def replace(dependency):
            target_path = (path.parent / (dependency.group(1)+'.luau')).resolve()
            target = BY_PATH.get(target_path)
            if not target:
                raise RuntimeError(f'{name}: unembedded dependency {target_path}')
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
        ' bootLog("CamModules","FAIL",API)',
        ' local problem=tostring(API)',
        ' local shown,issue=pcall(function()',
        '  local players=game:GetService("Players")',
        '  local player=players.LocalPlayer',
        '  return loadModule("Overlay").showFailure(player and player:FindFirstChild("PlayerGui"),"Cam modules: "..problem)',
        ' end)',
        ' if not shown then bootLog("FailureNotification","FAIL",issue) end',
        ' return {compatibility={ready=false,missing={problem}},error=problem}',
        'end',
        'if not SEDWARE_CAM_NO_AUTOSTART then',
        ' local started,problem=xpcall(function() return API.tryInit() end,bootTraceback)',
        ' if not started then',
        '  bootLog("CamAutoInit","FAIL",problem)',
        '  local notified,issue=pcall(function() loadModule("Session").notifyFailure(API.compatibility,problem) end)',
        '  if not notified then bootLog("FailureNotification","FAIL",issue) end',
        ' end',
        'else bootLog("CamAutoInit","SKIPPED","SEDWARE_CAM_NO_AUTOSTART=true; call API.init() to start") end',
        'return API', '',
    ))
    output = ROOT / 'SedwareCamLock.lua'
    rendered = '\n'.join(lines)
    if check:
        if not output.is_file() or output.read_text(encoding='utf-8') != rendered:
            raise RuntimeError('SedwareCamLock.lua differs from modules: run python3 scripts/build_cam.py')
    else:
        output.write_text(rendered, encoding='utf-8')
    (ROOT / 'build').mkdir(exist_ok=True)
    (ROOT / 'build/cam-manifest.json').write_text(json.dumps(manifest, indent=2)+'\n', encoding='utf-8')
    print(f'{"Verified" if check else "Embedded"} {len(MODULES)} Cam modules: {output}')
    return output


def studio_place(source_path, check=False):
    document = ET.Element('roblox', version='4')
    ET.SubElement(document, 'External').text = 'null'
    ET.SubElement(document, 'External').text = 'nil'
    sequence = 0
    def item(parent, cls, name):
        nonlocal sequence
        sequence += 1
        node = ET.SubElement(parent, 'Item', {'class': cls, 'referent': f'CAM{sequence}'})
        props = ET.SubElement(node, 'Properties')
        ET.SubElement(props, 'string', name='Name').text = name
        return node, props
    def vector(props, name, x, y, z):
        node = ET.SubElement(props, 'Vector3', name=name)
        for axis, value in zip(('X', 'Y', 'Z'), (x, y, z)):
            ET.SubElement(node, axis).text = str(value)
    def cframe(props, x, y, z):
        node = ET.SubElement(props, 'CoordinateFrame', name='CFrame')
        for key, value in {'X':x,'Y':y,'Z':z,'R00':1,'R01':0,'R02':0,'R10':0,'R11':1,'R12':0,'R20':0,'R21':0,'R22':1}.items():
            ET.SubElement(node, key).text = str(value)
    world, props = item(document, 'Workspace', 'Workspace')
    ET.SubElement(props, 'float', name='Gravity').text = '196.2'
    _, props = item(world, 'Part', 'Baseplate')
    ET.SubElement(props, 'bool', name='Anchored').text = 'true'
    vector(props, 'size', 400, 1, 400); cframe(props, 0, -0.5, 0)
    for i, (x, z) in enumerate(((0, 0), (0, -25))):
        _, props = item(world, 'SpawnLocation', f'Spawn{i+1}')
        ET.SubElement(props, 'bool', name='Anchored').text = 'true'
        ET.SubElement(props, 'bool', name='Neutral').text = 'true'
        ET.SubElement(props, 'int', name='Duration').text = '0'
        vector(props, 'size', 8, 0.2, 8); cframe(props, x, 0.1, z)
    starter, _ = item(document, 'StarterPlayer', 'StarterPlayer')
    scripts, _ = item(starter, 'StarterPlayerScripts', 'StarterPlayerScripts')
    _, props = item(scripts, 'LocalScript', 'SedwareCamLock')
    ET.SubElement(props, 'ProtectedString', name='Source').text = source_path.read_text(encoding='utf-8')
    item(document, 'Players', 'Players'); item(document, 'Lighting', 'Lighting')
    ET.indent(document, space='  ')
    build_path = ROOT / 'build/SedwareCamLock.rbxlx'
    ET.ElementTree(document).write(build_path, encoding='utf-8', xml_declaration=True)
    embedded = ET.parse(build_path).findall('.//ProtectedString[@name="Source"]')
    assert len(embedded) == 1 and embedded[0].text == source_path.read_text(encoding='utf-8')
    output = ROOT / 'studio/SedwareCamLock.rbxlx'
    if check:
        if not output.exists() or output.read_bytes() != build_path.read_bytes():
            raise RuntimeError('Studio Cam place differs: run python3 scripts/build_cam.py')
    else:
        output.parent.mkdir(exist_ok=True)
        output.write_bytes(build_path.read_bytes())
    print(f'Packaged Studio Cam place: {output} (native runtime verification pending)')
    # Native regression runner is distributed in its own place. The ordinary
    # Cam GUI, layout, controls and startup remain unchanged.
    regression = ROOT/'tests/studio/CamRollRegression.client.luau'
    if regression.exists():
        starter_script = document.find('.//Item[@class="LocalScript"]')
        starter_script.find('Properties/string[@name="Name"]').text = 'CamRollRegression'
        starter_script.find('Properties/ProtectedString[@name="Source"]').text = regression.read_text(encoding='utf-8')
        storage, _ = item(document, 'ReplicatedStorage', 'ReplicatedStorage')
        _, module_props = item(storage, 'ModuleScript', 'SedwareCamLock')
        ET.SubElement(module_props, 'ProtectedString', name='Source').text = source_path.read_text(encoding='utf-8')
        ET.indent(document, space='  ')
        regression_build = ROOT/'build/SedwareCamRollTest.rbxlx'
        ET.ElementTree(document).write(regression_build, encoding='utf-8', xml_declaration=True)
        regression_delivery = ROOT/'studio/SedwareCamRollTest.rbxlx'
        embedded = ET.parse(regression_build).findall('.//ProtectedString[@name="Source"]')
        assert sorted(node.text for node in embedded) == sorted([
            source_path.read_text(encoding='utf-8'), regression.read_text(encoding='utf-8')])
        if check:
            if not regression_delivery.exists() or regression_delivery.read_bytes() != regression_build.read_bytes():
                raise RuntimeError('Native Cam roll place differs: run scripts/build_cam.py')
        else:
            regression_delivery.write_bytes(regression_build.read_bytes())
        print(f'Packaged native roll regression place: {regression_delivery} (not executed in this Linux environment)')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    studio_place(source_bundle(args.check), args.check)
