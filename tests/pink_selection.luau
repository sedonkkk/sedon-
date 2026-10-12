--!nonstrict
-- Pure tests for PINK DOT LOCK mode detection and screen-space acquisition.
-- These exercise numbers and candidate records, not a Roblox camera renderer.
local ModeDetector = require("../src/pink/ModeDetector")
local Selection = require("../src/pink/Selection")
local V = require("./Vector")
local tests, failures, checks = 0, 0, 0

local function check(condition, message)
	checks += 1
	assert(condition, message or "assertion failed")
end

local function near(actual, expected)
	check(type(actual) == "number" and math.abs(actual - expected) < 1e-9,
		"expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function test(name, callback)
	tests += 1
	local ok, errorMessage = pcall(callback)
	if not ok then
		failures += 1
		print("FAIL " .. name .. ": " .. tostring(errorMessage))
	end
end

local function config()
	return { LockMode = "Auto", ModeEnterDistance = 0.75, ModeExitDistance = 1.5, ModeDwellSeconds = 0.2 }
end

local function evidence(head, focus, isLocal)
	return { forcedFirstPerson = false, subjectIsLocal = isLocal ~= false, headDistance = head, focusDistance = focus }
end

local function candidate(name, x, y)
	return {
		player = name, character = "character:" .. name, part = "part:" .. name,
		screenPosition = { X = x, Y = y, Z = 20 },
		onScreen = true, valid = true, visible = true, distanceStuds = 50,
	}
end

test("default mode and missing evidence preserve stable state", function()
	local detector = ModeDetector.new(config())
	check(detector:update(0, nil) == "ThirdPerson")
	check(detector:update(1, {}) == "ThirdPerson")
	check(detector:update(2, { forcedFirstPerson = true }) == "FirstPerson")
	check(detector:update(3, nil) == "FirstPerson")
	check(detector:update(4, { subjectIsLocal = true, headDistance = 0.2 }) == "FirstPerson")
end)

test("explicit first and third person overrides are immediate and mutable", function()
	local settings = config()
	settings.LockMode = "FirstPerson"
	local detector = ModeDetector.new(settings)
	check(detector:update(0, evidence(10, 10)) == "FirstPerson")
	settings.LockMode = "ThirdPerson"
	check(detector:update(0, { forcedFirstPerson = true }) == "ThirdPerson")
	settings.LockMode = "Auto"
	check(detector:update(0.01, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(0.22, evidence(0.1, 0.1)) == "FirstPerson")
end)

test("forced first person is immediate while auto requires corroborated dwell", function()
	local detector = ModeDetector.new(config())
	check(detector:update(0, { forcedFirstPerson = true }) == "FirstPerson")
	check(detector:update(0.1, evidence(3, 3)) == "FirstPerson")
	check(detector:update(0.299, evidence(3, 3)) == "FirstPerson")
	check(detector:update(0.301, evidence(3, 3)) == "ThirdPerson")
	check(detector:update(1, evidence(0.7, 0.7)) == "ThirdPerson")
	check(detector:update(1.199, evidence(0.7, 0.7)) == "ThirdPerson")
	check(detector:update(1.201, evidence(0.7, 0.7)) == "FirstPerson")
end)

test("head alone and camera obstruction do not establish first person", function()
	local detector = ModeDetector.new(config())
	for _, t in { 0, 0.3, 1, 10 } do
		check(detector:update(t, evidence(0.1, 4)) == "ThirdPerson")
	end
	check(detector:update(11, { subjectIsLocal = true, headDistance = 0.1 }) == "ThirdPerson")
	check(detector:update(12, evidence(0.1, 0.1, false)) == "ThirdPerson")
end)

test("hysteresis band and mixed evidence preserve established mode", function()
	local detector = ModeDetector.new(config())
	check(detector:update(0, { forcedFirstPerson = true }) == "FirstPerson")
	for index, sample in { evidence(1, 1), evidence(0.1, 2), evidence(2, 0.1) } do
		check(detector:update(index * 2 - 1, sample) == "FirstPerson")
		check(detector:update(index * 2, sample) == "FirstPerson")
	end
end)

test("interrupted evidence resets dwell instead of accumulating samples", function()
	local detector = ModeDetector.new(config())
	check(detector:update(0, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(0.15, evidence(1, 1)) == "ThirdPerson")
	check(detector:update(0.2, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(0.399, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(0.401, evidence(0.1, 0.1)) == "FirstPerson")
end)

test("invalid distances and timestamps cannot force or complete a transition", function()
	for _, invalid in { 0 / 0, math.huge, -math.huge, -1 } do
		local detector = ModeDetector.new(config())
		check(detector:update(0, evidence(invalid, 0.1)) == "ThirdPerson")
		check(detector:update(1, evidence(invalid, 0.1)) == "ThirdPerson")
		check(detector:update(2, evidence(0.1, invalid)) == "ThirdPerson")
	end
	local detector = ModeDetector.new(config())
	check(detector:update(10, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(9, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(0 / 0, { forcedFirstPerson = true }) == "ThirdPerson")
	check(detector:update(math.huge, { forcedFirstPerson = true }) == "ThirdPerson")
	check(detector:update(10.3, evidence(0.1, 0.1)) == "ThirdPerson")
	check(detector:update(10.51, evidence(0.1, 0.1)) == "FirstPerson")
end)

test("confirmed other camera subject exits after dwell", function()
	local detector = ModeDetector.new(config())
	check(detector:update(0, { forcedFirstPerson = true }) == "FirstPerson")
	check(detector:update(1, { subjectIsLocal = false }) == "FirstPerson")
	check(detector:update(1.21, { subjectIsLocal = false }) == "ThirdPerson")
end)

test("thresholds and zero dwell have defined boundary behavior", function()
	local settings = config()
	settings.ModeDwellSeconds = 0
	local detector = ModeDetector.new(settings)
	check(detector:update(0, evidence(0.75, 0.75)) == "FirstPerson")
	check(detector:update(1, evidence(1.5, 1.5)) == "ThirdPerson")
	local defaults = ModeDetector.new({ LockMode = "Auto" })
	check(defaults:update(0, evidence(0.1, 0.1)) == "ThirdPerson")
	check(defaults:update(0.21, evidence(0.1, 0.1)) == "FirstPerson")
end)

test("first-person reference is viewport center without mouse or inset", function()
	local reference = Selection.reference("FirstPerson", { X = 1920, Y = 1080 }, nil, { X = 0, Y = 36 })
	near(reference.X, 960)
	near(reference.Y, 540)
end)

test("third-person reference subtracts the inset exactly once", function()
	local viewport = { X = 1280, Y = 720 }
	local reference = Selection.reference("ThirdPerson", viewport, { X = 520, Y = 300 }, { X = 4, Y = 36 })
	near(reference.X, 516)
	near(reference.Y, 264)
	local noInset = Selection.reference("ThirdPerson", viewport, { X = 520, Y = 300 })
	near(noInset.X, 520)
	near(noInset.Y, 300)
end)

test("reference rejects invalid modes and nonfinite dimensions or coordinates", function()
	local viewport = { X = 1280, Y = 720 }
	check(Selection.reference("Auto", viewport, { X = 1, Y = 1 }) == nil)
	check(Selection.reference("FirstPerson", { X = 0, Y = 720 }) == nil)
	check(Selection.reference("FirstPerson", { X = 1280, Y = math.huge }) == nil)
	check(Selection.reference("ThirdPerson", viewport, nil) == nil)
	check(Selection.reference("ThirdPerson", viewport, { X = 1, Y = 0 / 0 }) == nil)
	check(Selection.reference("ThirdPerson", viewport, { X = 1, Y = 1 }, { X = 0, Y = math.huge }) == nil)
	check(Selection.reference("ThirdPerson", viewport, { X = 1e308, Y = 0 }, { X = -1e308, Y = 0 }) == nil)
end)

test("nearest valid candidate uses screen distance rather than world distance", function()
	local center = { X = 640, Y = 360 }
	local far = candidate("far", 710, 360)
	far.distanceStuds = 1
	local near = candidate("near", 650, 360)
	near.distanceStuds = 100
	check(Selection.nearest({ far, near }, center, 120) == near)
	check(Selection.within(near, center, 120))
	check(Selection.nearest({}, center, 120) == nil)
end)

test("FOV is a circular pixel radius with inclusive boundaries", function()
	local reference = { X = 0, Y = 0 }
	local boundary = candidate("boundary", 3, 4)
	check(Selection.within(boundary, reference, 5))
	check(not Selection.within(boundary, reference, 4.999))
	check(Selection.nearest({ boundary }, reference, 5) == boundary)
	check(Selection.nearest({ candidate("corner", 4, 4) }, reference, 5) == nil)
	check(Selection.within(candidate("center", 0, 0), reference, 0))
end)

test("invalid hidden offscreen behind-camera and malformed candidates are skipped", function()
	local reference = { X = 0, Y = 0 }
	for _, key in { "valid", "visible", "onScreen" } do
		local invalid = candidate(key, 0, 0)
		invalid[key] = false
		check(not Selection.isSelectable(invalid))
		check(Selection.nearest({ invalid }, reference, 120) == nil)
	end
	for _, bad in { 0 / 0, math.huge, -math.huge } do
		local invalid = candidate("nan", 0, 0)
		invalid.screenPosition.X = bad
		check(not Selection.isSelectable(invalid))
		invalid = candidate("nan", 0, 0)
		invalid.distanceStuds = bad
		check(not Selection.isSelectable(invalid))
	end
	for _, bad in { 0, -1, math.huge, 0 / 0 } do
		local invalid = candidate("behind", 0, 0)
		invalid.screenPosition.Z = bad
		check(not Selection.isSelectable(invalid))
	end
	check(not Selection.isSelectable(nil))
	check(not Selection.isSelectable({}))
	check(not Selection.isSelectable("player"))
	local noDepth = candidate("two-dimensional", 0, 0)
	noDepth.screenPosition = { X = 0, Y = 0 }
	check(Selection.isSelectable(noDepth))
	local withAdapter = candidate("adapter", 0, 0)
	withAdapter.screenPosition = V.new(0, 0, 20)
	check(Selection.isSelectable(withAdapter))
end)

test("invalid FOV and reference reject acquisition and within", function()
	local target = candidate("target", 0, 0)
	for _, bad in { -1, 0 / 0, math.huge, -math.huge } do
		check(not Selection.within(target, { X = 0, Y = 0 }, bad))
		check(Selection.nearest({ target }, { X = 0, Y = 0 }, bad) == nil)
	end
	check(not Selection.within(target, nil, 120))
	check(Selection.nearest(nil, { X = 0, Y = 0 }, 120) == nil)
	check(Selection.nearest({ target }, { X = 0 / 0, Y = 0 }, 120) == nil)
end)

test("ties keep the first candidate and do not mutate candidate records", function()
	local a, b = candidate("a", -10, 0), candidate("b", 10, 0)
	check(Selection.nearest({ a, b }, { X = 0, Y = 0 }, 120) == a)
	check(Selection.nearest({ b, a }, { X = 0, Y = 0 }, 120) == b)
	check(a.player == "a" and b.player == "b")
	near(a.screenPosition.X, -10)
	near(b.screenPosition.X, 10)
end)

test("mode detection and acquisition have no lock ownership or camera side effects", function()
	local persistent = candidate("locked", 640, 360)
	local detector = ModeDetector.new(config())
	local viewport = { X = 1280, Y = 720 }
	local mode = detector:update(0, { forcedFirstPerson = true })
	local first = Selection.reference(mode, viewport)
	local locked = Selection.nearest({ persistent }, first, 120)
	check(locked == persistent)
	detector:update(1, evidence(3, 3))
	mode = detector:update(1.21, evidence(3, 3))
	local third = Selection.reference(mode, viewport, { X = 0, Y = 36 }, { X = 0, Y = 36 })
	check(Selection.nearest({ persistent }, third, 180) == nil)
	-- Session is responsible for retaining `locked`; neither pure component
	-- can replace or clear that reference merely because the mode changed.
	check(locked == persistent)
end)

print(string.format("PINK selection: %d tests, %d checks, %d failures", tests, checks, failures))
assert(failures == 0, "PINK selection suite failed")
