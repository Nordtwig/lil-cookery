"""Generate the low-poly ingredient meshes as glTF, one glb per whole / pieces set.

Run from the repo root:
    blender -b --python tools/blender/gen_items.py -- [--only items|stations|details] [--sheet path.png]

--sheet writes one contact sheet per group (path_items.png, path_stations.png,
path_details.png), each fitted to its group's scale. Look at them before wiring
anything into a scene - that look is the only check that catches orientation.

Every item is built Z-up with its base on z=0 and exported Y-up, so a glb instanced at
the origin of an item scene sits exactly where the old primitive did. Dimensions match
the primitives they replace. Flat shaded, one material per object - Godot tints the
whole tree through Item's material override, so material colour here is only for the
contact sheet. Deterministic: every jitter is seeded.
"""
import math
import random
import sys
from pathlib import Path

import bmesh
import bpy
from mathutils import Matrix, Vector, noise

REPO = Path(__file__).resolve().parents[2]
ITEMS_OUT = REPO / "items" / "models"
STATIONS_OUT = REPO / "stations" / "models"
PLAYER_OUT = REPO / "player" / "models"

_registry = []

## Groups whose entries are parts of one object rather than a set of separate ones.
## A grid cell per part says nothing about whether the assembled figure reads, so
## these render stacked at the origin instead (see contact_sheets).
ASSEMBLED_GROUPS = {"player", "customer"}

## Geometry rendered alongside an assembled group purely for context - the thing it
## stands at, sits on or reaches into - as {group: [(builder, offset, color)]}. Never
## exported; a pose only reads against whatever it is posed against (a guest's hands
## look like they are dangling until the table they rest on is in the frame). Offsets
## are in the figure's own space: Blender +Y is its forward, +Z up, feet at z 0.
ASSEMBLED_CONTEXT = {}


# --- primitives (each returns a bmesh with the shape centred at the origin) ---

def sphere(r, segs=10, rings=7):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segs, v_segments=rings, radius=r)
    return bm


def ico(r, sub=1):
    bm = bmesh.new()
    bmesh.ops.create_icosphere(bm, subdivisions=sub, radius=r)
    return bm


def cyl(r_top, r_bot, h, segs=10, caps=True):
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=caps, cap_tris=False, segments=segs,
                          radius1=r_bot, radius2=r_top, depth=h)
    return bm


def cube(x, y, z):
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    scale(bm, (x, y, z))
    return bm


def torus(R, r, segs=10, minor=6):
    bm = bmesh.new()
    ring = []
    for i in range(segs):
        a = 2 * math.pi * i / segs
        verts = []
        for j in range(minor):
            b = 2 * math.pi * j / minor
            x = (R + r * math.cos(b)) * math.cos(a)
            y = (R + r * math.cos(b)) * math.sin(a)
            z = r * math.sin(b)
            verts.append(bm.verts.new((x, y, z)))
        ring.append(verts)
    for i in range(segs):
        for j in range(minor):
            a, b = ring[i][j], ring[i][(j + 1) % minor]
            c, d = ring[(i + 1) % segs][(j + 1) % minor], ring[(i + 1) % segs][j]
            bm.faces.new((a, b, c, d))
    return bm


def strip(length, width, thick, curl=0.0, segs=6):
    """A thin flat strip along X, optionally curled up at the ends (a shred)."""
    bm = bmesh.new()
    top, bot = [], []
    for i in range(segs + 1):
        t = i / segs
        x = (t - 0.5) * length
        z = curl * (2 * t - 1) ** 2
        for side in (-1, 1):
            y = side * width / 2
            top.append(bm.verts.new((x, y, z + thick / 2)))
            bot.append(bm.verts.new((x, y, z - thick / 2)))
    def quad(a, b, c, d):
        bm.faces.new((a, b, c, d))
    for i in range(segs):
        t0, t1 = top[2 * i], top[2 * i + 1]
        t2, t3 = top[2 * i + 2], top[2 * i + 3]
        b0, b1 = bot[2 * i], bot[2 * i + 1]
        b2, b3 = bot[2 * i + 2], bot[2 * i + 3]
        quad(t0, t2, t3, t1)
        quad(b1, b3, b2, b0)
        quad(t0, b0, b2, t2)
        quad(t1, t3, b3, b1)
    quad(top[0], top[1], bot[1], bot[0])
    quad(top[-2], bot[-2], bot[-1], top[-1])
    return bm


# --- deformers (in place) ---

def transform(bm, m):
    bmesh.ops.transform(bm, matrix=m, verts=bm.verts)


def translate(bm, v):
    transform(bm, Matrix.Translation(Vector(v)))


def scale(bm, s):
    transform(bm, Matrix.Diagonal((*s, 1.0)))


def rotate(bm, axis, deg):
    transform(bm, Matrix.Rotation(math.radians(deg), 4, axis))


def jitter(bm, amount, seed):
    rng = random.Random(seed)
    for v in bm.verts:
        v.co += Vector((rng.uniform(-1, 1), rng.uniform(-1, 1), rng.uniform(-1, 1))) * amount


def bumpy(bm, amount, freq, seed):
    """Organic lumps: displace along the normal by 3D noise."""
    bm.normal_update()
    off = Vector((seed * 7.1, seed * 3.3, seed * 5.7))
    for v in bm.verts:
        n = noise.noise(v.co * freq + off)
        v.co += v.normal * n * amount


def _limb(a, b, r, segs=8):
    """A slightly tapered cylinder running from point a to point b - an arm, a leg."""
    a, b = Vector(a), Vector(b)
    d = b - a
    bm = cyl(r * 0.9, r, d.length, segs)
    transform(bm, d.to_track_quat('Z', 'Y').to_matrix().to_4x4())
    translate(bm, (a + b) / 2)
    return bm


def floor_at(bm, z=0.0):
    """Lift so the lowest vertex sits on z."""
    lo = min(v.co.z for v in bm.verts)
    translate(bm, (0, 0, z - lo))


def clip_below(bm, z=0.0):
    """Flatten everything below z onto z (a fruit resting on a counter)."""
    for v in bm.verts:
        if v.co.z < z:
            v.co.z = z


def merge(*bms):
    out = bmesh.new()
    for bm in bms:
        tmp = bpy.data.meshes.new("_tmp")
        bm.to_mesh(tmp)
        out.from_mesh(tmp)
        bpy.data.meshes.remove(tmp)
        bm.free()
    return out


# --- objects and export ---

def _srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_object(name, bm, color):
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    for p in mesh.polygons:
        p.use_smooth = False
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*color, 1.0)  # Workbench viewport display - the contact sheet
    # The glTF exporter reads baseColorFactor from the Principled BSDF node, never from
    # diffuse_color - a node-less material exports as a flat neutral gray regardless of
    # this. Godot re-tints every ingredient/equipment mesh at runtime anyway
    # (Item._tint_tree), but station bodies and Crate's own glb material have no such
    # override, so this was silently exporting every station gray. Build the node graph.
    #
    # Colour space: Blender's Base Color socket and glTF's baseColorFactor are both
    # linear; every hand-written Color(...) elsewhere in this codebase (Ingredients,
    # Item.color, station body_mat) is used as a literal sRGB value with no conversion
    # (Godot applies none when a script sets albedo_color directly). Godot's glTF
    # importer DOES convert baseColorFactor (linear, per spec) to sRGB on the way in -
    # so writing the designer colour straight into the linear socket round-trips
    # washed out. Decode it first so the number a station's body_mat used to read
    # comes back out the other end.
    lin = tuple(_srgb_to_linear(c) for c in color)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*lin, 1.0)
    bsdf.inputs["Roughness"].default_value = 0.5
    mesh.materials.append(mat)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def item(type_name, color):
    """Decorator: the function returns {"whole": [bm...], "pieces": [bm...]}."""
    def wrap(fn):
        _registry.append((type_name, color, fn, ITEMS_OUT, "items"))
        return fn
    return wrap


