#!/usr/bin/env python3
"""Build a self-contained Studio place from source, without Rojo dependencies.

XML source is escaped by ElementTree; no source substitution or network access.
This packages the prototype. It does not execute the Roblox engine.
"""
from pathlib import Path
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]


def build(output: Path) -> None:
    document = ET.Element("roblox", version="4")
    ET.SubElement(document, "External").text = "null"
    ET.SubElement(document, "External").text = "nil"
    sequence = 0

    def instance(parent, class_name, name, source=None):
        nonlocal sequence
        sequence += 1
        element = ET.SubElement(parent, "Item", {"class": class_name, "referent": f"RBX{sequence}"})
        properties = ET.SubElement(element, "Properties")
        ET.SubElement(properties, "string", name="Name").text = name
        if source is not None:
            ET.SubElement(properties, "ProtectedString", name="Source").text = source
        return element

    def scripts(parent, directory):
        files = sorted(directory.glob("*.luau"))
        if not files:
            raise RuntimeError(f"No scripts in {directory}")
        for path in files:
            if path.name.endswith(".server.luau"):
                cls, name = "Script", path.name.removesuffix(".server.luau")
            elif path.name.endswith(".client.luau"):
                cls, name = "LocalScript", path.name.removesuffix(".client.luau")
            else:
                cls, name = "ModuleScript", path.stem
            instance(parent, cls, name, path.read_text(encoding="utf-8"))

    workspace = instance(document, "Workspace", "Workspace")
    properties = workspace.find("Properties")
    ET.SubElement(properties, "float", name="Gravity").text = "196.2"
    replicated = instance(document, "ReplicatedStorage", "ReplicatedStorage")
    scripts(instance(replicated, "Folder", "AimLab"), ROOT / "src/shared")
    server = instance(document, "ServerScriptService", "ServerScriptService")
    scripts(instance(server, "Folder", "AimLabServer"), ROOT / "src/server")
    starter = instance(document, "StarterPlayer", "StarterPlayer")
    player_scripts = instance(starter, "StarterPlayerScripts", "StarterPlayerScripts")
    scripts(instance(player_scripts, "Folder", "AimLabClient"), ROOT / "src/client")
    instance(document, "Players", "Players")
    instance(document, "Lighting", "Lighting")
    output.parent.mkdir(parents=True, exist_ok=True)
    ET.indent(document, space="  ")
    ET.ElementTree(document).write(output, encoding="utf-8", xml_declaration=True)
    # Ensure the bundled source equals the actual files, including XML escaping.
    loaded = ET.parse(output)
    bundled = [n.text for n in loaded.findall(".//ProtectedString[@name='Source']")]
    sources = [p.read_text(encoding="utf-8") for directory in ("shared", "server", "client")
               for p in sorted((ROOT / "src" / directory).rglob("*.luau"))]
    assert sorted(bundled) == sorted(sources), "Source round-trip mismatch"
    print(f"Bundled {len(sources)} Luau scripts: {output}")


if __name__ == "__main__":
    build(ROOT / "build/AimLab.rbxlx")
