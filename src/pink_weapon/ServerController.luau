--!nonstrict
-- Authoritative controller for the OWNED Studio Tool. No game-specific hooks.
-- All Roblox accesses live in the injected native wrapper, so this exact
-- controller can also be exercised by deterministic tests.
local WeaponSettings = if script then require(script.Parent.WeaponSettings) else require("./WeaponSettings")
local ServerController = {}
ServerController.__index = ServerController
local fields = {
	sessionId = true, shotId = true, ticketId = true, mode = true,
	capturedAt = true, origin = true, aimpoint = true, targetUserId = true,
	targetCharacter = true, partName = true, sampleTime = true,
}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value)
	return finite(value) and value >= 1 and value <= 1e12 and value % 1 == 0
end
local function finiteVector(value)
	-- Native wiring supplies an isVector predicate requiring real Vector3.
	-- Table vectors are allowed only for the isolated CLI arithmetic adapter.
	if typeof(value) ~= "Vector3" and type(value) ~= "table" then return false end
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function health(humanoid)
	return humanoid and finite(humanoid.Health) and humanoid.Health > 0
end
local function magnitude(vector)
	return math.sqrt(vector.X * vector.X + vector.Y * vector.Y + vector.Z * vector.Z)
end
local function response(request, reason)
	local result = { accepted = false, reason = reason, hit = false, selectedTargetHit = false, damageApplied = 0 }
	if type(request) == "table" and getmetatable(request) == nil then
		if type(request.sessionId) == "string" and #request.sessionId <= 64 then result.sessionId = request.sessionId end
		if integer(request.shotId) then result.shotId = request.shotId end
		if integer(request.ticketId) then result.ticketId = request.ticketId end
		if request.mode == "Normal" or request.mode == "Locked" then result.mode = request.mode end
	end
	return result
end

function ServerController.new(options)
	assert(type(options) == "table", "Server controller options required")
	for _, name in { "clock", "getEquippedWeapon", "getTarget", "raycast", "describeHit", "applyDamage" } do
		assert(type(options[name]) == "function", name .. " callback required")
	end
	assert(options.isVector == nil or type(options.isVector) == "function", "isVector must be a function")
	return setmetatable({ settings = WeaponSettings.new(options.settings), callbacks = options,
		states = {}, destroyed = false }, ServerController)
end