def station(type_name, color):
    """Same shape as @item, but exports to stations/models/ and never has pieces -
    stations don't chop, they only ever have a "whole"."""
    def wrap(fn):
        _registry.append((type_name, color, lambda: {"whole": fn(), "pieces": []}, STATIONS_OUT, "stations"))
        return fn
    return wrap


def detail(type_name, color, out_dir):
    """A secondary prop (Burner, Board, Basin, ...) - same shape as @station but the
    caller names its own output directory, since these live alongside either an item
    (crate's ContentMesh) or a station (everything else)."""
    def wrap(fn):
        _registry.append((type_name, color, lambda: {"whole": fn(), "pieces": []}, out_dir, "details"))
        return fn
    return wrap


def player_part(type_name, color):
    """One part of the player figure - its own glb and its own colour, built at its
    true position relative to the player's feet so the scene node keeps an identity
    transform. Rendered assembled rather than in a grid (ASSEMBLED_GROUPS)."""
    def wrap(fn):
        _registry.append((type_name, color, lambda: {"whole": fn(), "pieces": []}, PLAYER_OUT, "player"))
        return fn
    return wrap


def customer_part(type_name, color):
    """One part of the seated-guest figure. Same split as player_part - a part per
    colour, built at its true position relative to the feet - but exported alongside
    the table it belongs to, since a customer only ever exists as a table's child."""
    def wrap(fn):
        _registry.append((type_name, color, lambda: {"whole": fn(), "pieces": []}, STATIONS_OUT, "customer"))
        return fn
    return wrap


def export_set(name, bms, color, out_dir):
    objs = [make_object(f"{name}_{i}", bm, color) for i, bm in enumerate(bms)]
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=str(out_dir / f"{name}.glb"), export_format='GLB',
                              use_selection=True, export_apply=True, export_yup=True,
                              export_animations=False, export_skins=False, export_lights=False,
                              export_cameras=False)
    return objs


# --- godot -> blender placement helpers for the pieces layouts ---

def place(bm, gx, gy, gz, yaw_deg=0.0):
    """Put a piece where the old .tscn had it: Godot (x, y, z) -> Blender (x, -z, y)."""
    rotate(bm, 'Z', yaw_deg)
    translate(bm, (gx, -gz, gy))
    return bm


# =============================================================== ingredients

@item("tomato", (0.86, 0.19, 0.14))
def tomato():
    body = sphere(0.15, 12, 8)
    scale(body, (1.0, 1.0, 0.8))
    # soft lobes around the equator, a dimple at the top
    for v in body.verts:
        a = math.atan2(v.co.y, v.co.x)
        v.co.xy *= 1.0 + 0.04 * math.cos(5 * a) * (1 - abs(v.co.z) / 0.12)
        if v.co.z > 0.10:
            v.co.z -= 0.02 * (1 - (v.co.xy.length / 0.08) ** 2 if v.co.xy.length < 0.08 else 0)
    floor_at(body)
    stem = cyl(0.012, 0.016, 0.04, 6)
    translate(stem, (0, 0, 0.23))
    calyx = bmesh.new()
    for i in range(5):
        leaf = strip(0.07, 0.022, 0.006, curl=-0.01, segs=3)
        translate(leaf, (0.035, 0, 0))
        rotate(leaf, 'Z', i * 72)
        translate(leaf, (0, 0, 0.215))
        calyx = merge(calyx, leaf)
    whole = merge(body, stem, calyx)
    pieces = []
    for i, (x, y, z) in enumerate([(-0.08, 0.04, -0.05), (0.06, 0.04, -0.07), (-0.01, 0.04, 0.01),
                                   (0.08, 0.04, 0.05), (-0.07, 0.04, 0.08)]):
        chunk = ico(0.042, 1)
        jitter(chunk, 0.008, 100 + i)
        scale(chunk, (1.1, 1.0, 0.85))
        floor_at(chunk)
        pieces.append(place(chunk, x, 0, z, 37 * i))
    return {"whole": [whole], "pieces": pieces}


@item("bread_loaf", (0.82, 0.62, 0.36))
def bread_loaf():
    loaf = sphere(0.1, 16, 10)
    scale(loaf, (1.7, 0.85, 1.5))
    # a block with a domed top: flatten the lower half, widen it toward the base
    for v in loaf.verts:
        if v.co.z < 0:
            v.co.z *= 0.3
            v.co.xy *= 1.0 + 0.2 * (-v.co.z / 0.045)
        else:
            v.co.xy *= 1.0 + 0.1 * (1 - v.co.z / 0.15)
    clip_below(loaf, -0.04)
    floor_at(loaf)
    # three diagonal scores across the top
    for v in loaf.verts:
        if v.co.z > 0.15:
            s_ = math.sin((v.co.x - 0.4 * v.co.y) * 42 + 1.0)
            v.co.z -= 0.025 * max(0.0, s_) ** 6
    return {"whole": [loaf], "pieces": []}


@item("bread", (0.82, 0.62, 0.36))
def bread():
    # a slice of that loaf lying flat: a D outline 0.17 x 0.15, 0.05 thick
    bm = bmesh.new()
    prof = []
    for i in range(4):  # rounded bottom-left corner
        a = math.pi + math.pi / 2 * i / 3
        prof.append((-0.06 + 0.025 * math.cos(a), -0.05 + 0.025 * math.sin(a)))
    for i in range(4):  # rounded bottom-right corner
        a = -math.pi / 2 + math.pi / 2 * i / 3
        prof.append((0.06 + 0.025 * math.cos(a), -0.05 + 0.025 * math.sin(a)))
    for i in range(1, 12):  # the domed top
        a = math.pi * i / 12
        prof.append((0.085 * math.cos(a), -0.02 + 0.095 * math.sin(a)))
    lo = [bm.verts.new((x, y, 0.0)) for x, y in prof]
    hi = [bm.verts.new((x, y, 0.05)) for x, y in prof]
    bm.faces.new(lo[::-1])
    bm.faces.new(hi)
    n = len(prof)
    for i in range(n):
        bm.faces.new((lo[i], lo[(i + 1) % n], hi[(i + 1) % n], hi[i]))
    return {"whole": [bm], "pieces": []}


@item("meat", (0.62, 0.30, 0.28))
def meat():
    patty = cyl(0.13, 0.135, 0.06, 12)
    jitter(patty, 0.004, 3)
    for v in patty.verts:
        if v.co.z > 0.02:
            v.co.z += 0.012 * (1 - (v.co.xy.length / 0.135) ** 2)
    floor_at(patty)
    return {"whole": [patty], "pieces": []}


