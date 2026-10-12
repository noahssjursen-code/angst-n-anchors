class_name FishingLineShape
extends RefCounted

## Local visual rope: Verlet motion, fixed endpoints and bounded distance solves.
## Does not run rigid bodies or world queries for each line segment.
const COUNT := 25
var points := PackedVector3Array()
var _previous := PackedVector3Array()

func clear() -> void:
	points.clear();_previous.clear()

func advance(dt: float, tip: Vector3, hook: Vector3, slack: float) -> PackedVector3Array:
	var distance:=tip.distance_to(hook)
	var length:=distance+maxf(.01,slack)
	if points.size()!=COUNT or points[0].distance_to(tip)>8 or points[-1].distance_to(hook)>8:
		points.resize(COUNT)
		var sag:=sqrt(maxf(0,length*length-distance*distance))*.45
		for i in COUNT:
			var t:=float(i)/(COUNT-1)
			points[i]=tip.lerp(hook,t)-Vector3.UP*sin(t*PI)*sag
		_previous=points.duplicate()
	var steps:=clampi(ceili(dt*60),1,3)
	var step:=minf(dt,.05)/steps
	var segment:=length/(COUNT-1)
	for substep in steps:
		for i in range(1,COUNT-1):
			var current:=points[i]
			points[i]+=(points[i]-_previous[i])*pow(.92,step*60)+Vector3.DOWN*9.81*step*step
			_previous[i]=current
		for iteration in 12:
			points[0]=tip;points[-1]=hook
			for i in COUNT-1:
				var offset:=points[i+1]-points[i]
				var actual:=offset.length()
				if actual<.00001:continue
				var correction:=offset*(1-segment/actual)
				if i==0:points[i+1]-=correction
				elif i==COUNT-2:points[i]+=correction
				else:points[i]+=correction*.5;points[i+1]-=correction*.5
		points[0]=tip;points[-1]=hook
	return points
