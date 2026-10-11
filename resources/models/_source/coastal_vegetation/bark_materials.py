"""Periodic bark colour/normal textures authored in Blender, no external assets.

Used by build_foliage.py. Plates and lenticels wrap on both axes; normal maps
use wrapped finite differences so the material has no texture-edge seam.
"""
import bpy
import numpy as np
from pathlib import Path

def save_image(path, rgb, linear=False):
    n = rgb.shape[0]
    image = bpy.data.images.new(path.stem, width=n, height=n, alpha=True)
    image.colorspace_settings.name = 'Non-Color' if linear else 'sRGB'
    rgba = np.ones((n,n,4),dtype=np.float32);rgba[:,:,:3] = rgb
    image.pixels.foreach_set(rgba.ravel())
    image.filepath_raw = str(path);image.file_format = 'PNG';image.save()
    return image

def generate(folder):
    n=512; y,x=np.mgrid[0:n,0:n]/n
    rng=np.random.default_rng(47291)
    def noise(sx,sy):
        field=rng.normal(size=(n,n))
        fx=np.fft.fftfreq(n)[None,:];fy=np.fft.fftfreq(n)[:,None]
        field=np.fft.ifft2(np.fft.fft2(field)*np.exp(-((fx*sx)**2+(fy*sy)**2))).real
        return field/max(field.std(),1e-6)
    fine=noise(4,9);large=noise(45,80)
    first=np.full((n,n),100.0);second=first.copy()
    for j in range(6):
        for i in range(16):
            px=(i+rng.uniform(.15,.85))/16;py=(j+rng.uniform(.15,.85))/6
            dx=np.abs(x-px);dx=np.minimum(dx,1-dx)*16
            dy=np.abs(y-py);dy=np.minimum(dy,1-dy)*6
            d=dx*dx+dy*dy
            second=np.minimum(second,np.maximum(first,d));first=np.minimum(first,d)
    plate=np.clip((second-first)*5,0,1)
    height=.12+.55*plate+.035*fine+.04*large
    value=np.clip(.45+.24*plate+.05*large+.025*fine,.15,.9)
    conifer=value[:,:,None]*np.array([.22,.135,.072])[None,None,:]
    marks=np.zeros((n,n))
    for i in range(120):
        px,py=rng.uniform(size=2);dx=np.abs(x-px);dx=np.minimum(dx,1-dx)
        dy=np.abs(y-py);dy=np.minimum(dy,1-dy)
        edge=(dx/rng.uniform(.012,.065))**2+(dy/rng.uniform(.002,.009))**2
        marks=np.maximum(marks,np.clip((1-edge)*4,0,1)*rng.uniform(.45,1))
    birch=np.clip(.64+.04*large+.02*fine-marks*.52,.05,.85)[:,:,None]*np.array([1,.97,.88])[None,None,:]
    for name,color,relief in [('conifer',conifer,height),('birch',birch,.5-marks*.14+.025*fine)]:
        dx=(np.roll(relief,-1,axis=1)-np.roll(relief,1,axis=1))*2.5
        dy=(np.roll(relief,-1,axis=0)-np.roll(relief,1,axis=0))*2.5
        normals=np.stack([-dx,-dy,np.ones_like(dx)],axis=-1)
        normals/=np.linalg.norm(normals,axis=-1,keepdims=True)
        save_image(folder/(name+'_bark_colour.png'),color)
        save_image(folder/(name+'_bark_normal.png'),normals*.5+.5,True)

def material(species,folder):
    kind='birch' if species=='birch' else 'conifer'
    mat=bpy.data.materials.new(species+' Bark');mat.use_nodes=True
    nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF')
    p.inputs['Roughness'].default_value=.94
    color=nodes.new('ShaderNodeTexImage');color.image=bpy.data.images.load(str(folder/(kind+'_bark_colour.png')),check_existing=True)
    normal=nodes.new('ShaderNodeTexImage');normal.image=bpy.data.images.load(str(folder/(kind+'_bark_normal.png')),check_existing=True)
    normal.image.colorspace_settings.name='Non-Color'
    decode=nodes.new('ShaderNodeNormalMap');decode.inputs['Strength'].default_value=.7
    links.new(color.outputs['Color'],p.inputs['Base Color']);links.new(normal.outputs['Color'],decode.inputs['Color']);links.new(decode.outputs['Normal'],p.inputs['Normal'])
    return mat