def _shred(seed, length=0.16, width=0.035):
    s = strip(length, width, 0.012, curl=0.02, segs=5)
    rng = random.Random(seed)
    rotate(s, 'X', rng.uniform(-25, 25))
    return s


@item("lettuce_head", (0.45, 0.72, 0.30))
def lettuce_head():
    head = ico(0.14, 2)
    bumpy(head, 0.02, 14.0, 2)
    scale(head, (1.0, 1.0, 0.92))
    clip_below(head, -0.11)
    floor_at(head)
    layout = [(-0.07, 0.02, -0.03, 20), (0.06, 0.02, -0.05, -30), (-0.02, 0.02, 0.02, 45),
              (0.08, 0.02, 0.05, -15), (-0.08, 0.02, 0.07, -50), (0, 0.05, 0, 10),
              (-0.03, 0.045, 0.03, 35), (0.035, 0.045, -0.02, -60)]
    pieces = [place(_shred(10 + i), x, y, z, yaw) for i, (x, y, z, yaw) in enumerate(layout)]
    return {"whole": [head], "pieces": pieces}


@item("lettuce", (0.45, 0.72, 0.30))
def lettuce():
    layout = [(0, 0.018, 0, 10), (0.028, 0.018, 0.01, -25), (-0.026, 0.018, -0.012, 35),
              (0.004, 0.034, 0.004, -15)]
    whole = merge(*[place(_shred(20 + i, 0.14, 0.03), x, y, z, yaw) for i, (x, y, z, yaw) in enumerate(layout)])
    return {"whole": [whole], "pieces": []}


def _drumstick(seed=0):
    meat_ = sphere(0.055, 10, 7)
    scale(meat_, (1.5, 1.0, 0.9))
    for v in meat_.verts:  # taper toward the bone end (+x)
        v.co.yz *= 1.0 - 0.35 * max(0.0, v.co.x / 0.08)
    jitter(meat_, 0.003, seed)
    bone = cyl(0.011, 0.011, 0.09, 6)
    rotate(bone, 'Y', 90)
    translate(bone, (0.11, 0, 0))
    knob = sphere(0.018, 7, 5)
    translate(knob, (0.155, 0, 0))
    d = merge(meat_, bone, knob)
    floor_at(d)
    return d


@item("chicken", (0.95, 0.70, 0.60))
def chicken():
    body = sphere(0.16, 12, 8)
    scale(body, (1.05, 0.85, 0.75))
    for v in body.verts:  # breast forward (+y), narrower tail
        v.co.z += 0.03 * max(0.0, v.co.y / 0.14)
    clip_below(body, -0.09)
    floor_at(body)
    legs = []
    for side in (-1, 1):
        leg = _drumstick(seed=5)
        scale(leg, (0.85, 0.85, 0.85))
        rotate(leg, 'Z', side * 35 + 180)
        rotate(leg, 'Y', -side * 0)
        translate(leg, (side * 0.11, -0.12, 0.05))
        legs.append(leg)
    wings = []
    for side in (-1, 1):
        w = sphere(0.045, 8, 5)
        scale(w, (0.7, 1.4, 0.6))
        translate(w, (side * 0.15, 0.02, 0.12))
        wings.append(w)
    whole = merge(body, *legs, *wings)
    return {"whole": [whole], "pieces": []}


@item("chicken_piece", (0.95, 0.70, 0.60))
def chicken_piece():
    return {"whole": [_drumstick(seed=6)], "pieces": []}


def _bone(seed):
    shaft = cyl(0.011, 0.011, 0.16, 6)
    rotate(shaft, 'Y', 90)
    ends = []
    for x in (-0.09, 0.09):
        k = sphere(0.02, 7, 5)
        scale(k, (0.8, 1.3, 1.0))
        translate(k, (x, 0, 0))
        ends.append(k)
    b = merge(shaft, *ends)
    floor_at(b)
    return b


@item("bones", (0.92, 0.88, 0.78))
def bones():
    layout = [(-0.03, 0, 0, 20), (0.03, 0, 0.02, -60), (0, 0.028, -0.02, 45)]
    whole = merge(*[place(_bone(i), x, y, z, yaw) for i, (x, y, z, yaw) in enumerate(layout)])
    return {"whole": [whole], "pieces": []}


@item("potato", (0.66, 0.50, 0.30))
def potato():
    body = ico(0.11, 2)
    scale(body, (1.35, 1.0, 0.8))
    bumpy(body, 0.014, 9.0, 4)
    floor_at(body)
    pieces = []
    layout = [(-0.07, 0.025, -0.04, 20), (0.06, 0.025, -0.05, -30), (0, 0.025, 0.04, 0),
              (-0.05, 0.025, 0.06, 45), (0.07, 0.025, 0.05, 15)]
    for i, (x, y, z, yaw) in enumerate(layout):
        chunk = cube(0.06, 0.06, 0.05)
        jitter(chunk, 0.006, 40 + i)
        floor_at(chunk)
        pieces.append(place(chunk, x, 0, z, yaw))
    return {"whole": [body], "pieces": pieces}


@item("onion", (0.58, 0.28, 0.48))
def onion():
    bulb = sphere(0.1, 12, 8)
    for v in bulb.verts:  # vertical ridges, a pointed top, a flat root
        a = math.atan2(v.co.y, v.co.x)
        v.co.xy *= 1.0 + 0.035 * math.cos(6 * a)
        if v.co.z > 0:
            v.co.z *= 1.25
    clip_below(bulb, -0.075)
    floor_at(bulb)
    stalk = cyl(0.012, 0.03, 0.07, 7)
    translate(stalk, (0, 0, 0.21))
    whole = merge(bulb, stalk)
    layout = [(-0.06, 0.01, -0.03, 20), (0.05, 0.01, -0.04, -60), (-0.02, 0.01, 0.03, 45),
              (0.06, 0.01, 0.04, 15), (0, 0.03, 0, 75), (-0.04, 0.03, 0.05, -35)]
    pieces = []
    for i, (x, y, z, yaw) in enumerate(layout):
        arc = torus(0.045, 0.008, 12, 4)
        # keep a third of the ring: a sliver
        for v in list(arc.verts):
            if math.atan2(v.co.y, v.co.x) > 1.2 or math.atan2(v.co.y, v.co.x) < -1.2:
                arc.verts.remove(v)
        scale(arc, (1.0, 1.0, 1.6))
        floor_at(arc)
        pieces.append(place(arc, x, 0, z, yaw))
    return {"whole": [whole], "pieces": pieces}


def lathe(profile, segs=12):
    """Revolve an (r, z) profile around Z. Endpoints with r=0 close the ends."""
    bm = bmesh.new()
    rings = []
    for r, z in profile:
        if r <= 1e-6:
            rings.append([bm.verts.new((0, 0, z))] * segs)
            continue
        rings.append([bm.verts.new((r * math.cos(2 * math.pi * i / segs),
                                    r * math.sin(2 * math.pi * i / segs), z)) for i in range(segs)])
    for a, b in zip(rings, rings[1:]):
        for i in range(segs):
            quad = [a[i], a[(i + 1) % segs], b[(i + 1) % segs], b[i]]
            uniq = []
            for v in quad:
                if v not in uniq:
                    uniq.append(v)
            if len(uniq) >= 3:
                bm.faces.new(uniq)
    return bm


