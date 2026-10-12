--!nonstrict
-- Comparison adapter for an OWNED/authorized shooting system. No remotes,
-- interception, camera writes, HTTP, or game-specific integration live here.
-- referenceTime must come from the actual independent shot/reference measurement;
-- this module never manufactures a reference timestamp from prediction horizons.
local ShotAdapter = {}
ShotAdapter.__index = ShotAdapter
local POLICIES = { "active", "manual", "auto" }

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	if typeof(value) ~= "Vector3" and type(value) ~= "table" then return false end
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function position(record)
	return record and (record.targetPosition or record.position)
end
local function cloneFrozen(value, depth)
	if type(value) ~= "table" then return value end
	if depth > 5 then return nil end
	local copy = table.clone(value)
	for key, child in pairs(copy) do
		if type(child) == "table" then copy[key] = cloneFrozen(child, depth + 1) end
	end
	return table.freeze(copy)
end
local function difference(predicted, actual)
	local x, y, z = predicted.X - actual.X, predicted.Y - actual.Y, predicted.Z - actual.Z
	local horizontal = math.sqrt(x * x + z * z)
	local errorStuds = math.sqrt(x * x + y * y + z * z)
	if not finite(errorStuds) then return nil end
	return { signedX = x, signedY = y, signedZ = z, horizontalStuds = horizontal, errorStuds = errorStuds }
end
local function isValid(self, ticket)
	if not self.isTargetValid then return true end
	local ok, valid = pcall(self.isTargetValid, ticket)
	return ok and valid == true
end

function ShotAdapter.new(options)
	assert(type(options) == "table" and type(options.getSnapshot) == "function", "getSnapshot callback required")
	assert(type(options.clock) == "function", "independent clock callback required")
	assert(options.fire == nil or type(options.fire) == "function", "fire must be an owned callback")
	assert(options.onMeasurement == nil or type(options.onMeasurement) == "function", "invalid measurement callback")
	assert(options.isTargetValid == nil or type(options.isTargetValid) == "function", "invalid target validation callback")
	local maxAge = options.maxAge or 0.6
	local capacity = options.capacity or 120
	assert(finite(maxAge) and maxAge > 0 and maxAge <= 10, "invalid maxAge")
	assert(finite(capacity) and capacity >= 1 and capacity <= 5000 and capacity % 1 == 0, "invalid capacity")
	return setmetatable({
		getSnapshot = options.getSnapshot, clock = options.clock, fireCallback = options.fire,
		onMeasurement = options.onMeasurement, isTargetValid = options.isTargetValid,
		capacity = capacity, maxAge = maxAge, tickets = {}, ticketOrder = {}, records = {},
		nextId = 0, destroyed = false,
	}, ShotAdapter)
end

function ShotAdapter:capture()
	if self.destroyed then return nil, "destroyed" end
	local now = self.clock()
	if not finite(now) then return nil, "invalid-clock" end
	local ok, snapshot = pcall(self.getSnapshot)
	if not ok or type(snapshot) ~= "table" then return nil, "no-snapshot" end
	if not finite(snapshot.targetUserId) or snapshot.targetUserId % 1 ~= 0 then return nil, "invalid-target" end
	if not finite(snapshot.createdAt) or snapshot.createdAt > now + 0.05 or now - snapshot.createdAt > self.maxAge then
		return nil, "stale-snapshot"
	end
	if not finite(snapshot.sampleTime) or snapshot.sampleTime > now + 0.05 or now - snapshot.sampleTime > self.maxAge then
		return nil, "stale-sample"
	end
	for _, policy in POLICIES do
		if type(snapshot[policy]) ~= "table" or not vector(position(snapshot[policy])) or not vector(snapshot[policy].position) then
			return nil, "invalid-" .. policy .. "-prediction"
		end
	end
	self.nextId += 1
	local ticket = table.freeze({
		id = self.nextId, targetUserId = snapshot.targetUserId,
		character = snapshot.character, part = snapshot.part,
		capturedAt = now, createdAt = snapshot.createdAt, sampleTime = snapshot.sampleTime,
		active = cloneFrozen(snapshot.active, 0), manual = cloneFrozen(snapshot.manual, 0), auto = cloneFrozen(snapshot.auto, 0),
		aimpointActive = cloneFrozen(snapshot.active.position, 0),
	})
	if not isValid(self, ticket) then return nil, "target-invalid" end
	self.tickets[ticket.id] = { ticket = ticket, consumed = false }
	table.insert(self.ticketOrder, ticket.id)
	if #self.ticketOrder > self.capacity then self.tickets[table.remove(self.ticketOrder, 1)] = nil end
	return ticket
end

function ShotAdapter:fire()
	if self.destroyed then return nil, "destroyed" end
	if not self.fireCallback then return nil, "no-fire-callback" end
	local ticket, err = self:capture()
	if not ticket then return nil, err end
	local ok = pcall(self.fireCallback, ticket)
	if not ok then return nil, "fire-callback-failed" end
	return ticket
end

