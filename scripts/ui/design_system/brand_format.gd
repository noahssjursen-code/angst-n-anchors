class_name BrandFormat
extends RefCounted

## Canonical brand formatting for trusted instrument and economy data.

static func money(amount: int) -> String:
	var negative := amount < 0
	var digits := str(absi(amount))
	var groups: Array[String] = []
	while digits.length() > 3:
		groups.push_front(digits.right(3))
		digits = digits.left(digits.length() - 3)
	groups.push_front(digits)
	return "%s%s" % ["-" if negative else "", " ".join(PackedStringArray(groups))]


static func money_text(amount: int) -> String:
	return "ℳ %s" % money(amount)


static func heading(degrees: float) -> String:
	return "%03d°" % int(roundf(wrapf(degrees, 0.0, 360.0)))


static func speed_knots(value: float) -> String:
	return "%.1f KN" % value


static func distance_metres(value: float) -> String:
	if absf(value) >= 1000.0:
		return "%.1f KM" % (value / 1000.0)
	return "%d M" % int(roundf(value))


static func mass_tonnes(value: float) -> String:
	return "%.1f T" % value


static func time_24h(hours: float) -> String:
	var total_minutes := int(floorf(hours * 60.0))
	return "%02d:%02d" % [posmod(int(total_minutes / 60.0), 24), posmod(total_minutes, 60)]