def _bowl(r_top, r_bot, h, segs=12, t=0.012):
    bowl = lathe([(0, 0), (r_bot, 0), (r_top, h), (r_top - t, h), (r_bot - t, t), (0, t)], segs)
    liquid = cyl(r_top - t - 0.003, r_top - t - 0.003, 0.004, segs)
    translate(liquid, (0, 0, h - 0.016))
    return merge(bowl, liquid)


@item("stock", (0.86, 0.68, 0.32))
def stock():
    return {"whole": [_bowl(0.12, 0.07, 0.06)], "pieces": []}


@item("sauce", (0.52, 0.32, 0.16))
def sauce():
    boat = _bowl(0.05, 0.035, 0.07, 12)
    scale(boat, (1.4, 1.0, 1.0))
    for v in boat.verts:  # a spout on +x
        if v.co.x > 0.04 and v.co.z > 0.04:
            v.co.x += 0.02 * (v.co.z / 0.07)
            v.co.z += 0.01
    handle = torus(0.028, 0.007, 10, 5)
    rotate(handle, 'X', 90)
    translate(handle, (-0.075, 0, 0.04))
    whole = merge(boat, handle)
    floor_at(whole)
    return {"whole": [whole], "pieces": []}


# =============================================================== equipment

@item("pot", (0.42, 0.44, 0.48))
def pot():
    # a stockpot: straight-ish wall, a rolled rim, two ear handles. The Liquid disc
    # in pot.tscn sits at y 0.13 r 0.17 - the inner wall stays outside that.
    body = lathe([(0, 0), (0.175, 0), (0.185, 0.02), (0.195, 0.16), (0.205, 0.175), (0.2, 0.18),
                  (0.185, 0.18), (0.183, 0.015), (0, 0.015)], 14)
    ears = []
    for side in (-1, 1):
        ear = torus(0.028, 0.008, 10, 5)
        for v in list(ear.verts):  # keep the outer half
            if v.co.x * side < 0.005:
                ear.verts.remove(v)
        rotate(ear, 'X', 90)
        translate(ear, (side * 0.2, 0, 0.14))
        ears.append(ear)
    return {"whole": [merge(body, *ears)], "pieces": []}


@item("pan", (0.22, 0.22, 0.24))
def pan():
    # a skillet: shallow flared dish, a flat handle out along +x with a hang-hole
    dish = lathe([(0, 0), (0.19, 0), (0.2, 0.01), (0.22, 0.06), (0.205, 0.06), (0.19, 0.055),
                  (0.18, 0.012), (0, 0.012)], 16)
    handle = cube(0.2, 0.04, 0.014)
    for v in handle.verts:  # slight taper and upward sweep
        t = (v.co.x + 0.1) / 0.2
        v.co.y *= 1.0 - 0.25 * t
        v.co.z += 0.02 * t
    translate(handle, (0.31, 0, 0.045))
    return {"whole": [merge(dish, handle)], "pieces": []}


@item("plate", (0.92, 0.92, 0.94))
def plate():
    return {"whole": [lathe([(0, 0), (0.2, 0), (0.22, 0.012), (0.27, 0.035), (0.28, 0.05),
                             (0.265, 0.05), (0.21, 0.03), (0.19, 0.025), (0, 0.025)], 16)],
            "pieces": []}


@item("tray", (0.78, 0.72, 0.60))
def tray():
    # a rectangular tray 0.94 x 0.72: a 0.04 floor (contents sit at y 0.06) and a low
    # rim all round, with a hand notch in the long sides
    base = cube(0.94, 0.72, 0.04)
    translate(base, (0, 0, 0.02))
    rails = []
    for sy in (-1, 1):
        for x0, x1 in ((-0.47, -0.12), (0.12, 0.47)):
            r = cube(x1 - x0, 0.03, 0.07)
            translate(r, ((x0 + x1) / 2, sy * 0.345, 0.045))
            rails.append(r)
    for sx in (-1, 1):
        r = cube(0.03, 0.72, 0.07)
        translate(r, (sx * 0.455, 0, 0.045))
        rails.append(r)
    return {"whole": [merge(base, *rails)], "pieces": []}


@item("spice_shaker", (0.32, 0.27, 0.22))
def spice_shaker():
    body = lathe([(0, 0), (0.11, 0), (0.12, 0.02), (0.1, 0.19), (0.095, 0.2), (0, 0.2)], 12)
    cap = lathe([(0, 0.2), (0.095, 0.2), (0.09, 0.24), (0.06, 0.26), (0, 0.265)], 12)
    holes = []
    for i in range(6):
        a = 2 * math.pi * i / 6
        h = cyl(0.008, 0.008, 0.01, 6)
        translate(h, (0.035 * math.cos(a), 0.035 * math.sin(a), 0.262))
        holes.append(h)
    return {"whole": [merge(body, cap, *holes)], "pieces": []}


@item("crate", (0.50, 0.36, 0.22))
def crate():
    # a slatted crate 0.5 x 0.5 x 0.35, open top; ContentMesh in crate.tscn shows the
    # contents peeking out at y 0.34
    parts = []
    floor = cube(0.5, 0.5, 0.03)
    translate(floor, (0, 0, 0.015))
    parts.append(floor)
    for side in range(4):
        for z in (0.06, 0.16, 0.26):
            slat = cube(0.5, 0.025, 0.07)
            translate(slat, (0, -0.2375, z + 0.035))
            rotate(slat, 'Z', 90 * side)
            parts.append(slat)
        post = cube(0.035, 0.035, 0.35)
        translate(post, (0.2325, 0.2325, 0.175))
        rotate(post, 'Z', 90 * side)
        parts.append(post)
    return {"whole": [merge(*parts)], "pieces": []}


# =============================================================== stations
#
# Every station body today is a bare box (Vector3(1, 0.9, 1), or a variant size) with
# a per-instance tint - the "cube prison." Godot's collision Shape stays that exact
# box always (StationGrid/physics/reach depend on it); only the visual Mesh gets
# replaced here. A shared cabinet carcass, one glb per colour already in use, matches
# how the game already differentiates stations (tint + a distinguishing prop on top,
# e.g. Burner/Board/Basin/Screen/Sign/Mattress) - it's the box getting real panels and
# a countertop lip, not a bespoke piece of furniture per station.


def _cabinet_base(w, h, d):
    """The kick + carcass + recessed front panel shared by every cabinet - no top,
    since a plain counter wants a solid lip (_cabinet) and the sink wants a framed
    opening (sink(), below) instead. Returns (parts, kick_h, lip_h, body_h) so a
    caller can add its own top at the right height."""
    kick_h = min(0.08, h * 0.18)
    lip_h = min(0.05, h * 0.1)
    body_h = h - kick_h - lip_h
    parts = []
    body = cube(w, d, body_h)
    translate(body, (0, 0, -h / 2 + kick_h + body_h / 2))
    parts.append(body)
    kick = cube(w * 0.92, d * 0.85, kick_h)
    translate(kick, (0, -d * 0.04, -h / 2 + kick_h / 2))
    parts.append(kick)
    panel = cube(w * 0.7, 0.015, body_h * 0.7)
    translate(panel, (0, -d / 2 - 0.006, -h / 2 + kick_h + body_h / 2))
    parts.append(panel)
    return parts, kick_h, lip_h, body_h


