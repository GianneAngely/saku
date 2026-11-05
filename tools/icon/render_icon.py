"""Renders Saku's clay icon in Blender, headless (tools/make-icon.sh --render runs it):
  Blender -b --factory-startup -P render_icon.py -- icon|mark OUT.png [samples] [size]
A smooth plasticine sakura on a purple clay night sky with clay stars and dots, the notch pressed in at the top.
Everything is real geometry with a clay shader (soft edges, dents, fingerprints), lit softly from the top left."""
import bpy, bmesh, math, random, sys, os

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shapes                    # notch and petal outlines on the 1024 px canvas

argv = sys.argv[sys.argv.index("--") + 1:]
PART, OUT = argv[0], argv[1]
SAMPLES = int(argv[2]) if len(argv) > 2 else 160
RES = int(argv[3]) if len(argv) > 3 else 1024
random.seed(7)

S = 512.0                        # px per Blender unit: the 1024 canvas spans -1..1
def u(x, y):                     # canvas px -> Blender XY (y up)
    return ((x - 512) / S, (512 - y) / S)

def hexc(h, a=1.0):
    h = h.lstrip("#")
    srgb = [int(h[i:i + 2], 16) / 255 for i in (0, 2, 4)]
    lin = [c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4 for c in srgb]
    return (*lin, a)

# ---------- scene ----------
scene = bpy.context.scene
for o in list(bpy.data.objects):
    bpy.data.objects.remove(o, do_unlink=True)
scene.render.engine = "CYCLES"
scene.cycles.samples = SAMPLES
scene.cycles.use_denoising = True
scene.render.resolution_x = scene.render.resolution_y = RES
scene.render.film_transparent = True
scene.render.image_settings.file_format = "PNG"
scene.render.image_settings.color_mode = "RGBA"
scene.view_settings.view_transform = "Standard"
try:
    prefs = bpy.context.preferences.addons["cycles"].preferences
    prefs.compute_device_type = "METAL"
    prefs.get_devices()
    for d in prefs.devices:
        d.use = True
    scene.cycles.device = "GPU"
except Exception as e:
    print("GPU setup failed, CPU render:", e)

world = bpy.data.worlds.new("w")
scene.world = world
world.use_nodes = True
bg = world.node_tree.nodes["Background"]
bg.inputs[0].default_value = hexc("#D8D0DC")
bg.inputs[1].default_value = 0.16

cam_data = bpy.data.cameras.new("cam")
cam_data.type = "ORTHO"
cam_data.ortho_scale = 2.0
cam = bpy.data.objects.new("cam", cam_data)
cam.location = (0, 0, 6)
scene.collection.objects.link(cam)
scene.camera = cam

def area(name, loc, size, energy, color="#FFFFFF"):
    l = bpy.data.lights.new(name, "AREA")
    l.size = size
    l.energy = energy
    l.color = hexc(color)[:3]
    o = bpy.data.objects.new(name, l)
    o.location = loc
    d = [-c for c in loc]
    o.rotation_euler = (0, 0, 0)
    o.rotation_mode = "QUATERNION"
    from mathutils import Vector
    o.rotation_quaternion = Vector(d).to_track_quat("-Z", "Y")
    scene.collection.objects.link(o)
    return o

area("key", (-3.0, 3.2, 4.6), 3.0, 900, "#FFF1E4")
area("fill", (3.5, -2.5, 4.0), 5.0, 140, "#E9E6FF")
area("top", (0.0, 0.0, 6.0), 6.0, 160, "#FFFFFF")

