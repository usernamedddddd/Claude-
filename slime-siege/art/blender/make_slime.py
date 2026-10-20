"""
Slime Siege - slime mesh generator for Blender (3.6+ / 4.x).

How to use:
  1. Blender > Scripting tab > Open > this file > Run Script.
  2. It builds "Slime" (a squishy gumdrop body with eyes and a smile) at the origin,
     about 2 studs wide, as ONE mesh, and exports Slime.fbx + SlimeTexture.png next to
     the .blend file (or to your home folder if the .blend hasn't been saved).
  3. Roblox Studio: Home > Import 3D > Slime.fbx (upload). Select the imported MeshPart
     and copy its MeshId. Upload SlimeTexture.png (Asset Manager > Images) and copy its id.
  4. Paste both into src/shared/Data/Theme.luau -> Theme.Meshes.slime.

One upload covers every slime: the texture is white for the body and dark for the face,
and the game multiplies it by each slime's colour (SpecialMesh.VertexColor), so the body
turns green/blue/... while the eyes and smile stay dark.
"""

import math
import os

import bpy
import bmesh

BODY_RADIUS = 1.0  # Roblox units after export scale (1 Blender unit = 1 stud)
SQUASH = 0.78  # height / width
SEGMENTS = 32
RINGS = 16


def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.materials):
        for item in list(block):
            if item.users == 0:
                block.remove(item)


def material(name, rgb, roughness=0.35):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = roughness
    return mat


def make_body():
    """Gumdrop: a UV sphere with a flattened, slightly flared bottom."""
    mesh = bpy.data.meshes.new("SlimeBody")
    obj = bpy.data.objects.new("Slime", mesh)
    bpy.context.collection.objects.link(obj)

    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=SEGMENTS, v_segments=RINGS, radius=BODY_RADIUS)
    for v in bm.verts:
        x, y, z = v.co
        if z < 0:
            # Flatten the underside and flare it out a little, like a blob sitting on the ground.
            t = -z / BODY_RADIUS
            z = -BODY_RADIUS * 0.35 * (t ** 0.6)
            flare = 1.0 + 0.12 * t
            x, y = x * flare, y * flare
        else:
            z = z * SQUASH * 1.25
        v.co = (x, y, z + BODY_RADIUS * 0.35)
    bm.to_mesh(mesh)
    bm.free()

    for poly in mesh.polygons:
        poly.use_smooth = True
    obj.data.materials.append(material("SlimeBody", (1.0, 1.0, 1.0), 0.25))
    return obj


def make_eye(name, x):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=16, ring_count=8, radius=0.17, location=(x, -0.82, 1.05))
    eye = bpy.context.active_object
    eye.name = name
    eye.scale = (1.0, 0.55, 1.35)
    bpy.ops.object.shade_smooth()
    eye.data.materials.append(material("SlimeEye", (0.05, 0.04, 0.08), 0.2))
    # Small white highlight so the eyes read at a distance.
    bpy.ops.mesh.primitive_uv_sphere_add(segments=8, ring_count=6, radius=0.055, location=(x + 0.05, -0.9, 1.15))
    shine = bpy.context.active_object
    shine.name = name + "Shine"
    shine.data.materials.append(material("SlimeShine", (1.0, 1.0, 1.0), 0.1))
    return [eye, shine]


def make_mouth():
    """A small smile: a torus segment."""
    bpy.ops.mesh.primitive_torus_add(
        major_radius=0.22, minor_radius=0.035, major_segments=24, minor_segments=8, location=(0, -0.9, 0.78)
    )
    mouth = bpy.context.active_object
    mouth.name = "Mouth"
    mouth.rotation_euler = (math.radians(90), 0, 0)
    # Keep only the lower half of the ring.
    bpy.ops.object.mode_set(mode="EDIT")
    bm = bmesh.from_edit_mesh(mouth.data)
    remove = [v for v in bm.verts if (v.co.y > 0.02)]  # local Y is "up" before rotation
    bmesh.ops.delete(bm, geom=remove, context="VERTS")
    bmesh.update_edit_mesh(mouth.data)
    bpy.ops.object.mode_set(mode="OBJECT")
    bpy.ops.object.shade_smooth()
    mouth.data.materials.append(material("SlimeEye", (0.05, 0.04, 0.08), 0.2))
    return mouth


def output_folder():
    return os.path.dirname(bpy.data.filepath) if bpy.data.filepath else os.path.expanduser("~")


def make_texture():
    """4x2 texture: left half white (body), right half near-black (face)."""
    image = bpy.data.images.new("SlimeTexture", width=4, height=2)
    pixels = []
    for _y in range(2):
        for x in range(4):
            pixels += [1.0, 1.0, 1.0, 1.0] if x < 2 else [0.06, 0.05, 0.09, 1.0]
    image.pixels = pixels
    image.filepath_raw = os.path.join(output_folder(), "SlimeTexture.png")
    image.file_format = "PNG"
    image.save()
    mat = bpy.data.materials.new("SlimeTextured")
    mat.use_nodes = True
    nodes = mat.node_tree.nodes
    tex = nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Closest"
    mat.node_tree.links.new(tex.outputs["Color"], nodes.get("Principled BSDF").inputs["Base Color"])
    return mat


def paint_uv(obj, u):
    """Point every face of `obj` at one texel column (body = white, face = dark)."""
    mesh = obj.data
    if not mesh.uv_layers:
        mesh.uv_layers.new(name="UVMap")
    layer = mesh.uv_layers.active
    for loop in layer.data:
        loop.uv = (u, 0.5)


def join(parts, body):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in parts:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = body
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    bpy.ops.object.join()
    return bpy.context.active_object


def export(obj):
    bpy.ops.object.select_all(action="DESELECT")
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    path = os.path.join(output_folder(), "Slime.fbx")
    bpy.ops.export_scene.fbx(
        filepath=path,
        use_selection=True,
        apply_scale_options="FBX_SCALE_UNITS",
        axis_forward="-Z",
        axis_up="Y",
        mesh_smooth_type="FACE",
    )
    print("Slime Siege: exported", path)


def main():
    clear_scene()
    body = make_body()
    face = []
    face += make_eye("EyeL", -0.32)
    face += make_eye("EyeR", 0.32)
    face.append(make_mouth())
    # The eye highlights stay white; the eyes and mouth use the dark half of the texture.
    paint_uv(body, 0.25)
    for obj in face:
        paint_uv(obj, 0.25 if obj.name.endswith("Shine") else 0.75)
    slime = join([body] + face, body)
    slime.name = "Slime"
    slime.data.materials.clear()
    slime.data.materials.append(make_texture())
    # Face looks toward -Y in Blender, which becomes -Z (Roblox "Front") after export.
    export(slime)


main()
