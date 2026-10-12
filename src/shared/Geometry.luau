--!nonstrict
-- Pure finite-segment geometry, shared by authoritative projectile simulation
-- and CLI tests. Accepts Roblox Vector3 or a compatible test vector adapter.
local Geometry = {}

function Geometry.closestOnSegment(point, from, to)
	local delta = to - from
	local denominator = delta:Dot(delta)
	local alpha = if denominator > 1e-9 then math.clamp((point - from):Dot(delta) / denominator, 0, 1) else 0
	return alpha, from + delta * alpha
end

-- First contact within [0, 1], never an intersection on an infinite ray.
-- Call with projectile minus target positions at both ends to include target motion.
function Geometry.sphereIntersection(relativeStart, relativeEnd, radius)
	local delta = relativeEnd - relativeStart
	local c = relativeStart:Dot(relativeStart) - radius * radius
	if c <= 0 then return 0 end
	local a = delta:Dot(delta)
	if a < 1e-12 then return nil end
	local b = 2 * relativeStart:Dot(delta)
	local discriminant = b * b - 4 * a * c
	if discriminant < 0 then return nil end
	local first = (-b - math.sqrt(discriminant)) / (2 * a)
	return if first >= 0 and first <= 1 then first else nil
end

return table.freeze(Geometry)