def _cabinet(w, h, d):
    """A counter carcass: a toe-kick at the base, a recessed front panel, a
    countertop lip. Centred at the origin, matching the box it replaces exactly -
    the Mesh node keeps its identity transform."""
    parts, kick_h, lip_h, body_h = _cabinet_base(w, h, d)
    top = cube(w * 0.99, d * 0.99, lip_h)
    translate(top, (0, 0, h / 2 - lip_h / 2))
    parts.append(top)
    return merge(*parts)


@station("counter", (0.55, 0.40, 0.28))
def counter():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("cook_station", (0.28, 0.28, 0.30))
def cook_station():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("sink", (0.72, 0.74, 0.78))
def sink():
    # the same cabinet carcass, but the top is a FRAME around a rectangular opening
    # (four rim strips, not a solid lip) so the basin prop reads as set INTO the
    # counter, not resting on top of it - what made the old sink "just a repainted
    # desk" (Noah, 2026-09-20): a flat lip with a shape glued on top, same as every
    # other cabinet. A short gooseneck faucet (a post + a partial-torus arc, the same
    # "keep one wedge of a ring" trick onion()'s slivers use) rises from the back edge.
    w, h, d = 1.0, 0.9, 1.0
    parts, kick_h, lip_h, body_h = _cabinet_base(w, h, d)
    opening_w, opening_d = 0.62, 0.42
    rim_t = (w * 0.99 - opening_w) / 2
    front_t = (d * 0.99 - opening_d) / 2
    for cx, cy, cw, cd in [
        (0, (d * 0.99 - front_t) / 2, w * 0.99, front_t),
        (0, -(d * 0.99 - front_t) / 2, w * 0.99, front_t),
        ((w * 0.99 - rim_t) / 2, 0, rim_t, opening_d),
        (-(w * 0.99 - rim_t) / 2, 0, rim_t, opening_d),
    ]:
        strip = cube(cw, cd, lip_h)
        translate(strip, (cx, cy, h / 2 - lip_h / 2))
        parts.append(strip)

    post = cyl(0.018, 0.018, 0.22, 8)
    translate(post, (0, -d * 0.32, h / 2 + 0.11))
    parts.append(post)
    arc = torus(0.11, 0.016, 14, 6)
    rotate(arc, 'X', 90)
    for v in list(arc.verts):  # keep a quarter-circle: up the post, over, and down
        a = math.atan2(v.co.z, -v.co.y)
        if a < 0 or a > math.pi / 2:
            arc.verts.remove(v)
    translate(arc, (0, -d * 0.32 + 0.11, h / 2 + 0.22))
    parts.append(arc)
    spout = cyl(0.014, 0.014, 0.05, 8)
    translate(spout, (0, -d * 0.32 + 0.11, h / 2 + 0.085))
    parts.append(spout)

    return [merge(*parts)]


@station("open_sign", (0.42, 0.34, 0.22))
def open_sign():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("order_desk", (0.35, 0.3, 0.38))
def order_desk():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("plate_stack", (0.62, 0.60, 0.66))
def plate_stack():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("till", (0.35, 0.32, 0.30))
def till():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("tray_rack", (0.58, 0.54, 0.48))
def tray_rack():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("bed", (0.4, 0.28, 0.18))
def bed():
    return [_cabinet(1.0, 0.9, 1.0)]


@station("trashcan", (0.25, 0.32, 0.26))
def trashcan():
    bin_ = lathe([(0, 0), (0.28, 0), (0.30, 0.04), (0.33, 0.85), (0.35, 0.9), (0.32, 0.9),
                  (0.31, 0.06), (0.27, 0.03), (0, 0.03)], 14)
    translate(bin_, (0, 0, -0.45))
    return [bin_]


@station("table", (0.55, 0.40, 0.28))
def table():
    top = cube(1.1, 1.1, 0.06)
    translate(top, (0, 0, 0.22))
    legs = []
    for sx in (-1, 1):
        for sy in (-1, 1):
            leg = cube(0.07, 0.07, 0.44)
            translate(leg, (sx * 0.48, sy * 0.48, -0.03))
            legs.append(leg)
    apron = []
    for w_, off in [((1.1, 0.05), (0, 0.5)), ((1.1, 0.05), (0, -0.5))]:
        a = cube(w_[0] - 0.12, w_[1], 0.08)
        translate(a, (0, off[1] * 0.94, 0.15))
        apron.append(a)
    return [merge(top, *legs, *apron)]


# =============================================================== station/item detail props
#
# The small props riding on top of a cabinet or an item, previously left as primitives
# ("a later pass, if wanted, same tool" - Noah: "let's do all the extras too"). Every
# node keeps its existing scene transform - most are already centred at their own
# local origin the same way a BoxMesh/CylinderMesh always is, so nothing here needs
# floor_at(). Three of these (the LedgerAccumulator Piles on till/invoice_folder/
# receipt_station) are procedurally Y-scaled at runtime off their own mesh AABB
# (LedgerAccumulator._process) - they get a nicer profile, not a multi-part stack,
# and stay vertically symmetric around the origin so that scaling still reads as
# "more/less", not a deformed shape.


@detail("burner", (0.12, 0.12, 0.13), STATIONS_OUT)
def burner():
    # a coil hob: a low base disc, three concentric raised rings, a center hub -
    # always visible under Godot's own material_override, so the colour barely
    # matters, but the shape will. torus() already lies flat (its hoop is in the XY
    # plane, like the pot's ear handles before THEY get tipped up) - no rotation
    # needed, or it stands the ring up on its edge instead of resting flat on the
    # burner. The Burner node's own scene transform sits it just proud of the
    # counter's top surface, the way the old flat disc (centred at its own origin)
    # did - floor_at() at the end matches that: the base rests AT the node's local
    # z=0, everything rises from there, instead of the coils dipping below it and
    # poking down through the counter.
    base = cyl(0.34, 0.34, 0.02, 14)
    rings = [base]
    for i, r in enumerate((0.14, 0.22, 0.30)):
        ring = torus(r, 0.018, 16, 6)
        translate(ring, (0, 0, 0.02))
        rings.append(ring)
    hub = cyl(0.05, 0.05, 0.02, 10)
    translate(hub, (0, 0, 0.02))
    rings.append(hub)
    whole = merge(*rings)
    floor_at(whole)
    return [whole]


@detail("cutting_board", (0.68, 0.52, 0.36), STATIONS_OUT)
def cutting_board_detail():
    board = lathe([(0, 0)], 1)  # placeholder, unused - real profile below
    board = cube(0.7, 0.7, 0.06)
    # rounded corners: chamfer each corner vert inward a touch
    for v in board.verts:
        v.co.x -= math.copysign(0.03, v.co.x)
        v.co.y -= math.copysign(0.03, v.co.y)
    hole = torus(0.045, 0.012, 10, 5)
    translate(hole, (0, 0.29, 0.02))
    return [merge(board, hole)]


