extends RefCounted
## Deterministic swept reservations, shared by visible and off-screen residents.
## Bodies have 12px feet radii; 32px leaves an additional personal-space margin.
const SPACING := 32.0

static func free_segment(origin: Vector2, end: Vector2, id: String, people: Dictionary, location: String, navigation: RefCounted) -> bool:
	if not navigation.clear_segment(origin,end):
		return false
	for other in people:
		if other==id or people[other].location!=location:
			continue
		var person: Dictionary=people[other]
		# Reserve the entire movement of already updated neighbours as well as
		# their starting point. Interpolation cannot cross another resident.
		for point in [person.position,person.previous]:
			var before: float=origin.distance_to(point)
			var closest: float=Geometry2D.get_closest_point_to_segment(point,origin,end).distance_to(point)
			if before<SPACING-0.01:
				# Old saves may contain overlaps: only a gradual separating step is legal.
				if end.distance_to(point)<=before+0.01:
					return false
			elif closest<SPACING-0.01:
				return false
	return true

static func steer(origin: Vector2, desired: Vector2, id: String, people: Dictionary, location: String, navigation: RefCounted) -> Vector2:
	if free_segment(origin,desired,id,people,location,navigation):
		return desired
	var direction:=origin.direction_to(desired)
	var length:=minf(12,origin.distance_to(desired))
	# Both approaching walkers keep to their own right. Fixed order avoids jitter.
	for angle in [PI/4,PI/2,3*PI/4,-PI/4,-PI/2]:
		var candidate:=origin+direction.rotated(angle)*length
		if free_segment(origin,candidate,id,people,location,navigation):
			return candidate
	return origin

static func occupied(point: Vector2, id: String, people: Dictionary, location: String, spacing: float = SPACING) -> bool:
	for other in people:
		if other!=id and people[other].location==location and point.distance_to(people[other].position)<spacing:
			return true
	return false

static func escape(origin: Vector2, id: String, people: Dictionary, location: String, navigation: RefCounted) -> Vector2:
	var ids: Array=people.keys()
	ids.sort()
	var away:=Vector2.ZERO
	for other in people:
		if other!=id and people[other].location==location:
			var offset: Vector2=origin-people[other].position
			if offset.length()>0.01 and offset.length()<96:
				away+=offset.normalized()*(96-offset.length())
	var angle:=away.angle() if away.length()>0.01 else TAU*float(ids.find(id))/float(maxi(1,ids.size()))
	for index in range(16):
		var end:=origin+Vector2.from_angle(angle+float(index)*TAU/16)*12
		if free_segment(origin,end,id,people,location,navigation):
			return end
	return origin
