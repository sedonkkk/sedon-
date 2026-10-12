--!nonstrict
-- Pure screen-space acquisition. Persistence and character lifetime belong
-- to Session; being offscreen later must never invalidate an existing lock.
local Selection = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function components(value)
	local kind = typeof(value)
	if type(value) ~= "table" and kind ~= "Vector2" and kind ~= "Vector3" then
		return nil
	end
	if not finite(value.X) or not finite(value.Y) then
		return nil
	end
	return value.X, value.Y
end

function Selection.reference(mode, viewportSize, mousePosition, inset)
	local width, height = components(viewportSize)
	if width == nil or width <= 0 or height <= 0 then
		return nil
	end
	if mode == "FirstPerson" then
		-- WorldToViewportPoint coordinates omit the GUI inset. Do not add it to
		-- the first-person reference; the viewport center is already correct.
		return { X = width / 2, Y = height / 2 }
	end
	if mode ~= "ThirdPerson" then
		return nil
	end
	local mouseX, mouseY = components(mousePosition)
	if mouseX == nil then
		return nil
	end
	local insetX, insetY = 0, 0
	if inset ~= nil then
		insetX, insetY = components(inset)
		if insetX == nil then
			return nil
		end
	end
	-- UserInputService.GetMouseLocation includes the GUI inset, while projected
	-- candidates use WorldToViewportPoint. Convert exactly once.
	local x, y = mouseX - insetX, mouseY - insetY
	if not finite(x) or not finite(y) then
		return nil
	end
	return { X = x, Y = y }
end

function Selection.isSelectable(candidate)
	if type(candidate) ~= "table" or candidate.valid ~= true
		or candidate.visible ~= true or candidate.onScreen ~= true
		or not finite(candidate.distanceStuds) or candidate.distanceStuds < 0 then
		return false
	end
	local point = candidate.screenPosition
	local x = components(point)
	if x == nil then
		return false
	end
	-- Vector2 has no Z member. Vector3 projection or a plain table may include
	-- depth; when supplied, positive finite depth is mandatory.
	local kind = typeof(point)
	if kind == "Vector3" or type(point) == "table" then
		local depth = point.Z
		if depth ~= nil and (not finite(depth) or depth <= 0) then
			return false
		end
	end
	return true
end

local function squaredDistance(candidate, reference)
	local referenceX, referenceY = components(reference)
	if referenceX == nil or not Selection.isSelectable(candidate) then
		return nil
	end
	local x, y = components(candidate.screenPosition)
	local dx, dy = x - referenceX, y - referenceY
	local value = dx * dx + dy * dy
	return finite(value) and value or nil
end

function Selection.within(candidate, reference, fov)
	if not finite(fov) or fov < 0 then
		return false
	end
	local squared = squaredDistance(candidate, reference)
	return squared ~= nil and squared <= fov * fov
end

function Selection.nearest(candidates, reference, fov)
	if type(candidates) ~= "table" or not finite(fov) or fov < 0
		or components(reference) == nil then
		return nil
	end
	local winner = nil
	local closestSquared = fov * fov
	for _, candidate in ipairs(candidates) do
		local squared = squaredDistance(candidate, reference)
		if squared ~= nil and squared <= closestSquared then
			-- Keep input ordering for exact ties instead of oscillating based on
			-- unrelated world distance or unstable player enumeration.
			if winner == nil or squared < closestSquared then
				winner = candidate
				closestSquared = squared
			end
		end
	end
	return winner
end

return Selection