function ShotAdapter:record(ticketOrId, reference)
	if self.destroyed then return nil, "destroyed" end
	local id = if type(ticketOrId) == "table" then ticketOrId.id else ticketOrId
	local entry = self.tickets[id]
	if not entry then return nil, "unknown-ticket" end
	if type(ticketOrId) == "table" and ticketOrId ~= entry.ticket then return nil, "unknown-ticket" end
	if entry.consumed then return nil, "duplicate-reference" end
	local ticket = entry.ticket
	local now = self.clock()
	if not finite(now) then return nil, "invalid-clock" end
	if now - ticket.capturedAt > self.maxAge then return nil, "stale-ticket" end
	if not isValid(self, ticket) then return nil, "target-invalid" end
	if type(reference) ~= "table" or reference.accepted ~= true then return nil, "reference-not-accepted" end
	if reference.targetUserId ~= ticket.targetUserId then return nil, "target-mismatch" end
	if reference.character ~= nil and ticket.character ~= nil and reference.character ~= ticket.character then
		return nil, "character-mismatch"
	end
	if not vector(reference.actualPosition) then return nil, "invalid-reference-position" end
	if not finite(reference.referenceTime) or reference.referenceTime < ticket.capturedAt or reference.referenceTime > now + 0.05 then
		return nil, "invalid-reference-time"
	end
	if reference.actualAimPoint ~= nil and not vector(reference.actualAimPoint) then return nil, "invalid-reference-aimpoint" end
	local record = {
		ticketId = ticket.id, targetUserId = ticket.targetUserId,
		capturedAt = ticket.capturedAt, sampleTime = ticket.sampleTime,
		referenceTime = reference.referenceTime, actualPosition = cloneFrozen(reference.actualPosition, 0),
	}
	for _, policy in POLICIES do
		local prediction = ticket[policy]
		local delta = difference(position(prediction), reference.actualPosition)
		if not delta then return nil, "nonfinite-error" end
		delta.position = position(prediction)
		delta.weaponProfile = prediction.weaponProfile or prediction.weapon or "unknown"
		delta.range = prediction.range or "unknown"
		record[policy] = table.freeze(delta)
	end
	if reference.actualAimPoint then
		local aim = difference(ticket.aimpointActive, reference.actualAimPoint)
		if not aim then return nil, "nonfinite-aim-error" end
		record.activeAimErrorStuds = aim.errorStuds
	end
	entry.consumed = true
	record = table.freeze(record)
	table.insert(self.records, record)
	if #self.records > self.capacity then table.remove(self.records, 1) end
	if self.onMeasurement then pcall(self.onMeasurement, record) end
	return record
end

local function bucket()
	return { count = 0, squareSum = 0, horizontalSum = 0, verticalSum = 0, signedX = 0, signedY = 0, signedZ = 0 }
end
local function accumulate(b, delta)
	b.count += 1
	b.squareSum += delta.errorStuds * delta.errorStuds
	b.horizontalSum += delta.horizontalStuds * delta.horizontalStuds
	b.verticalSum += delta.signedY * delta.signedY
	b.signedX += delta.signedX; b.signedY += delta.signedY; b.signedZ += delta.signedZ
end
local function metrics(b)
	local count = b.count
	return {
		count = count,
		rmseStuds = if count > 0 then math.sqrt(b.squareSum / count) else nil,
		horizontalRMSEStuds = if count > 0 then math.sqrt(b.horizontalSum / count) else nil,
		verticalRMSEStuds = if count > 0 then math.sqrt(b.verticalSum / count) else nil,
		meanSignedX = if count > 0 then b.signedX / count else nil,
		meanSignedY = if count > 0 then b.signedY / count else nil,
		meanSignedZ = if count > 0 then b.signedZ / count else nil,
	}
end
function ShotAdapter:summary()
	local totals, byWeaponRange = {}, {}
	for _, policy in POLICIES do totals[policy] = bucket() end
	for _, record in self.records do
		for _, policy in POLICIES do
			local delta = record[policy]
			accumulate(totals[policy], delta)
			local weapon = byWeaponRange[delta.weaponProfile]
			if not weapon then weapon = {}; byWeaponRange[delta.weaponProfile] = weapon end
			local range = weapon[delta.range]
			if not range then range = {}; weapon[delta.range] = range end
			if not range[policy] then range[policy] = bucket() end
			accumulate(range[policy], delta)
		end
	end
	for _, weapon in byWeaponRange do
		for _, range in weapon do
			for policy, b in range do range[policy] = metrics(b) end
		end
	end
	return { measurementCount = #self.records,
		active = metrics(totals.active), manual = metrics(totals.manual), auto = metrics(totals.auto), byWeaponRange = byWeaponRange }
end

function ShotAdapter:destroy()
	if self.destroyed then return end
	self.destroyed = true
	table.clear(self.tickets); table.clear(self.ticketOrder); table.clear(self.records)
	self.getSnapshot = nil; self.clock = nil; self.fireCallback = nil
	self.isTargetValid = nil; self.onMeasurement = nil
end

return ShotAdapter