function ServerController:_process(player, request)
	local rejected = response(request, "invalid-request")
	if self.destroyed then rejected.reason = "destroyed"; return rejected end
	if type(request) ~= "table" or getmetatable(request) ~= nil then return rejected end
	for key in request do if not fields[key] then rejected.reason = "unknown-field"; return rejected end end
	if type(request.sessionId) ~= "string" or #request.sessionId < 1 or #request.sessionId > 64 or not integer(request.shotId) then return rejected end
	if request.mode ~= "Normal" and request.mode ~= "Locked" then rejected.reason = "invalid-mode"; return rejected end
	if request.ticketId ~= nil and not integer(request.ticketId) then rejected.reason = "invalid-ticket"; return rejected end
	local settings, callbacks = self.settings, self.callbacks
	local now = callbacks.clock()
	if not finite(now) then rejected.reason = "invalid-server-clock"; return rejected end
	if not finite(request.capturedAt) or request.capturedAt > now + settings.ClockTolerance
		or now - request.capturedAt > settings.RequestMaxAge then rejected.reason = "stale-request"; return rejected end
	local isVector = callbacks.isVector or finiteVector
	if not isVector(request.origin) or not finiteVector(request.origin) or not isVector(request.aimpoint) or not finiteVector(request.aimpoint) then
		rejected.reason = "invalid-vectors"; return rejected
	end
	if not player or not finite(player.UserId) or player.UserId % 1 ~= 0 then rejected.reason = "invalid-player"; return rejected end
	if request.mode == "Locked" then
		if not finite(request.targetUserId) or request.targetUserId % 1 ~= 0 or request.targetUserId == player.UserId
			or not settings.AllowedParts[request.partName] or request.targetCharacter == nil then rejected.reason = "invalid-target"; return rejected end
		if not finite(request.sampleTime) or request.sampleTime > now + settings.ClockTolerance
			or now - request.sampleTime > settings.RequestMaxAge then rejected.reason = "stale-sample"; return rejected end
	elseif request.targetUserId ~= nil or request.targetCharacter ~= nil or request.partName ~= nil
		or request.sampleTime ~= nil or request.ticketId ~= nil then
		rejected.reason = "unexpected-target-fields"; return rejected
	end
	local state = self.states[player]
	if not state then
		state = { nextFire = -math.huge, sessions = {}, order = {} }
		self.states[player] = state
	end
	local prior = state.sessions[request.sessionId]
	if prior and request.shotId <= prior then rejected.reason = "duplicate-shot"; return rejected end
	if not prior then
		table.insert(state.order, request.sessionId)
		if #state.order > settings.MaxSessionsPerPlayer then state.sessions[table.remove(state.order, 1)] = nil end
	end
	state.sessions[request.sessionId] = request.shotId
	if now < state.nextFire then rejected.reason = "cooldown"; return rejected end
	local weapon = callbacks.getEquippedWeapon(player)
	if type(weapon) ~= "table" or not weapon.tool or not weapon.character or not health(weapon.humanoid)
		or not isVector(weapon.origin) or not finiteVector(weapon.origin) then rejected.reason = "weapon-not-equipped"; return rejected end
	local authoritativeOrigin = weapon.origin
	if magnitude(request.origin - authoritativeOrigin) > settings.MaxOriginDistance then rejected.reason = "invalid-origin"; return rejected end
	local delta = request.aimpoint - authoritativeOrigin
	local distance = magnitude(delta)
	if not finite(distance) or distance <= 0.001 then rejected.reason = "degenerate-aimpoint"; return rejected end
	if distance > settings.MaxAimDistance then rejected.reason = "aimpoint-out-of-range"; return rejected end
	local target
	if request.mode == "Locked" then
		target = callbacks.getTarget(request.targetUserId, request.partName, request.targetCharacter)
		if type(target) ~= "table" or not target.player or target.player.UserId ~= request.targetUserId
			or target.character ~= request.targetCharacter or not target.part or not health(target.humanoid)
			or not isVector(target.position) or not finiteVector(target.position) then rejected.reason = "target-lost"; return rejected end
		if magnitude(target.position - authoritativeOrigin) > settings.Range then rejected.reason = "target-out-of-range"; return rejected end
	end
	-- Rate is consumed before any raycast/damage callback, including a failed
	-- callback. Retrying cannot cause duplicated physical damage.
	state.nextFire = now + settings.Cooldown
	local rayDirection = delta / distance * settings.Range
	local rayResult = callbacks.raycast(authoritativeOrigin, rayDirection, weapon.character)
	local hitDescription
	if rayResult ~= nil then
		hitDescription = callbacks.describeHit(rayResult, player)
		if type(hitDescription) ~= "table" or not isVector(hitDescription.position) or not finiteVector(hitDescription.position) then
			error("Raycast returned an impact without a valid description")
		end
	end
	local selectedHit = target ~= nil and hitDescription ~= nil and hitDescription.character == target.character
	local referenceTime = callbacks.clock()
	if not finite(referenceTime) then error("Reference clock unavailable after raycast") end
	local actualPosition
	if target then
		-- Capture the reference before damage can remove a dead character.
		actualPosition = target.part.Position
		if not isVector(actualPosition) or not finiteVector(actualPosition) then error("Target reference position unavailable") end
	end
	local damageApplied = 0
	if hitDescription and hitDescription.humanoid and hitDescription.character ~= weapon.character and health(hitDescription.humanoid) then
		local damage = callbacks.applyDamage(hitDescription.humanoid, settings.Damage)
		assert(type(damage) == "table" and finite(damage.before) and finite(damage.after), "Damage callback must return measured health")
		damageApplied = math.max(0, damage.before - damage.after)
	end
	local accepted = {
		sessionId = request.sessionId, shotId = request.shotId, ticketId = request.ticketId,
		accepted = true, mode = request.mode, serverTime = referenceTime, referenceTime = referenceTime,
		hit = rayResult ~= nil, selectedTargetHit = selectedHit, damageApplied = damageApplied,
		impactPosition = if hitDescription then hitDescription.position else authoritativeOrigin + rayDirection,
		origin = authoritativeOrigin,
		reason = if selectedHit then "selected-target-hit" elseif hitDescription then "surface-impact" else "miss",
	}
	if hitDescription then accepted.hitName = hitDescription.name; accepted.hitPlayerUserId = hitDescription.playerUserId end
	if target then
		-- Actual position is read independently at the server reference time;
		-- no prediction value or proximity check decides an impact.
		accepted.targetUserId = target.player.UserId
		accepted.character = target.character
		accepted.actualPosition = actualPosition
	end
	return accepted
end

function ServerController:process(player, request)
	local ok, result = pcall(self._process, self, player, request)
	if ok then return result end
	local rejected = response(request, "server-error")
	local stringifyOK, detail = pcall(tostring, result)
	rejected.error = if stringifyOK then detail else "Server callback failed"
	return rejected
end
function ServerController:removePlayer(player)
	self.states[player] = nil
end
function ServerController:destroy()
	if self.destroyed then return end
	self.destroyed = true
	table.clear(self.states)
	self.callbacks = nil
end
return ServerController
