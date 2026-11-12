"""LAB LOOK TEST kit recolour (Daniele 2026-11-12, test branch lab-look-test only - not for release).

Writes NEW files <kit>/<key>_lab.glb beside the originals (originals never touched) with the material factors of the
26S-structure-A zone sheets (DIRECTOR-PACKAGE/deliveries/26S-structure-A/MATERIALS.md). Geometry is byte-identical:
only the glTF JSON material block changes; the binary buffer (vertices, indices, node transforms) is copied as is and
checked. Runtime slots stay runtime: OS_Light* = player neon rim, OS_Ooze* = goo (AI tint via GooTone), OS_State* =
relay state, OS_Glass = Mats.glass (the game tints it #AECAC7 under --look=lab), OS_Hazard / OS_Conveyor = function cues.

usage: python recolour_kit_lab.py <game>/assets/kit
"""
import json, struct, sys, os, glob, hashlib

def lin(h):
    h = h.lstrip('#'); c = [int(h[i:i+2], 16) / 255 for i in (0, 2, 4)]
    return [round(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4, 5) for x in c]

ZONES = {   # zone: (hex, metallic, roughness)  - MATERIALS.md
    'SHELL': ('#EAE2D1', 0.0, 0.64), 'SEAM': ('#C8CBC0', 0.0, 0.68), 'GLASS': ('#AECAC7', 0.0, 0.12),
    'DETAIL': ('#718A83', 0.6, 0.44), 'RECESS': ('#3D5758', 0.0, 0.78),
}
MAT_ZONE = {   # kit material (Blender name before any ".001") -> zone
    'OS_Plate': 'SHELL',     # deck / platform standing surfaces: continuous warm ivory
    'OS_Shell': 'SHELL',     # vat / relay housings (shroud)
    'OS_Steel': 'DETAIL',    # service hardware, rails, trusses
    'OS_Dark': 'RECESS',     # everything below the standing plane
    'OS_Recess': 'RECESS',
    'OS_Glass': 'GLASS',
}
PIECES = ['Platform_Standard', 'Platform_Pillar', 'Platform_Relay_v3', 'Deck_S', 'Deck_S_Frag_*', 'Pier_Connector',
          'Pier_Angled_*', 'Vat_T1', 'Vat_T2', 'Vat_T3', 'Vat_T4', 'Deck_Conveyor_Belt_v4_*', 'Deck_Ferry_v4_*',
          'Relay_Button_*_v2', 'Relay_Button_*_v3', 'Relay_Ferry_Rail_v3', 'junctions/*']

def read(p):
    b = open(p, 'rb').read()
    assert b[:4] == b'glTF'
    jl = struct.unpack('<I', b[12:16])[0]
    j = json.loads(b[20:20 + jl])
    rest = b[20 + jl:]            # the BIN chunk (header + data), copied byte for byte
    return j, rest

def write(p, j, rest):
    js = json.dumps(j, separators=(',', ':')).encode()
    js += b' ' * ((4 - len(js) % 4) % 4)
    total = 12 + 8 + len(js) + len(rest)
    open(p, 'wb').write(b'glTF' + struct.pack('<II', 2, total) + struct.pack('<I', len(js)) + b'JSON' + js + rest)

def main(kit):
    out = []
    for pat in PIECES:
        for p in sorted(glob.glob(os.path.join(kit, pat + '.glb'))):
            if p.endswith('_lab.glb'):
                continue
            j, rest = read(p)
            changed = []
            for m in j.get('materials', []):
                z = MAT_ZONE.get(m.get('name', '').split('.')[0])
                if not z:
                    continue
                hx, met, rough = ZONES[z]
                pb = m.setdefault('pbrMetallicRoughness', {})
                a = pb.get('baseColorFactor', [1, 1, 1, 1])[3]
                pb['baseColorFactor'] = lin(hx) + [a]
                pb['metallicFactor'] = met
                pb['roughnessFactor'] = rough
                changed.append(m['name'] + '>' + z)
            q = p[:-4] + '_lab.glb'
            write(q, j, rest)
            j2, rest2 = read(q)
            geo_same = rest2 == rest and j2.get('meshes') == j.get('meshes') and j2.get('nodes') == j.get('nodes') \
                and j2.get('accessors') == j.get('accessors')
            assert geo_same, q
            out.append((os.path.relpath(q, kit).replace(os.sep, '/'), hashlib.sha1(rest).hexdigest()[:10], ', '.join(changed)))
    for o in out:
        print('%-40s bin %s  %s' % o)
    print(len(out), 'files written (originals untouched)')

if __name__ == '__main__':
    main(sys.argv[1])
