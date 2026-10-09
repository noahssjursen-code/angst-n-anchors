"""Original reusable six-metre accessible terminal approach, approved materials."""
from pathlib import Path
exec((Path(__file__).resolve().parent/'build_ferry.py').read_text(encoding='utf-8').split('\nclear()\n# Slender')[0])
clear()
box('Anti slip deck',(0,0,-.05),(4,6,.10),deck,.015)
for x in [-1.9,1.9]:
    box('Side stringer',(x,0,-.18),(.14,6,.30),steel,.01)
    for y in [-2.9,-1.45,0,1.45,2.9]:
        beam('Guard upright',(x,y,0),(x,y,1.1),.028,steel)
    for z in [.55,1.1]:beam('Handrail',(x,-3,z),(x,3,z),.031,steel)
    box('Toe protection',(x,0,.07),(.045,6,.14),steel)
for y in [-2.98,2.98]:box('Landing threshold',(0,y,.006),(3.7,.035,.012),dark)
export('terminal_shore_ramp_6m',ROOT/'parts/passenger_terminal')