# ---------- clay material ----------
def clay(name, color, rough=0.62, sss=0.12, print_strength=0.45, dents=0.22, gloss=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    n, l = nt.nodes, nt.links
    for x in list(n):
        n.remove(x)
    out = n.new("ShaderNodeOutputMaterial")
    b = n.new("ShaderNodeBsdfPrincipled")
    b.inputs["Base Color"].default_value = hexc(color)
    b.inputs["Roughness"].default_value = rough
    for key, val in (("Subsurface Weight", sss), ("Subsurface Scale", 0.03), ("Specular IOR Level", 0.35),
                     ("Coat Weight", gloss), ("Coat Roughness", 0.25), ("Sheen Weight", 0.15)):
        if key in b.inputs:
            b.inputs[key].default_value = val
    if "Subsurface Radius" in b.inputs:
        b.inputs["Subsurface Radius"].default_value = (1.0, 0.45, 0.35)
    l.new(b.outputs[0], out.inputs[0])

    tc = n.new("ShaderNodeTexCoord")
    info = n.new("ShaderNodeObjectInfo")
    # per-object offset so no two pieces share a fingerprint
    add = n.new("ShaderNodeVectorMath"); add.operation = "ADD"
    l.new(tc.outputs["Object"], add.inputs[0])
    l.new(info.outputs["Random"], add.inputs[1])

    # soft dents from handling
    dent = n.new("ShaderNodeTexNoise"); dent.inputs["Scale"].default_value = 2.2; dent.inputs["Detail"].default_value = 3
    l.new(add.outputs[0], dent.inputs["Vector"])
    # fine grain
    grain = n.new("ShaderNodeTexNoise"); grain.inputs["Scale"].default_value = 140; grain.inputs["Detail"].default_value = 2
    l.new(add.outputs[0], grain.inputs["Vector"])
    # fingerprint: distorted rings, only in a few soft patches
    wave = n.new("ShaderNodeTexWave"); wave.wave_type = "RINGS"; wave.inputs["Scale"].default_value = 26
    wave.inputs["Distortion"].default_value = 4.5; wave.inputs["Detail"].default_value = 1.5
    l.new(add.outputs[0], wave.inputs["Vector"])
    mask = n.new("ShaderNodeTexNoise"); mask.inputs["Scale"].default_value = 2.4
    l.new(add.outputs[0], mask.inputs["Vector"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].position = 0.48
    ramp.color_ramp.elements[1].position = 0.66
    l.new(mask.outputs["Fac"], ramp.inputs["Fac"])
    mul = n.new("ShaderNodeMath"); mul.operation = "MULTIPLY"
    l.new(wave.outputs["Fac"], mul.inputs[0])
    l.new(ramp.outputs["Color"], mul.inputs[1])

    b1 = n.new("ShaderNodeBump"); b1.inputs["Strength"].default_value = dents; b1.inputs["Distance"].default_value = 0.02
    l.new(dent.outputs["Fac"], b1.inputs["Height"])
    b2 = n.new("ShaderNodeBump"); b2.inputs["Strength"].default_value = print_strength; b2.inputs["Distance"].default_value = 0.002
    l.new(mul.outputs[0], b2.inputs["Height"])
    l.new(b1.outputs["Normal"], b2.inputs["Normal"])
    b3 = n.new("ShaderNodeBump"); b3.inputs["Strength"].default_value = 0.06; b3.inputs["Distance"].default_value = 0.001
    l.new(grain.outputs["Fac"], b3.inputs["Height"])
    l.new(b2.outputs["Normal"], b3.inputs["Normal"])
    l.new(b3.outputs["Normal"], b.inputs["Normal"])
    return m

# ---------- geometry helpers ----------
def poly_object(name, pts, z0, height, mat, voxel=0.008, smooth=12, smooth_factor=0.9, sub=1):
    """Extruded outline, voxel-remeshed and smoothed so every edge turns soft and puffy like pressed clay."""
    me = bpy.data.meshes.new(name)
    bm = bmesh.new()
    vs = [bm.verts.new((x, y, z0)) for x, y in pts]
    f = bm.faces.new(vs)
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    for v in [e for e in ext["geom"] if isinstance(e, bmesh.types.BMVert)]:
        v.co.z += height
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = bpy.data.objects.new(name, me)
    scene.collection.objects.link(o)
    r = o.modifiers.new("remesh", "REMESH"); r.mode = "VOXEL"; r.voxel_size = voxel; r.use_smooth_shade = True
    s = o.modifiers.new("smooth", "SMOOTH"); s.factor = smooth_factor; s.iterations = smooth
    if sub:
        d = o.modifiers.new("sub", "SUBSURF"); d.levels = sub; d.render_levels = sub
    o.data.materials.append(mat)
    return o

def flat_pts(path_d, step=1):
    pts = shapes.flatten(path_d, steps=10)[0]
    out = [u(x, y) for x, y in pts[::step]]
    # drop duplicates that would break the face
    clean = []
    for p in out:
        if not clean or abs(p[0] - clean[-1][0]) + abs(p[1] - clean[-1][1]) > 1e-4:
            clean.append(p)
    if abs(clean[0][0] - clean[-1][0]) + abs(clean[0][1] - clean[-1][1]) < 1e-4:
        clean.pop()
    return clean

def sparkle_pts(cx, cy, r, steps=12):
    """Four-point twinkle with curved sides (same shape as the flat logos), in Blender units."""
    c = r * 0.18
    corners = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    ctrls = [(cx + c, cy - c), (cx + c, cy + c), (cx - c, cy + c), (cx - c, cy - c)]
    pts = []
    for k in range(4):
        p0, p1, p2 = corners[k], ctrls[k], corners[(k + 1) % 4]
        for i in range(steps):
            t = i / steps
            x = (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * p1[0] + t * t * p2[0]
            y = (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * p1[1] + t * t * p2[1]
            pts.append(u(x, y))
    return pts

def squircle_pts(n=5.0, steps=240, inset=0.0):
    a = 824 / 2 / S - inset
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        c, s = math.cos(t), math.sin(t)
        pts.append((a * math.copysign(abs(c) ** (2 / n), c), a * math.copysign(abs(s) ** (2 / n), s)))
    return pts

TILE_TOP = 0.16

def sky_tile():
    """The night-sky clay slab, deep indigo at the top to plum at the bottom."""
    m = clay("sky", "#3B2466", rough=0.64, print_strength=0.28)
    nt = m.node_tree; n = nt.nodes; l = nt.links
    b = next(x for x in n if x.type == "BSDF_PRINCIPLED")
    tc = n.new("ShaderNodeTexCoord")
    sep = n.new("ShaderNodeSeparateXYZ")
    l.new(tc.outputs["Object"], sep.inputs[0])
    mr = n.new("ShaderNodeMapRange")
    mr.inputs["From Min"].default_value = 0.805; mr.inputs["From Max"].default_value = -0.805
    l.new(sep.outputs["Y"], mr.inputs["Value"])
    ramp = n.new("ShaderNodeValToRGB")
    ramp.color_ramp.elements[0].color = hexc("#2B1D52")
    ramp.color_ramp.elements[1].color = hexc("#5E2B6A")
    l.new(mr.outputs["Result"], ramp.inputs["Fac"])
    l.new(ramp.outputs["Color"], b.inputs["Base Color"])
    return poly_object("tile", squircle_pts(), 0.0, TILE_TOP, m, voxel=0.01, smooth=24, smooth_factor=1.0)

def notch_slab():
    m = clay("notch", "#231D2A", rough=0.5, print_strength=0.3)
    pts = flat_pts(shapes.notch(w=388, h=176, r=72, top=shapes.T0 + 2))
    o = poly_object("notch", pts, TILE_TOP - 0.03, 0.075, m, voxel=0.007, smooth=10)
    lens = bpy.data.objects.new("lens", bpy.data.meshes.new("lens"))
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=32, v_segments=16, radius=0.032); bm.to_mesh(lens.data); bm.free()
    lens.data.shade_smooth()
    lens.location = (*u(512, 160), TILE_TOP + 0.04)
    lens.scale = (1, 1, 0.55)
    glass = bpy.data.materials.new("lens"); glass.use_nodes = True
    pb = glass.node_tree.nodes["Principled BSDF"]
    pb.inputs["Base Color"].default_value = hexc("#141A3A"); pb.inputs["Roughness"].default_value = 0.12
    lens.data.materials.append(glass)
    scene.collection.objects.link(lens)
    return o

# ---------- the sakura ----------
def sakura(with_tile=True):
    CX, CY = 512.0, 540.0
    if with_tile:
        sky_tile()
        notch_slab()
    pink = clay("petal", "#FF7FB8", rough=0.56, print_strength=0.4)
    # deeper pink near the centre, lighter at the tips, like a real sakura
    nt = pink.node_tree; nn = nt.nodes; ll = nt.links
    bsdf = next(x for x in nn if x.type == "BSDF_PRINCIPLED")
    geom = nn.new("ShaderNodeNewGeometry")
    centre = nn.new("ShaderNodeCombineXYZ"); centre.inputs[0].default_value, centre.inputs[1].default_value = u(CX, CY)
    dist = nn.new("ShaderNodeVectorMath"); dist.operation = "DISTANCE"
    ll.new(geom.outputs["Position"], dist.inputs[0]); ll.new(centre.outputs[0], dist.inputs[1])
    mr = nn.new("ShaderNodeMapRange"); mr.inputs["From Min"].default_value = 0.1; mr.inputs["From Max"].default_value = 0.5
    ll.new(dist.outputs["Value"], mr.inputs["Value"])
    pr = nn.new("ShaderNodeValToRGB")
    pr.color_ramp.elements[0].color = hexc("#EC4A95"); pr.color_ramp.elements[1].color = hexc("#FF88C1")
    ll.new(mr.outputs["Result"], pr.inputs["Fac"])
    ll.new(pr.outputs["Color"], bsdf.inputs["Base Color"])
    PH = 0.12
    for i in range(5):
        pts = flat_pts(shapes.petal(CX, CY, i * 72, w=212, t=268))
        o = poly_object(f"petal{i}", pts, TILE_TOP + 0.005, PH, pink, voxel=0.006, smooth=30, smooth_factor=1.0, sub=0)
        mx = sum(p[0] for p in pts) / len(pts); my = sum(p[1] for p in pts) / len(pts)
        for v in o.data.vertices:
            v.co.x -= mx; v.co.y -= my; v.co.z -= TILE_TOP
        o.location = (mx, my, TILE_TOP)
        cast = o.modifiers.new("dome", "CAST"); cast.cast_type = "SPHERE"; cast.factor = 0.55
        cast.use_x = False; cast.use_y = False; cast.use_z = True
        sd = o.modifiers.new("sub", "SUBSURF"); sd.levels = 1; sd.render_levels = 1
        o.rotation_euler = (random.uniform(-0.03, 0.03), random.uniform(-0.03, 0.03), 0)
        a = math.radians(i * 72)
    # centre ball and stamens
    yellow = clay("centre", "#FFCF4D", rough=0.55, print_strength=0.15)
    orange = clay("stamen", "#F0902E", rough=0.5, print_strength=0.05)
    c = bpy.data.objects.new("centre", bpy.data.meshes.new("centre"))
    bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=48, v_segments=24, radius=0.115); bm.to_mesh(c.data); bm.free()
    c.data.shade_smooth()
    c.location = (*u(CX, CY), TILE_TOP + 0.125)
    c.scale = (1, 1, 0.5)
    c.data.materials.append(yellow)
    scene.collection.objects.link(c)
    for k in range(9):
        a = 2 * math.pi * k / 9 + 0.3
        s = bpy.data.objects.new(f"st{k}", bpy.data.meshes.new(f"st{k}"))
        bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=0.026); bm.to_mesh(s.data); bm.free()
        s.data.shade_smooth()
        x, y = u(CX, CY)
        s.location = (x + 0.072 * math.cos(a), y + 0.072 * math.sin(a), TILE_TOP + 0.17)
        s.data.materials.append(orange)
        scene.collection.objects.link(s)
    if not with_tile:
        return
    # clay stars and dots in the night sky
    butter = clay("star", "#FFD66B", rough=0.55, print_strength=0.12)
    white = clay("dot", "#FFF6E8", rough=0.55, print_strength=0.0)
    lilac = clay("lilac", "#C7A6FF", rough=0.55, print_strength=0.0)
    for (x, y, r) in [(235, 395, 44), (800, 300, 30), (805, 760, 34)]:
        poly_object(f"spark{x}", sparkle_pts(x, y, r), TILE_TOP - 0.01, 0.06, butter, voxel=0.005, smooth=14)
    for (x, y, rad, mat) in [(180, 560, 0.016, white), (300, 250, 0.013, white), (720, 220, 0.015, lilac), (860, 520, 0.014, white),
                             (690, 845, 0.013, lilac), (330, 830, 0.016, white), (175, 300, 0.012, lilac), (880, 650, 0.012, white)]:
        d = bpy.data.objects.new(f"dot{x}", bpy.data.meshes.new(f"dot{x}"))
        bm = bmesh.new(); bmesh.ops.create_uvsphere(bm, u_segments=16, v_segments=8, radius=rad); bm.to_mesh(d.data); bm.free()
        d.data.shade_smooth()
        d.location = (*u(x, y), TILE_TOP)
        d.scale = (1, 1, 0.6)
        d.data.materials.append(mat)
        scene.collection.objects.link(d)

# ---------- go ----------
sakura(with_tile=(PART == "icon"))
if PART == "mark":
    # tight on the flower, no sky
    cam_data.ortho_scale = 1.22
    cam.location = (0, u(512, 540)[1] + 0.02, 6)
    bg.inputs[1].default_value = 0.6
scene.render.filepath = OUT
bpy.ops.render.render(write_still=True)
print("rendered", OUT)
