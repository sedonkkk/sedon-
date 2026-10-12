--!nonstrict
-- Pure camera-mode classification. No camera writes, Roblox services or targets.
-- Auto requires corroborated camera-to-head AND camera-to-focus distances;
-- proximity to the head alone is insufficient (e.g. a third-person obstruction).
local ModeDetector = {}
ModeDetector.__index = ModeDetector

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function distance(value)
	return finite(value) and value >= 0
end

local function resetPending(self)
	self.pendingMode = nil
	self.pendingSince = nil
end

function ModeDetector.new(config)
	return setmetatable({
		config = config or {},
		mode = "ThirdPerson",
		pendingMode = nil,
		pendingSince = nil,
		lastTime = nil,
	}, ModeDetector)
end

function ModeDetector:update(now, observation)
	-- Bad/out-of-order time cannot satisfy a dwell interval.
	if not finite(now) or (self.lastTime ~= nil and now < self.lastTime) then
		resetPending(self)
		return self.mode
	end
	self.lastTime = now
	local config = self.config
	local override = config.LockMode
	if override == "FirstPerson" or override == "ThirdPerson" then
		self.mode = override
		resetPending(self)
		return self.mode
	end
	if type(observation) ~= "table" then
		resetPending(self)
		return self.mode
	end
	-- The runtime obtains this explicit setting from Player.CameraMode.
	-- It is strong evidence and does not need the heuristic's dwell interval.
	if observation.forcedFirstPerson == true then
		self.mode = "FirstPerson"
		resetPending(self)
		return self.mode
	end

	local enter = config.ModeEnterDistance
	local exit = config.ModeExitDistance
	local dwell = config.ModeDwellSeconds
	if not distance(enter) then enter = 0.75 end
	if not distance(exit) or exit <= enter then exit = math.max(1.5, enter + 0.75) end
	if not distance(dwell) then dwell = 0.2 end

	local desired = nil
	if observation.subjectIsLocal == false then
		-- A confirmed different subject is not local first-person evidence.
		desired = "ThirdPerson"
	elseif observation.subjectIsLocal == true
		and distance(observation.headDistance) and distance(observation.focusDistance) then
		if observation.headDistance <= enter and observation.focusDistance <= enter then
			desired = "FirstPerson"
		elseif observation.headDistance >= exit and observation.focusDistance >= exit then
			desired = "ThirdPerson"
		end
	end

	-- Missing data and the hysteresis band preserve the established mode, but
	-- invalidate pending evidence so separated near samples cannot accumulate.
	if desired == nil or desired == self.mode then
		resetPending(self)
		return self.mode
	end
	if self.pendingMode ~= desired then
		self.pendingMode = desired
		self.pendingSince = now
	end
	if now - self.pendingSince >= dwell then
		self.mode = desired
		resetPending(self)
	end
	return self.mode
end

return ModeDetector