@detail("basin", (0.55, 0.68, 0.78), STATIONS_OUT)
def basin():
    # a plain rectangular void - Noah's correction to the round lathed bowl this
    # replaced ("looks pretty odd... let's just do a cube sink void"). Straight walls,
    # an open top, a flat floor, a drain dimple - nests inside sink()'s framed
    # countertop opening (0.62 x 0.42) rather than sitting on top of it.
    w, d, depth = 0.56, 0.36, 0.14
    bm = bmesh.new()
    top = [bm.verts.new((sx * w / 2, sy * d / 2, 0)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    bot = [bm.verts.new((sx * w / 2, sy * d / 2, -depth)) for sx, sy in ((-1, -1), (1, -1), (1, 1), (-1, 1))]
    for i in range(4):
        bm.faces.new((top[i], top[(i + 1) % 4], bot[(i + 1) % 4], bot[i]))
    bm.faces.new(bot[::-1])
    drain = cyl(0.025, 0.025, 0.01, 10)
    translate(drain, (0, 0, -depth + 0.005))
    return [merge(bm, drain)]


@detail("sign", (0.88, 0.83, 0.68), STATIONS_OUT)
def sign():
    board = cube(0.6, 0.08, 0.4)
    frame = cube(0.56, 0.02, 0.36)
    translate(frame, (0, -0.03, 0))
    post = cube(0.04, 0.04, 0.26)
    translate(post, (0, 0, -0.33))
    return [merge(board, frame, post)]


@detail("mattress", (0.55, 0.65, 0.78), STATIONS_OUT)
def mattress():
    body = cube(0.9, 0.9, 0.12)
    bumpy(body, 0.012, 6.0, 8)
    for v in body.verts:  # rounded top edges
        if v.co.z > 0.03:
            v.co.x *= 0.94
            v.co.y *= 0.94
    pillow = ico(0.14, 1)
    scale(pillow, (1.3, 1.0, 0.55))
    translate(pillow, (0, -0.32, 0.12))
    return [merge(body, pillow)]


@detail("screen", (0.15, 0.55, 0.35), STATIONS_OUT)
def screen():
    # built in the SAME normalized unit-cube space the old size=(1,1,1) BoxMesh
    # occupied - the scene's own non-uniform transform (0.6, 0.5, 0.06) resizes this
    # to the real 0.6 x 0.5 x 0.06 monitor footprint, unchanged.
    panel = cube(1.0, 1.0, 1.0)
    bezel = cube(0.86, 0.06, 0.86)
    translate(bezel, (0, -0.53, 0))
    return [merge(panel, bezel)]


@detail("plates", (0.92, 0.92, 0.94), STATIONS_OUT)
def plates():
    discs = []
    rng = random.Random(11)
    for i in range(6):
        d = lathe([(0, 0), (0.22, 0), (0.24, 0.008), (0.26, 0.02), (0.24, 0.028),
                   (0.20, 0.022), (0, 0.02)], 12)
        translate(d, (rng.uniform(-0.01, 0.01), rng.uniform(-0.01, 0.01), i * 0.026))
        discs.append(d)
    return [merge(*discs)]


@detail("rod", (0.55, 0.55, 0.58), STATIONS_OUT)
def rod():
    spike = lathe([(0, 0), (0.05, 0), (0.055, 0.02), (0.03, 0.36), (0, 0.4)], 8)
    return [spike]


@detail("light_base", (0.2, 0.2, 0.22), STATIONS_OUT)
def light_base():
    base = cube(0.16, 0.16, 0.1)
    for v in base.verts:
        v.co.x *= 0.9 if v.co.z > 0 else 1.0
        v.co.y *= 0.9 if v.co.z > 0 else 1.0
    return [base]


@detail("light", (0.6, 0.6, 0.6), STATIONS_OUT)
def light():
    return [sphere(0.07, 8, 6)]


@detail("tray_pile", (0.78, 0.72, 0.6), STATIONS_OUT)
def tray_pile():
    base = cube(0.86, 0.64, 0.03)
    rails = []
    for sy in (-1, 1):
        r = cube(0.86, 0.02, 0.05)
        translate(r, (0, sy * 0.31, 0.025))
        rails.append(r)
    for sx in (-1, 1):
        r = cube(0.02, 0.64, 0.05)
        translate(r, (sx * 0.42, 0, 0.025))
        rails.append(r)
    return [merge(base, *rails)]


@detail("crate_content", (0.7, 0.5, 0.3), ITEMS_OUT)
def crate_content():
    # a small mound - produce peeking over the crate's rim, tinted per-ingredient at
    # runtime (Crate.gd sets material_override on this node directly)
    mound = ico(0.14, 1)
    scale(mound, (1.3, 1.3, 0.5))
    bumpy(mound, 0.012, 10.0, 3)
    floor_at(mound)
    translate(mound, (0, 0, -0.06))
    return [mound]


# =============================================================== the customer
#
# Built against the player's own proportions so a guest and a cook read as the same
# species, then made unmistakably not-a-cook: no toque, no apron, hair instead, and
# hands resting on the table rather than reaching out in front. A guest ends up a
# little shorter than a chef purely because the chef's hat adds to the silhouette.
# Table.gd tints the shirt and hair per guest, so a party of four isn't four clones.

_C_WAIST = 0.46
_C_SHOULDER = 0.98
_C_HAND = (0.235, 0.40, 0.53)  # resting on the table edge, which sits at y 0.5


@customer_part("customer_body", (0.60, 0.42, 0.72))
def customer_body():
    # The shirt - torso plus both arms angled down and forward onto the table. The one
    # part Table.gd re-colours, so everything that makes one guest a different person
    # from the next lives here (and in the hair).
    parts = []
    torso = cyl(0.255, 0.275, 0.58, 12)
    scale(torso, (1.0, 0.84, 1.0))
    translate(torso, (0, 0, _C_WAIST + 0.29))
    parts.append(torso)
    hx, hy, hz = _C_HAND
    for side in (-1, 1):
        shoulder = (side * 0.24, 0.0, _C_SHOULDER)
        parts.append(_limb(shoulder, (side * hx, hy, hz), 0.072))
        cap = sphere(0.09, 8, 6)
        translate(cap, shoulder)
        parts.append(cap)
    return [merge(*parts)]


@customer_part("customer_skin", (0.92, 0.74, 0.60))
def customer_skin():
    parts = []
    neck = cyl(0.082, 0.1, 0.12, 8)
    translate(neck, (0, 0, 1.03))
    parts.append(neck)
    head = sphere(0.17, 12, 9)
    scale(head, (1.0, 0.95, 1.05))
    translate(head, (0, 0, 1.22))
    parts.append(head)
    nose = cyl(0.0, 0.05, 0.11, 8)
    rotate(nose, 'X', -90)
    translate(nose, (0, 0.16, 1.20))
    parts.append(nose)
    hx, hy, hz = _C_HAND
    for side in (-1, 1):
        hand = sphere(0.085, 8, 6)
        scale(hand, (1.0, 1.2, 0.85))
        translate(hand, (side * hx, hy, hz))
        parts.append(hand)
    return [merge(*parts)]


@customer_part("customer_hair", (0.28, 0.20, 0.16))
def customer_hair():
    # A cap over the back and top of the skull, cut away at the face so the nose and
    # brow still read - the chef's toque occupies this space, so hair here is the
    # cheapest way to tell a guest from a cook at a glance.
    cap = sphere(0.185, 12, 9)
    scale(cap, (1.0, 0.97, 1.05))
    translate(cap, (0, -0.012, 1.235))
    clip_below(cap, 1.17)
    for v in cap.verts:  # raise the hairline toward the front so it isn't a helmet
        front = max(0.0, v.co.y) / 0.185
        v.co.z = max(v.co.z, 1.17 + 0.10 * front * front)
    return [cap]


@customer_part("customer_legs", (0.30, 0.30, 0.34))
def customer_legs():
    parts = []
    for side in (-1, 1):
        parts.append(_limb((side * 0.14, 0.0, _C_WAIST + 0.04),
                           (side * 0.13, 0.015, 0.09), 0.1))
        shoe = cube(0.165, 0.28, 0.1)
        translate(shoe, (side * 0.13, 0.05, 0.05))
        parts.append(shoe)
    return [merge(*parts)]


@detail("coin_pile", (0.90, 0.76, 0.28), STATIONS_OUT)
def coin_pile():
    rng = random.Random(21)
    coins = []
    for i in range(5):
        c = cyl(0.1, 0.1, 0.025, 10)
        translate(c, (rng.uniform(-0.015, 0.015), rng.uniform(-0.015, 0.015), i * 0.02))
        rotate(c, 'Z', rng.uniform(0, 360))
        coins.append(c)
    return [merge(*coins)]


@detail("pile_coins", (0.88, 0.74, 0.18), STATIONS_OUT)
def pile_coins():
    # the till's LedgerAccumulator pile - vertically symmetric so runtime Y-scaling
    # (LedgerAccumulator._process, off this mesh's own AABB) still reads as "more/less"
    p = lathe([(0, -0.2), (0.3, -0.2), (0.3, -0.16), (0.26, -0.14), (0.26, 0.14),
               (0.3, 0.16), (0.3, 0.2), (0, 0.2)], 14)
    return [p]


@detail("pile_paper", (0.92, 0.90, 0.85), STATIONS_OUT)
def pile_paper():
    p = cube(0.18, 0.24, 0.35)
    for v in p.verts:
        v.co.x += 0.006 if v.co.z > 0 else -0.006  # a slight lean, a paper stack
    return [p]


@detail("pile_folders", (0.78, 0.62, 0.32), STATIONS_OUT)
def pile_folders():
    p = cube(0.55, 0.42, 0.22)
    for v in p.verts:
        v.co.x *= 0.97 if v.co.z > 0 else 1.0
    return [p]


# =============================================================== the player

## The figure is laid out against the CharacterBody3D's own capsule - radius 0.35,
## height 1.4, feet at z 0 - so the silhouette stays inside what the body collides
## with. HoldPoint sits 0.55 forward at height 1.0, which is where the arms reach:
## a held item should look held, not floating in front of a box.
_P_WAIST = 0.46
_P_SHOULDER = 0.97
_P_HAND = (0.15, 0.47, 0.95)

_SKIN = (0.95, 0.76, 0.60)


@player_part("player_body", (0.31, 0.62, 1.0))
def player_body():
    # A cook's jacket, and the only part Player._ready() re-colours - so everything
    # that identifies which player this is lives here and nowhere else. Flattened
    # front-to-back so it doesn't just read as the capsule again.
    parts = []
    torso = cyl(0.25, 0.265, 0.56, 12)
    scale(torso, (1.0, 0.82, 1.0))
    translate(torso, (0, 0, _P_WAIST + 0.28))
    parts.append(torso)
    hx, hy, hz = _P_HAND
    for side in (-1, 1):
        shoulder = (side * 0.235, 0.0, _P_SHOULDER)
        parts.append(_limb(shoulder, (side * hx, hy, hz), 0.075))
        cap = sphere(0.095, 8, 6)
        translate(cap, shoulder)
        parts.append(cap)
    return [merge(*parts)]


@player_part("player_skin", _SKIN)
def player_skin():
    # Head, nose and both hands in one mesh - one colour, so one part. The nose is a
    # cone rather than the old box: at this camera angle it is still the clearest
    # read on which way a player is facing.
    parts = []
    neck = cyl(0.085, 0.105, 0.12, 8)
    translate(neck, (0, 0, 1.04))
    parts.append(neck)
    head = sphere(0.175, 12, 9)
    scale(head, (1.0, 0.94, 1.04))
    translate(head, (0, 0, 1.25))
    parts.append(head)
    nose = cyl(0.0, 0.055, 0.13, 8)
    rotate(nose, 'X', -90)
    translate(nose, (0, 0.165, 1.23))
    parts.append(nose)
    hx, hy, hz = _P_HAND
    for side in (-1, 1):
        hand = sphere(0.09, 8, 6)
        scale(hand, (1.0, 1.15, 0.9))
        translate(hand, (side * hx, hy, hz))
        parts.append(hand)
    return [merge(*parts)]


@player_part("player_hat", (0.95, 0.95, 0.92))
def player_hat():
    # The one part that rises above the collision capsule, and worth the exception:
    # from a fixed angled-topdown camera the face is barely visible, so the toque is
    # what says "cook" at a glance - and what tells a player apart from a customer.
    parts = []
    band = cyl(0.185, 0.19, 0.08, 14)
    translate(band, (0, 0, 1.39))
    parts.append(band)
    crown = sphere(0.225, 14, 9)
    scale(crown, (1.0, 1.0, 0.70))
    bumpy(crown, 0.025, 5.0, 3)
    translate(crown, (0, 0, 1.49))
    clip_below(crown, 1.42)
    parts.append(crown)
    return [merge(*parts)]


@player_part("player_apron", (0.93, 0.92, 0.88))
def player_apron():
    # The only part that tells front from back at the game's camera angle. The toque's
    # brim hides the face and the nose from anywhere above, and no nose long enough to
    # clear it would look like a nose - so facing is read off the body instead.
    # Slats rather than one curved panel: a box has only two X values, so bending it
    # by vertex just slides the whole thing backwards into the torso it should sit on.
    cols, width = 5, 0.27
    slats = []
    for i in range(cols):
        x = (i - (cols - 1) / 2) * (width / cols)
        y = 0.82 * math.sqrt(max(0.262 ** 2 - x * x, 0.0)) + 0.012
        slat = cube(width / cols + 0.004, 0.03, 0.48)
        translate(slat, (x, y, 0.74))
        slats.append(slat)
    return [merge(*slats)]


@player_part("player_legs", (0.26, 0.27, 0.32))
def player_legs():
    parts = []
    for side in (-1, 1):
        parts.append(_limb((side * 0.145, 0.0, _P_WAIST + 0.04),
                           (side * 0.135, 0.015, 0.09), 0.105))
        shoe = cube(0.17, 0.29, 0.1)
        translate(shoe, (side * 0.135, 0.05, 0.05))
        parts.append(shoe)
    return [merge(*parts)]


## A guest is only ever posed against a table, so render one.
ASSEMBLED_CONTEXT["customer"] = [(table, (0, 0.95, 0.25), (0.55, 0.40, 0.28))]


# =============================================================== main

def build_all(only_group=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    ITEMS_OUT.mkdir(parents=True, exist_ok=True)
    STATIONS_OUT.mkdir(parents=True, exist_ok=True)
    PLAYER_OUT.mkdir(parents=True, exist_ok=True)
    built = []
    for type_name, color, fn, out_dir, group in _registry:
        if only_group is not None and group != only_group:
            continue
        sets = fn()
        whole_objs = export_set(f"{type_name}_whole", sets["whole"], color, out_dir)
        piece_objs = export_set(f"{type_name}_pieces", sets["pieces"], color, out_dir) if sets["pieces"] else []
        built.append((type_name, whole_objs, piece_objs, group))
        print(f"built {type_name}: {sum(len(o.data.polygons) for o in whole_objs)} faces whole, "
              f"{sum(len(o.data.polygons) for o in piece_objs)} faces pieces")
    return built


def _extent(objs):
    """The largest dimension across a set of objects - what a sheet cell has to fit."""
    return max((max(o.dimensions) for o in objs), default=0.1)


def _union_bounds(objs):
    """The box every one of these objects fits inside, read off their vertices - what
    an assembled figure actually spans, which no single part's dimensions tell you."""
    cos = [v.co for o in objs for v in o.data.vertices]
    lo = Vector((min(c.x for c in cos), min(c.y for c in cos), min(c.z for c in cos)))
    hi = Vector((max(c.x for c in cos), max(c.y for c in cos), max(c.z for c in cos)))
    return lo, hi


## Camera directions for an assembled render, scaled by the figure's own size. Front
## for the face and the reach, three-quarter for the silhouette, top-down because that
## is roughly what the game's own camera sees.
## +Y is the figure's forward (place() maps Godot -z, forward, onto Blender +y), so a
## camera that wants the face belongs on +Y. Front for the face and the reach, three-
## quarter for the silhouette, game for roughly the kitchen camera's own ~50 degrees.
_ASSEMBLED_VIEWS = [
    ("front", Vector((0.0, 2.4, 0.2))),
    ("three_quarter", Vector((1.5, 1.9, 0.9))),
    ("game", Vector((0.0, 1.6, 1.9))),
    ("game_back", Vector((0.0, -1.6, 1.9))),
]


def _assembled_sheet(group, objs, every_obj, path):
    """Render one group's parts in place, together, from a few angles - the check
    that says whether the assembly reads as one object. A grid cell per part can't."""
    for o in every_obj:
        o.hide_render = True
    for o in objs:
        o.hide_render = False
        o.location = (0, 0, 0)
    context = []
    for i, (builder, offset, color) in enumerate(ASSEMBLED_CONTEXT.get(group, [])):
        for j, bm in enumerate(builder()):
            translate(bm, offset)
            context.append(make_object(f"_ctx_{group}_{i}_{j}", bm, color))
    lo, hi = _union_bounds(objs)
    centre = (lo + hi) / 2
    span = max(hi.x - lo.x, hi.y - lo.y, hi.z - lo.z)
    scene = bpy.context.scene
    scene.render.resolution_x = 700
    scene.render.resolution_y = 900
    cam_data = bpy.data.cameras.new(f"cam_{group}")
    cam_data.type = 'ORTHO'
    cam_data.ortho_scale = span * 1.3
    cam_data.clip_end = 1000.0
    cam = bpy.data.objects.new(f"cam_{group}", cam_data)
    scene.collection.objects.link(cam)
    scene.camera = cam
    for view, direction in _ASSEMBLED_VIEWS:
        cam.location = centre + direction * span
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        out = path.with_name(f"{path.stem}_{group}_{view}{path.suffix or '.png'}")
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        print(f"sheet: {out}")
    bpy.data.objects.remove(cam)
    for o in context:
        bpy.data.objects.remove(o)


def contact_sheets(built, path, cols=4):
    """One sheet per group (items / stations / details), each with a cell size fitted
    to that group's biggest object - a 0.9m cabinet and a 0.05m coin can't share a
    grid, and a sheet that crops is a sheet that doesn't get looked at. Writes
    <path stem>_<group>.png for every group present. The sheet is the check that
    catches what AABB assertions can't (a ring stood on edge, a diamond for a
    square) - never ship a batch without looking at it."""
    groups = {}
    for entry in built:
        groups.setdefault(entry[3], []).append(entry)
    every_obj = [o for e in built for o in e[1] + e[2]]
    scene = bpy.context.scene
    scene.render.engine = 'BLENDER_WORKBENCH'
    scene.display.shading.light = 'STUDIO'
    scene.display.shading.color_type = 'MATERIAL'
    for group, entries in groups.items():
        if group in ASSEMBLED_GROUPS:
            _assembled_sheet(group, [o for e in entries for o in e[1] + e[2]],
                             every_obj, path)
            continue
        cell = 1.3 * max(_extent(e[1] + e[2]) for e in entries)
        for o in every_obj:
            o.hide_render = True
        labels = []
        for i, (name, whole_objs, piece_objs, _) in enumerate(entries):
            cx = (i % cols) * cell * 2
            cy = -(i // cols) * cell
            for o in whole_objs:
                o.location = (cx, cy, 0)
                o.hide_render = False
            for o in piece_objs:
                o.location = (cx + cell * 0.8, cy, 0)
                o.hide_render = False
            curve = bpy.data.curves.new(f"label_{group}_{name}", type='FONT')
            curve.body = name
            curve.size = cell * 0.08
            curve.align_x = 'CENTER'
            label = bpy.data.objects.new(f"label_{group}_{name}", curve)
            label.location = (cx + cell * 0.4, cy - cell * 0.42, 0)
            scene.collection.objects.link(label)
            labels.append(label)
        rows = (len(entries) + cols - 1) // cols
        w, h = cols * cell * 2, rows * cell * 1.2
        scene.render.resolution_x = 1800
        scene.render.resolution_y = max(200, int(1800 * h / w))
        cam_data = bpy.data.cameras.new(f"cam_{group}")
        cam_data.type = 'ORTHO'
        cam_data.ortho_scale = w * 1.05
        cam_data.clip_end = 1000.0
        cam = bpy.data.objects.new(f"cam_{group}", cam_data)
        scene.collection.objects.link(cam)
        centre = Vector((w / 2 - cell * 0.6, -h / 2 + cell * 0.4, 0))
        cam.location = centre + Vector((0, -1.5, 2.6)) * cell
        cam.rotation_euler = (centre - cam.location).to_track_quat('-Z', 'Y').to_euler()
        scene.camera = cam
        out = path.with_name(f"{path.stem}_{group}{path.suffix or '.png'}")
        scene.render.filepath = str(out)
        bpy.ops.render.render(write_still=True)
        print(f"sheet: {out}")
        for label in labels:
            bpy.data.objects.remove(label)


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    assert only in (None, "items", "stations", "details", "player", "customer"), only
    built = build_all(only_group=only)
    if "--sheet" in argv:
        contact_sheets(built, Path(argv[argv.index("--sheet") + 1]).resolve())
