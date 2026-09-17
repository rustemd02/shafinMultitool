#!/usr/bin/env python3
"""Original SET OS procedural blocking assets, version 1.

The generator uses only the Python standard library and Apple's installed usdcat.
It never reads original meshes, textures, scenes, or the source repository. The
numeric output bounds retain the existing app's placement and scale contract.
All shape parameters and topology are authored in this file for this task.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import subprocess
import zipfile

VERSION = "setos-procedural-ar-v1"
TARGET_BOUNDS = {
    "Circle": ((-0.125168696, 0.0, -0.125168696), (0.125168696, 0.002, 0.125168696)),
    "Person": ((-0.292125016, -0.002830000, -0.092654996), (0.292125016, 1.034204960, 0.095850006)),
}


def add(a, b): return tuple(x + y for x, y in zip(a, b))
def sub(a, b): return tuple(x - y for x, y in zip(a, b))
def mul(a, s): return tuple(x * s for x in a)
def dot(a, b): return sum(x * y for x, y in zip(a, b))
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a): return math.sqrt(dot(a, a))
def unit(a): return mul(a, 1 / norm(a))


class Mesh:
    def __init__(self):
        self.points = []
        self.faces = []
        self.parts = []

    def component(self, name, points, faces):
        offset = len(self.points)
        self.points.extend(points)
        self.faces.extend(tuple(i + offset for i in face) for face in faces)
        self.parts.append({"name": name, "first_vertex": offset, "vertex_count": len(points), "triangle_count": len(faces)})

    def ellipsoid(self, name, center, radii, segments=24, rings=14):
        points = [add(center, (0, radii[1], 0))]
        for row in range(1, rings):
            phi = math.pi * row / rings
            for column in range(segments):
                theta = 2 * math.pi * column / segments
                points.append(add(center, (radii[0]*math.sin(phi)*math.cos(theta), radii[1]*math.cos(phi), radii[2]*math.sin(phi)*math.sin(theta))))
        bottom = len(points)
        points.append(add(center, (0, -radii[1], 0)))
        faces = []
        for j in range(segments):
            k = (j + 1) % segments
            faces.append((0, 1+k, 1+j))
        for row in range(rings-2):
            a = 1 + row*segments
            b = a + segments
            for j in range(segments):
                k = (j+1) % segments
                faces.extend(((a+j, a+k, b+k), (a+j, b+k, b+j)))
        a = 1 + (rings-2)*segments
        for j in range(segments):
            k = (j+1) % segments
            faces.append((a+j, a+k, bottom))
        self.component(name, points, faces)

    def loft(self, name, profile, segments=32):
        """Closed elliptical cross sections around Y; profile=(y,rx,rz,z)."""
        points = []
        for y, rx, rz, z in profile:
            for j in range(segments):
                t = 2*math.pi*j/segments
                points.append((rx*math.cos(t), y, z+rz*math.sin(t)))
        faces = []
        for row in range(len(profile)-1):
            a, b = row*segments, (row+1)*segments
            for j in range(segments):
                k=(j+1)%segments
                faces.extend(((a+j,b+k,a+k),(a+j,b+j,b+k)))
        lo = len(points); points.append((0, profile[0][0], profile[0][3]))
        hi = len(points); points.append((0, profile[-1][0], profile[-1][3]))
        for j in range(segments):
            k=(j+1)%segments
            faces.extend(((lo,j,k),(hi,(len(profile)-1)*segments+k,(len(profile)-1)*segments+j)))
        self.component(name, points, faces)

    def limb(self, name, start, end, radii, depth=1.0, segments=20):
        axis = unit(sub(end, start))
        side = unit(cross(axis, (0, 0, 1)))
        front = unit(cross(side, axis))
        points = []
        for t,r in radii:
            center=add(start,mul(sub(end,start),t))
            for j in range(segments):
                angle=2*math.pi*j/segments
                points.append(add(center,add(mul(side,r*math.cos(angle)),mul(front,r*depth*math.sin(angle)))))
        faces=[]
        for row in range(len(radii)-1):
            a,b=row*segments,(row+1)*segments
            for j in range(segments):
                k=(j+1)%segments
                faces.extend(((a+j,a+k,b+k),(a+j,b+k,b+j)))
        lo=len(points);points.append(start)
        hi=len(points);points.append(end)
        for j in range(segments):
            k=(j+1)%segments
            faces.extend(((lo,k,j),(hi,(len(radii)-1)*segments+j,(len(radii)-1)*segments+k)))
        self.component(name,points,faces)

    def fit_bounds(self, target):
        before=self.bounds()
        scales=[(target[1][i]-target[0][i])/(before[1][i]-before[0][i]) for i in range(3)]
        self.points=[tuple(round(target[0][i]+(p[i]-before[0][i])*scales[i],9) for i in range(3)) for p in self.points]
        return scales

    def bounds(self):
        return tuple(tuple(fn(p[i] for p in self.points) for i in range(3)) for fn in (min,max))

    def validated_normals(self):
        normals=[(0.0,0.0,0.0) for p in self.points]
        part_ranges=[]
        face_index=0
        for part in self.parts:
            # Each authored component is closed. Signed volume fixes outward
            # winding without using any imported mesh or face ordering.
            end=face_index+part['triangle_count']
            volume=sum(dot(self.points[a],cross(self.points[b],self.points[c]))/6 for a,b,c in self.faces[face_index:end])
            if volume < 0:
                self.faces[face_index:end]=[(a,c,b)for a,b,c in self.faces[face_index:end]]
                volume=-volume
            assert volume>1e-12,(part['name'],volume)
            part_ranges.append({'name':part['name'],'signed_volume':volume})
            face_index=end
        minimum_area=float('inf')
        for a,b,c in self.faces:
            assert len({a,b,c})==3
            normal=cross(sub(self.points[b],self.points[a]),sub(self.points[c],self.points[a]))
            area=norm(normal)/2
            minimum_area=min(minimum_area,area)
            assert area>1e-14, (a,b,c,area)
            for index in (a,b,c):normals[index]=add(normals[index],normal)
        assert all(math.isfinite(v) for p in self.points for v in p)
        normals=[unit(n) for n in normals]
        return normals,minimum_area,part_ranges


def circle():
    mesh=Mesh()
    # Thin solid waypoint disk, with a small chamfer for a readable edge.
    mesh.loft('waypoint_disk',[(0,.124668696,.124668696,0),(.0003,.125168696,.125168696,0),(.0017,.125168696,.125168696,0),(.002,.124668696,.124668696,0)],64)
    return mesh


def person():
    mesh=Mesh()
    # Neutral adult blocking mannequin: standing A pose, two feet, two hands
    # with separate fingers, distinct head/neck, and a small front-facing nose.
    # Proportions are hand-authored; this is not an anatomical scan or likeness.
    mesh.loft('torso',[(.475,.058,.047,0),(.505,.084,.059,0),(.555,.089,.064,0),(.62,.078,.060,-.006),(.685,.09,.069,-.008),(.76,.115,.075,-.006),(.81,.133,.060,-.008),(.845,.106,.048,-.01),(.865,.043,.039,-.006)])
    mesh.ellipsoid('pelvis',(0,.511,-.003),(.090,.079,.063))
    mesh.ellipsoid('neck',(0,.867,-.004),(.038,.042,.036))
    mesh.ellipsoid('head',(0,.941,.002),(.062,.097,.065),32,20)
    mesh.ellipsoid('chin',(0,.895,.039),(.036,.025,.034),24,12)
    mesh.ellipsoid('nose',(0,.944,.063),(.010,.020,.018),16,12)
    for side,label in [(-1,'left'),(1,'right')]:
        mesh.ellipsoid(label+'_ear',(side*.061,.942,.002),(.012,.023,.015),16,12)
        shoulder=(side*.124,.811,-.004)
        elbow=(side*.199,.676,.0)
        wrist=(side*.247,.551,.011)
        mesh.ellipsoid(label+'_shoulder',shoulder,(.041,.052,.046))
        mesh.limb(label+'_upper_arm',shoulder,elbow,[(0,.035),(.18,.039),(.48,.035),(.82,.027),(1,.024)],1.05)
        mesh.ellipsoid(label+'_elbow',elbow,(.025,.027,.025))
        mesh.limb(label+'_forearm',elbow,wrist,[(0,.026),(.22,.032),(.5,.028),(.8,.020),(1,.017)],.9)
        mesh.ellipsoid(label+'_palm',(side*.257,.524,.014),(.023,.038,.014),20,14)
        for index,(offset,length) in enumerate([(-.015,.040),(-.005,.047),(.005,.044),(.014,.035)]):
            start=(side*(.258+offset),.504,.015)
            end=(side*(.272+offset),.504-length,.017)
            mesh.limb(label+'_finger_'+str(index+1),start,end,[(0,.0055),(.45,.005),(1,.0035)],.85,12)
            mesh.ellipsoid(label+'_fingertip_'+str(index+1),end,(.0035,.004,.0035),12,8)
        mesh.limb(label+'_thumb',(side*.240,.527,.018),(side*.228,.497,.031),[(0,.007),(.55,.006),(1,.0045)],.9,12)
        mesh.ellipsoid(label+'_thumbtip',(side*.228,.497,.031),(.0045,.006,.0045),12,8)
        hip=(side*.059,.512,-.003)
        knee=(side*.064,.282,.008)
        ankle=(side*.068,.060,-.006)
        mesh.ellipsoid(label+'_hip',hip,(.049,.060,.056))
        mesh.limb(label+'_thigh',hip,knee,[(0,.045),(.25,.052),(.5,.047),(.8,.035),(1,.029)],1.05,24)
        mesh.ellipsoid(label+'_knee',knee,(.03,.034,.033))
        mesh.limb(label+'_calf',knee,ankle,[(0,.028),(.24,.037),(.45,.036),(.75,.025),(1,.019)],1.04,24)
        mesh.ellipsoid(label+'_ankle',ankle,(.021,.030,.024),20,12)
        mesh.ellipsoid(label+'_foot',(side*.068,.028,.032),(.035,.028,.073),24,12)
    return mesh


def number(value):
    if abs(value)<.0000000005:return '0'
    return format(value,'.9f').rstrip('0').rstrip('.')


def triple(value):return '('+', '.join(number(x)for x in value)+')'


def write_layer(name,mesh,normals):
    lo,hi=mesh.bounds()
    return '\n'.join([
        '#usda 1.0','(',f'    defaultPrim = "{name}"','    metersPerUnit = 1','    upAxis = "Y"',
        '    customLayerData = {',f'        string generator = "{VERSION}"',
        '        string provenance = "Original AI-assisted procedural geometry authored for SET OS; no imported mesh or texture."','    }',')','',
        f'def Xform "{name}" (kind = "component")','{',
        '    def Mesh "Geometry" (prepend apiSchemas = ["MaterialBindingAPI"])','    {',
        '        uniform token subdivisionScheme = "none"','        uniform token orientation = "rightHanded"','        bool doubleSided = false',
        '        point3f[] points = ['+', '.join(triple(p)for p in mesh.points)+']',
        '        int[] faceVertexCounts = ['+', '.join('3'for _ in mesh.faces)+']',
        '        int[] faceVertexIndices = ['+', '.join(str(i)for face in mesh.faces for i in face)+']',
        '        normal3f[] normals = ['+', '.join(triple(p)for p in normals)+'] (interpolation = "vertex")',
        '        float3[] extent = ['+triple(lo)+', '+triple(hi)+']',
        f'        rel material:binding = </{name}/Materials/Body>','    }',
        '    def Scope "Materials"','    {','        def Material "Body"','        {',
        f'            token outputs:surface.connect = </{name}/Materials/Body/Surface.outputs:surface>',
        '            def Shader "Surface"','            {','                uniform token info:id = "UsdPreviewSurface"',
        '                color3f inputs:diffuseColor = (1, 1, 1)','                float inputs:roughness = 0.55',
        '                float inputs:metallic = 0','                float inputs:opacity = 1','                token outputs:surface',
        '            }','        }','    }','}',''])


def package_usdz(source,destination):
    # USDZ requires uncompressed ZIP and 64-byte aligned file data. Freeze all
    # archive metadata, including timestamp, so repeated output is identical.
    with zipfile.ZipFile(destination,'w',compression=zipfile.ZIP_STORED) as archive:
        info=zipfile.ZipInfo(source.name,date_time=(2026,9,16,0,0,0))
        info.compress_type=zipfile.ZIP_STORED
        info.create_system=3
        info.external_attr=0o100644<<16
        base=30+len(info.filename.encode())
        padding=(-base)%64
        if 0<padding<4:padding+=64
        if padding:info.extra=struct.pack('<HH',0x1986,padding-4)+bytes(padding-4)
        archive.writestr(info,source.read_bytes())
    with zipfile.ZipFile(destination)as archive:
        info=archive.infolist()[0]
        offset=info.header_offset+30+len(info.filename.encode())+len(info.extra)
        assert offset%64==0
        assert info.compress_type==zipfile.ZIP_STORED


def digest(path):return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    args.output.mkdir(parents=True,exist_ok=False)
    manifest={'schema':'setos-original-ar-assets-v1','generator':VERSION,'generator_sha256':digest(Path(__file__)),
              'authorship':'AI-assisted original procedural code and geometry produced for SET OS in this task; no human authorship claim.',
              'third_party_geometry':False,'external_textures':False,'source_mesh_read':False,
              'scope':'Candidate; native decode/render and app integration must be verified separately.','assets':[]}
    for name,builder in [('Circle',circle),('Person',person)]:
        mesh=builder();scale=mesh.fit_bounds(TARGET_BOUNDS[name]);normals,min_area,parts=mesh.validated_normals()
        usda=args.output/(name+'.usda');usda.write_text(write_layer(name,mesh,normals),encoding='utf-8')
        usdc=args.output/(name+'.usdc')
        result=subprocess.run(['/usr/bin/usdcat',str(usda),'-o',str(usdc)],capture_output=True,text=True,timeout=30)
        (args.output/(name+'.convert.log')).write_text(result.stdout+result.stderr)
        if result.returncode:raise RuntimeError(f'{name} conversion failed: {result.returncode}')
        usdz=args.output/(name+'.usdz');package_usdz(usdc,usdz)
        manifest['assets'].append({'name':name,'bounds':mesh.bounds(),'normal_count':len(normals),'vertex_count':len(mesh.points),'triangles':len(mesh.faces),
             'native_units':'metres','up_axis':'Y','front_axis':'+Z' if name=='Person' else None,'root_transform':'identity',
             'material_count':1,'material':'white opaque neutral roughness 0.55 metallic 0',
             'normalization_scale':scale,'minimum_triangle_area':min_area,'components':parts,
             'self_intersection_policy':'Joined limbs are overlapping closed component shells in one mesh; no skinning or physical simulation is claimed.',
             'files':[{'path':p.name,'bytes':p.stat().st_size,'sha256':digest(p)}for p in (usda,usdc,usdz)]})
    (args.output/'generation-receipt.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    print(json.dumps({'output':str(args.output),'assets':[{k:a[k]for k in ['name','bounds','vertex_count','triangles','files']}for a in manifest['assets']]}))


if __name__=='__main__':main()
