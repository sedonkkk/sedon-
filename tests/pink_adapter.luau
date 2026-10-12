--!nonstrict
-- Real ShotAdapter contract tests. No Roblox/Da Hood weapon runtime is simulated.
local ShotAdapter = require("../src/pink/ShotAdapter")
local Vector = require("./Vector")
local tests, assertions = 0, 0
local function check(value, message)
	assertions += 1
	assert(value, message or "assertion failed")
end
local function near(actual, expected)
	check(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
		"expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, body)
	tests += 1
	local ok, err = pcall(body)
	assert(ok, name .. ": " .. tostring(err))
end
local function fixture(options)
	local clock = { now = 1800000000 }
	local character, part = {}, {}
	local snapshot = { targetUserId = -2, character = character, part = part,
		sampleTime = clock.now, createdAt = clock.now }
	for _, policy in { "active", "manual", "auto" } do
		snapshot[policy] = { position = Vector.new(3, 4, 0), targetPosition = Vector.new(3, 4, 0),
			weaponProfile = "Revolver", range = "medium" }
	end
	local config = { clock = function() return clock.now end, getSnapshot = function() return snapshot end }
	for key, value in pairs(options or {}) do config[key] = value end
	return ShotAdapter.new(config), clock, snapshot
end
local function reference(clock, override)
	local result = { targetUserId = -2, actualPosition = Vector.new(0, 0, 0),
		referenceTime = clock.now, accepted = true }
	for key, value in pairs(override or {}) do result[key] = value end
	return result
end

test("Unix clocks and negative Studio IDs are accepted", function()
	local adapter, clock = fixture()
	local ticket = adapter:capture()
	check(ticket and ticket.targetUserId == -2)
	near(ticket.capturedAt, clock.now)
	clock.now += 0.05
	local record = adapter:record(ticket, reference(clock))
	near(record.active.errorStuds, 5)
	near(record.manual.horizontalStuds, 3)
	near(record.auto.signedY, 4)
end)

test("captured ticket and vectors cannot drift after snapshot mutation", function()
	local adapter, clock, snapshot = fixture()
	local ticket = adapter:capture()
	snapshot.active.position.X = 100
	snapshot.active.targetPosition.Y = 200
	check(not pcall(function() ticket.id = 9 end))
	check(not pcall(function() ticket.active.targetPosition.X = 9 end))
	clock.now += 0.01
	local record = adapter:record(ticket.id, reference(clock))
	near(record.active.errorStuds, 5)
	near(ticket.aimpointActive.X, 3)
end)

test("physical target error excludes shooter gravity compensation", function()
	local adapter, clock, snapshot = fixture()
	snapshot.active.position = Vector.new(3, 20, 0)
	snapshot.active.targetPosition = Vector.new(3, 4, 0)
	local ticket = adapter:capture()
	clock.now += 0.1
	local record = adapter:record(ticket, reference(clock, {
		actualPosition = Vector.new(3, 4, 0), actualAimPoint = Vector.new(3, 19, 0),
	}))
	near(record.active.errorStuds, 0)
	near(record.activeAimErrorStuds, 1)
end)

test("reference time is supplied independently of prediction horizons", function()
	local adapter, clock, snapshot = fixture()
	local before = clock.now
	snapshot.active.position = Vector.new(1.205, 0.8, 0)
	snapshot.active.targetPosition = snapshot.active.position
	snapshot.active.delayX = 0.1205
	snapshot.active.delayY = 0.08
	local ticket = adapter:capture()
	clock.now += 0.05
	local record = adapter:record(ticket, reference(clock, { actualPosition = Vector.new(0.5, 0.3, 0) }))
	near(record.referenceTime, before + 0.05)
	near(record.active.signedX, 0.705)
	near(record.active.signedY, 0.5)
	check(record.referenceTime ~= before + snapshot.active.delayX)
end)

test("manual and automatic policies share the actual reference", function()
	local adapter, clock, snapshot = fixture()
	snapshot.manual.targetPosition = Vector.new(1, -2, 3)
	snapshot.auto.targetPosition = Vector.new(-3, 2, -1)
	local ticket = adapter:capture()
	clock.now += 0.1
	local record = adapter:record(ticket, reference(clock, { actualPosition = Vector.new(1, 2, 3) }))
	near(record.manual.errorStuds, 4)
	near(record.manual.signedY, -4)
	near(record.auto.horizontalStuds, math.sqrt(32))
	near(record.auto.signedX, -4)
	near(record.auto.signedZ, -4)
end)

test("unknown forged and duplicate tickets are rejected", function()
	local adapter, clock = fixture()
	local ticket = adapter:capture()
	clock.now += 0.01
	local actual = reference(clock)
	local _, unknown = adapter:record(999, actual)
	check(unknown == "unknown-ticket")
	local _, forged = adapter:record({ id = ticket.id }, actual)
	check(forged == "unknown-ticket")
	check(adapter:record(ticket, actual) ~= nil)
	local _, duplicate = adapter:record(ticket, actual)
	check(duplicate == "duplicate-reference")
end)

test("stale samples and stale returned references are rejected", function()
	local adapter, clock, snapshot = fixture()
	snapshot.sampleTime = clock.now - 1
	local _, staleSample = adapter:capture()
	check(staleSample == "stale-sample")
	snapshot.sampleTime = clock.now
	local ticket = adapter:capture()
	clock.now += 0.7
	local _, staleTicket = adapter:record(ticket, reference(clock))
	check(staleTicket == "stale-ticket")
	local _, staleSnapshot = adapter:capture()
	check(staleSnapshot == "stale-snapshot")
end)

test("target, respawn and target validation protect ticket identity", function()
	local valid = true
	local adapter, clock = fixture({ isTargetValid = function() return valid end })
	local ticket = adapter:capture()
	clock.now += 0.05
	local _, mismatch = adapter:record(ticket, reference(clock, { targetUserId = -3 }))
	check(mismatch == "target-mismatch")
	local _, respawn = adapter:record(ticket, reference(clock, { character = {} }))
	check(respawn == "character-mismatch")
	valid = false
	local _, invalid = adapter:record(ticket, reference(clock))
	check(invalid == "target-invalid")
end)

test("malformed reference timestamps and positions are rejected", function()
	local adapter, clock = fixture()
	local ticket = adapter:capture()
	clock.now += 0.1
	for _, time in { ticket.capturedAt - 0.1, clock.now + 1, 0 / 0, math.huge } do
		local _, err = adapter:record(ticket, reference(clock, { referenceTime = time }))
		check(err == "invalid-reference-time")
	end
	for _, bad in { { X = math.huge, Y = 0, Z = 0 }, { X = 0 / 0, Y = 0, Z = 0 }, {} } do
		local _, err = adapter:record(ticket, reference(clock, { actualPosition = bad }))
		check(err == "invalid-reference-position")
	end
	local _, rejected = adapter:record(ticket, reference(clock, { accepted = false }))
	check(rejected == "reference-not-accepted")
	check(adapter:summary().measurementCount == 0)
end)

test("fire forwards only to the explicit owned callback", function()
	local called, delivered = 0, nil
	local adapter = fixture({ fire = function(ticket) called += 1; delivered = ticket end })
	local ticket = adapter:fire()
	check(ticket == delivered)
	near(called, 1)
	local adapterWithoutFire = fixture()
	local _, err = adapterWithoutFire:fire()
	check(err == "no-fire-callback")
end)

test("callback failure does not claim a shot was sent", function()
	local adapter = fixture({ fire = function() error("owned callback failed") end })
	local ticket, err = adapter:fire()
	check(ticket == nil and err == "fire-callback-failed")
end)

test("bounded records retain matching RMSE and per-profile/range groups", function()
	local adapter, clock, snapshot = fixture({ capacity = 2 })
	for index = 1, 3 do
		snapshot.createdAt, snapshot.sampleTime = clock.now, clock.now
		for _, policy in { "active", "manual", "auto" } do
			snapshot[policy].position = Vector.new(index, 0, 0)
			snapshot[policy].targetPosition = snapshot[policy].position
		end
		local ticket = adapter:capture()
		clock.now += 0.01
		check(adapter:record(ticket, reference(clock)) ~= nil)
	end
	local summary = adapter:summary()
	near(summary.measurementCount, 2)
	near(summary.active.rmseStuds, math.sqrt(6.5))
	near(summary.manual.meanSignedX, 2.5)
	near(summary.auto.verticalRMSEStuds, 0)
	near(summary.byWeaponRange.Revolver.medium.active.count, 2)
end)

test("bounded ticket queue evicts only the oldest capture", function()
	local adapter, clock = fixture({ capacity = 2 })
	local first, second, third = adapter:capture(), adapter:capture(), adapter:capture()
	clock.now += 0.01
	local _, err = adapter:record(first, reference(clock))
	check(err == "unknown-ticket")
	check(adapter:record(second, reference(clock)) ~= nil)
	check(adapter:record(third, reference(clock)) ~= nil)
end)

test("measurement callback receives frozen accepted record once", function()
	local called, delivered = 0, nil
	local adapter, clock = fixture({ onMeasurement = function(record) called += 1; delivered = record end })
	local ticket = adapter:capture()
	clock.now += 0.05
	local record = adapter:record(ticket, reference(clock))
	check(record == delivered and called == 1)
	check(not pcall(function() record.active.signedY = 99 end))
	adapter:record(ticket, reference(clock))
	near(called, 1)
end)

test("destroy releases callbacks and clears all bounded state", function()
	local adapter, clock = fixture()
	local ticket = adapter:capture()
	adapter:destroy(); adapter:destroy()
	check(adapter.getSnapshot == nil and adapter.clock == nil and adapter.fireCallback == nil)
	check(next(adapter.tickets) == nil and #adapter.records == 0)
	local _, capture = adapter:capture()
	local _, record = adapter:record(ticket, reference(clock))
	check(capture == "destroyed" and record == "destroyed")
	check(adapter:summary().measurementCount == 0)
end)

print(string.format("PINK DOT LOCK adapter: %d tests, %d assertions, 0 failures", tests, assertions))
