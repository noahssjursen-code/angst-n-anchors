"""Original larger machinery package for Northline's 15-16 knot game tune.

Uses the existing editable V12 construction vocabulary and approved engine
materials. This is fictional machinery, not a certified manufacturer's model.
Metres, Blender +Y bow, exported Godot -Z bow; separate coupling socket.
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODELS = HERE.parents[1]
source = (HERE.parent / 'marine_engines/build_engines.py').read_text(encoding='utf-8')
exec(source.split('\nfor values in')[0])
SRC = HERE
OUT = MODELS / 'machinery'
engine('marine_v12_feeder_high_output', 6.0, 2.85, 3.0, True)
print('NORTHLINE HIGH OUTPUT ENGINE EXPORTED')
