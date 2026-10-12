--!nonstrict
-- Real bundled modules, compared with the original laboratory modules.
-- This runner exercises numerical behavior; it does not claim Roblox rendering,
-- replication, or properties of weapons in another experience were validated.
local V = require("./Vector")
local OriginalSettings = require("../src/shared/Settings")
local OriginalWeapons = require("../src/shared/Weapons")
local OriginalPredictor = require("../src/shared/Predictor")
local Bundle = require("../DaHoodPrediction")
local M = Bundle.Modules
local tests, failures, checks = 0, 0, 0
local zero = V.new(0, 0, 0)
local function check(condition, message)
	checks += 1
	assert(condition, message or "assertion failed")
end
local function near(actual, expected, tolerance, message)
	check(type(actual) == "number" and actual == actual and math.abs(actual - expected) <= (tolerance or 1e-10),
		(message or "numeric mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function vectorNear(actual, expected, tolerance, message)
	check(actual ~= nil and expected ~= nil and (actual - expected).Magnitude <= (tolerance or 1e-9),
		(message or "vector mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end
local function test(name, body)
	tests += 1
	local ok, err = pcall(body)
	if not ok then
		failures += 1
		print("FAIL " .. name .. ": " .. tostring(err))
	end
end
local function clone(value)
	if type(value) ~= "table" then return value end
	local result = {}
	for key, child in pairs(value) do result[key] = clone(child) end
	return result
end
local function sameData(a, b, path)
	path = path or "root"
	check(type(a) == type(b), path .. " has a different type")
	if type(a) ~= "table" then
		if type(a) == "number" then near(a, b, 1e-12, path) else check(a == b, path .. " differs") end
		return
	end
	for key, value in pairs(a) do
		check(b[key] ~= nil, path .. " missing " .. tostring(key))
		sameData(value, b[key], path .. "." .. tostring(key))
	end
	for key in pairs(b) do check(a[key] ~= nil, path .. " has an extra " .. tostring(key)) end
end
local function sample(t, position, velocity, state)
	return {t = t, position = position, velocity = velocity, state = state or "Walking"}
end
local function comparePrediction(actual, expected)
	check((actual == nil) == (expected == nil), "prediction presence differs")
	if not actual then return end
	for _, key in ipairs({"position", "targetPosition", "velocity", "acceleration"}) do
		vectorNear(actual[key], expected[key], 1e-9, key)
	end
	for _, key in ipairs({"delaySeconds", "distanceStuds", "rawPingSeconds", "smoothedPingSeconds",
		"flightSeconds", "sampleTime", "predictionHorizonSeconds"}) do
		near(actual[key], expected[key], 1e-12, key)
	end
	check(actual.state == expected.state and actual.range == expected.range, "state or range differs")
end

test("bundle is usable without a Roblox runtime and exports original core", function()
	check(type(Bundle.init) == "function")
	for _, name in ipairs({"Settings", "Weapons", "Latency", "MotionHistory", "Ballistics", "Predictor",
		"Diagnostics", "Geometry", "Configuration", "Calibration", "Interface", "Runtime", "Session"}) do
		check(type(M[name]) == "table", "missing module " .. name)
	end
	sameData(M.Settings.new(), OriginalSettings.new())
	for _, name in ipairs(OriginalWeapons.names()) do sameData(M.Weapons.get(name), OriginalWeapons.get(name)) end
end)

test("runtime audit reports absent native APIs while the numerical modules remain usable", function()
	local report = M.Runtime.check()
	check(report.ready == false)
	check(type(report.missing) == "table" and #report.missing > 0)
	check(type(report.warnings) == "table")
	check(type(M.Runtime.errorMessage(report)) == "string")
	check(type(Bundle.checkCompatibility) == "function" and type(Bundle.tryInit) == "function")
	local apiReport = Bundle.checkCompatibility()
	check(apiReport.ready == false and #apiReport.missing > 0)
	local session, failedReport = Bundle.tryInit()
	check(session == nil and failedReport.ready == false)
	local strict, message = pcall(Bundle.init)
	check(not strict and type(message) == "string")
	check(M.Settings.validate(M.Settings.new()))
	local latency = M.Latency.new(M.Settings.new())
	check(latency:sample(0.09, 0))
	near(latency:estimate(0, 0), 0.09)
end)

-- These traces include acceleration, sudden reversal, jumping, landing, a
-- teleport and a long observation gap. Both engines receive identical samples.
for _, rttMs in ipairs({8, 60, 150, 180}) do
	for _, feature in ipairs({"all", "manual", "no-memory", "no-velocity", "no-distance", "no-acceleration"}) do
		test(string.format("original parity at %g ms RTT with %s", rttMs, feature), function()
			local aSettings, bSettings = OriginalSettings.new(), M.Settings.new()
			for _, settings in ipairs({aSettings, bSettings}) do
				settings.autoPrediction = feature ~= "manual"
				settings.manualDelaySeconds = 0.117
				settings.memoryTracking = feature ~= "no-memory"
				settings.velocityPrediction = feature ~= "no-velocity"
				settings.distancePrediction = feature ~= "no-distance"
				settings.accelerationPrediction = feature ~= "no-acceleration"
				settings.weaponOffsets.RevolverLab = 0.013
				settings.weaponOffsets.ProjectileLab = -0.007
			end
			local original, bundled = OriginalPredictor.new(aSettings), M.Predictor.new(bSettings)
			local t, position = 1, V.new(0, 0, 85)
			for index = 1, 95 do
				local dt = if index == 78 then 0.8 else 1 / 30
				t += dt
				local direction = if index >= 24 and index < 48 then -1 else 1
				local airborne = index >= 37 and index < 60
				local velocity = V.new(direction * (8 + 2 * math.sin(index * 0.12)), airborne and 7 or 0, 0)
				position += velocity * dt
				if index == 68 then position += V.new(500, 0, 0) end
				local observation = sample(t, position, velocity, airborne and "Jumping" or "Walking")
				local ping = rttMs / 2000 + (index > 50 and 0.002 or 0)
				check(original:setPing(ping, t) == bundled:setPing(ping, t), "ping acceptance differs")
				check(original:observe("trace", observation) == bundled:observe("trace", observation), "observation acceptance differs")
				local oldTrack, newTrack = original.tracks.trace, bundled.tracks.trace
				near(newTrack.resets, oldTrack.resets)
				near(newTrack.rejected, oldTrack.rejected)
				near(#newTrack.samples, #oldTrack.samples)
				vectorNear(newTrack.velocity, oldTrack.velocity)
				vectorNear(newTrack.acceleration, oldTrack.acceleration)
				for _, weapon in ipairs(OriginalWeapons.names()) do
					comparePrediction(bundled:predict("trace", zero, t + 0.016, M.Weapons.get(weapon)),
						original:predict("trace", zero, t + 0.016, OriginalWeapons.get(weapon)))
				end
			end
			check(bundled:predict("trace", zero, t + 0.8, M.Weapons.get("RevolverLab")) == nil)
			bundled:forget("trace")
			check(next(bundled.tracks) == nil)
		end)
	end
end

test("memory resets prevent pre-turn, pre-jump and pre-teleport acceleration leaking", function()
	local history = M.MotionHistory.new(M.Settings.new())
	check(history:observe(sample(0, zero, V.new(10, 0, 0))))
	check(history:observe(sample(0.1, V.new(1.2, 0, 0), V.new(14, 0, 0))))
	check(history.acceleration.Magnitude > 0)
	check(history:observe(sample(0.2, V.new(0, 0, 0), V.new(-12, 0, 0))))
	near(#history.samples, 1)
	vectorNear(history.acceleration, zero)
	check(history:observe(sample(0.3, V.new(-1.2, 1, 0), V.new(-12, 10, 0), "Jumping")))
	near(#history.samples, 1)
	vectorNear(history.acceleration, zero)
	check(history:observe(sample(0.4, V.new(100, 1, 0), V.new(0, 0, 0), "Walking")))
	near(#history.samples, 1)
	vectorNear(history.velocity, zero)
	vectorNear(history.acceleration, zero)
	local rejected = history.rejected
	check(not history:observe(sample(0.4, zero, zero)))
	check(not history:observe(sample(0.2, zero, zero)))
	near(history.rejected, rejected + 2)
	near(history:latest().t, 0.4)
end)

test("manual prediction ignores ping and automatic prediction uses one-way seconds", function()
	for _, rttMs in ipairs({8, 60, 150, 180}) do
		local settings = M.Settings.new()
		local auto = M.Predictor.new(settings)
		check(auto:setPing(rttMs / 2000, 0))
		check(auto:observe("moving", sample(0, V.new(0, 0, 20), V.new(10, 0, 0))))
		local result = auto:predict("moving", zero, 0, M.Weapons.get("RevolverLab"))
		near(result.delaySeconds, rttMs / 2000)
		near(result.position.X, 10 * rttMs / 2000)
		settings = M.Settings.new()
		settings.autoPrediction, settings.manualDelaySeconds = false, 0.121
		local manual = M.Predictor.new(settings)
		check(manual:setPing(rttMs / 2000, 0))
		check(manual:observe("moving", sample(0, V.new(0, 0, 20), V.new(10, 0, 0))))
		result = manual:predict("moving", zero, 0, M.Weapons.get("RevolverLab"))
		near(result.delaySeconds, 0.121)
		near(result.position.X, 1.21)
	end
end)

test("configuration defaults are fresh and snapshots and envelopes own their nested data", function()
	local C = M.Configuration
	local first, second = C.new(), C.new()
	check(C.validate(first))
	first.profiles.Revolver.rangeOffsets.close = 0.021
	first.core.pingCalibration[1].offsetSeconds = -0.004
	near(second.profiles.Revolver.rangeOffsets.close, 0)
	near(second.core.pingCalibration[1].offsetSeconds, 0)
	local snapshot = C.createSnapshot(first)
	local envelope = C.toEnvelope(first)
	check(envelope.schemaVersion == 1)
	sameData(snapshot, first)
	snapshot.profiles.Revolver.rangeOffsets.close = 0.045
	envelope.configuration.core.pingCalibration[1].offsetSeconds = 0.015
	near(first.profiles.Revolver.rangeOffsets.close, 0.021)
	near(first.core.pingCalibration[1].offsetSeconds, -0.004)
	local restored = C.fromEnvelope(C.toEnvelope(first))
	sameData(restored, first)
	restored.core.weaponOffsets.RevolverLab = 0.013
	near(first.core.weaponOffsets.RevolverLab, 0)
end)

test("validated partial import applies defaults and rejects malformed data atomically", function()
	local C = M.Configuration
	local partial = {activeProfile = "Custom", profiles = {Custom = {speed = 300, rangeOffsets = {long = 0.022}}},
		core = {fovPixels = 275}}
	local imported = C.import(partial)
	check(imported ~= nil and C.validate(imported))
	check(imported.activeProfile == "Custom")
	near(imported.profiles.Custom.speed, 300)
	near(imported.profiles.Custom.rangeOffsets.long, 0.022)
	near(imported.profiles.Custom.rangeOffsets.close, 0)
	near(imported.core.fovPixels, 275)
	partial.profiles.Custom.speed = 1
	near(imported.profiles.Custom.speed, 300)
	local original = C.createSnapshot(imported)
	local invalid = {
		{unexpected = true}, {core = {unexpected = 1}}, {activeProfile = "Unknown"},
		{targetMode = "AllPlayers"}, {core = {memoryTracking = "true"}},
		{core = {historyCapacity = 2.5}}, {core = {minDelaySeconds = 0.4, maxDelaySeconds = 0.1}},
		{profiles = {Custom = {kind = "projectile", speed = 0}}},
		{profiles = {Revolver = {rangeOffsets = {close = 0.151}}}},
		{profiles = {Revolver = {rangeOffsets = {unknown = 0}}}},
		{profiles = {Unknown = {}}}, {core = {enabled = function() end}},
		{core = {pingCalibration = {{pingSeconds = 0.03, offsetSeconds = 0}, {pingSeconds = 0.02, offsetSeconds = 0}}}},
		{core = {pingCalibration = {[1] = {pingSeconds = 0.03, offsetSeconds = 0}, [3] = {pingSeconds = 0.09, offsetSeconds = 0}}}},
		{core = {pingCalibration = {{pingSeconds = 0.03, offsetSeconds = 0, injected = true}}}},
	}
	for _, bad in ipairs(invalid) do
		local result, message = C.import(bad)
		check(result == nil and type(message) == "string", "invalid partial import accepted")
	end
	for _, badNumber in ipairs({0 / 0, math.huge, -math.huge}) do
		check(C.import({simulatedRTTMilliseconds = badNumber}) == nil)
		check(C.import({profiles = {Revolver = {latencyOffsetSeconds = badNumber}}}) == nil)
		check(C.import({core = {pingCalibration = {{pingSeconds = 0.03, offsetSeconds = badNumber}}}}) == nil)
	end
	check(C.import(setmetatable({}, {})) == nil)
	check(C.fromEnvelope({schemaVersion = 2, configuration = {}}) == nil)
	check(C.fromEnvelope({schemaVersion = 1, configuration = {}, unexpected = true}) == nil)
	check(C.fromEnvelope({schemaVersion = 1, configuration = "bad"}) == nil)
	sameData(imported, original)
end)

test("lab profile range offsets are measured corrections without fabricated distance flight", function()
	local C = M.Configuration
	local config = C.new()
	check(config.activeProfile == "Revolver")
	check(config.profiles.Revolver.kind == "hitscan")
	near(config.profiles.Revolver.speed, 0)
	for _, name in ipairs({"Revolver", "Default", "Custom"}) do
		for _, range in ipairs({"close", "medium", "long"}) do near(config.profiles[name].rangeOffsets[range], 0) end
	end
	config.profiles.Revolver.latencyOffsetSeconds = 0.01
	config.profiles.Revolver.rangeOffsets = {close = -0.005, medium = 0.012, long = 0.02}
	for _, scenario in ipairs({{20, -0.005}, {40, 0.012}, {119.99, 0.012}, {120, 0.02}, {200, 0.02}}) do
		local distance, rangeOffset = scenario[1], scenario[2]
		local core, profile = C.prepareCore(config, distance), C.getProfile(config, distance)
		near(profile.latencyOffsetSeconds, 0.01 + rangeOffset)
		local p = M.Predictor.new(core)
		check(p:setPing(0.03, 1))
		check(p:observe("moving", sample(1, V.new(0, 0, distance), V.new(10, 0, 0))))
		local prediction = p:predict("moving", zero, 1, profile)
		near(prediction.delaySeconds, 0.03 + 0.01 + rangeOffset)
		near(prediction.flightSeconds, 0)
		near(prediction.position.X, 10 * (0.03 + 0.01 + rangeOffset))
		profile.rangeOffsets.close = 0.15
		near(config.profiles.Revolver.rangeOffsets.close, -0.005)
	end
	check(C.rangeForDistance(39.99) == "close")
	check(C.rangeForDistance(40) == "medium")
	check(C.rangeForDistance(120) == "long")
end)

test("each profile retains its manual delay and ping compensation preserves user mode", function()
	local C = M.Configuration
	local config = C.new()
	config.profiles.Revolver.manualDelaySeconds = 0.051
	config.profiles.Default.manualDelaySeconds = 0.091
	config.profiles.Custom.manualDelaySeconds = 0.131
	for _, name in ipairs({"Revolver", "Default", "Custom"}) do
		config.activeProfile = name
		config.core.autoPrediction = false
		local core = C.prepareCore(config, 80)
		near(core.manualDelaySeconds, config.profiles[name].manualDelaySeconds)
		check(core.autoPrediction == false)
		check(core.weapon == (name == "Custom" and "ProjectileLab" or "RevolverLab"))
	end
	config.core.autoPrediction = true
	config.pingCompensation = false
	check(C.prepareCore(config, 80).autoPrediction == true)
	config.core.autoPrediction = false
	check(C.prepareCore(config, 80).autoPrediction == false)
end)

test("automatic and manual diagnostic RMSE are independent per profile and range", function()
	local calibration = M.Calibration.new()
	check(calibration:record({weapon = "Revolver", range = "medium", mode = "auto", errorStuds = 3, now = 1}))
	check(calibration:record({weapon = "Revolver", range = "medium", mode = "auto", errorStuds = 4, now = 2}))
	check(calibration:record({weapon = "Revolver", range = "medium", mode = "manual", errorStuds = 8, now = 3,
		residual = V.new(8, 0, 0), velocity = V.new(10, 0, 0)}))
	check(calibration:record({weapon = "Default", range = "medium", mode = "auto", errorStuds = 1, now = 1}))
	check(calibration:record({weapon = "Revolver", range = "long", mode = "manual", errorStuds = 6, now = 1}))
	local summary = calibration:summary("Revolver", "medium")
	near(summary.autoCount, 2)
	near(summary.manualCount, 1)
	near(summary.autoRMSEStuds, math.sqrt(12.5))
	near(summary.manualRMSEStuds, 8)
	near(summary.confidenceSamples, 0)
	near(summary.suggestedOffsetSeconds, 0)
	near(calibration:summary("Default", "medium").autoRMSEStuds, 1)
	near(calibration:summary("Revolver", "long").manualRMSEStuds, 6)
	near(calibration:summary("Custom", "close").autoCount, 0)
	summary.autoCount = 100
	near(calibration:summary("Revolver", "medium").autoCount, 2)
	calibration:clear()
	near(calibration:summary("Revolver", "medium").manualCount, 0)
	near(calibration:summary("Default", "medium").autoCount, 0)
end)

test("calibration window counts and denominators follow eviction", function()
	local calibration = M.Calibration.new({capacity = 3})
	for index, item in ipairs({{"auto", 3}, {"auto", 4}, {"manual", 9}, {"auto", 12}}) do
		check(calibration:record({weapon = "Custom", range = "close", mode = item[1], errorStuds = item[2], now = index}))
	end
	local summary = calibration:summary("Custom", "close")
	near(summary.autoCount, 2)
	near(summary.manualCount, 1)
	near(summary.autoRMSEStuds, math.sqrt((4 ^ 2 + 12 ^ 2) / 2))
	near(summary.manualRMSEStuds, 9)
end)

test("signed residual trains only moving automatic measurements with bounded temporal correction", function()
	local calibration = M.Calibration.new({smoothingSeconds = 2})
	local function record(mode, now, residual, velocity)
		check(calibration:record({weapon = "Revolver", range = "medium", mode = mode,
			errorStuds = residual.Magnitude, now = now, residual = residual, velocity = velocity}))
	end
	record("auto", 1, V.new(1, 0, 0), V.new(10, 0, 0))
	local expected = 0.1 * (1 - math.exp(-0.1 / 2))
	near(calibration:summary("Revolver", "medium").suggestedOffsetSeconds, expected)
	record("manual", 2, V.new(-5, 0, 0), V.new(10, 0, 0))
	near(calibration:summary("Revolver", "medium").suggestedOffsetSeconds, expected)
	record("auto", 3, V.new(1, 0, 0), V.new(2, 0, 0))
	near(calibration:summary("Revolver", "medium").confidenceSamples, 1)
	near(calibration:summary("Revolver", "medium").suggestedOffsetSeconds, expected)
	record("auto", 4, V.new(0, 10, 0), V.new(10, 0, 0))
	expected *= math.exp(-3 / 2)
	near(calibration:summary("Revolver", "medium").suggestedOffsetSeconds, expected)
	record("auto", 5, V.new(-1, 0, 0), V.new(10, 0, 0))
	expected += (-0.1 - expected) * (1 - math.exp(-1 / 2))
	near(calibration:summary("Revolver", "medium").suggestedOffsetSeconds, expected)
	check(expected < 0, "leading prediction should receive a negative correction")
	for i = 6, 40 do record("auto", i, V.new(100, 0, 0), V.new(10, 0, 0)) end
	local suggestion, count = calibration:suggest("Revolver", "medium")
	check(suggestion <= 0.15 and suggestion > 0.14)
	check(count > 1)
end)

test("calibration EMA depends on elapsed time and ignores equal-time correction repeats", function()
	local fast, slow = M.Calibration.new({capacity = 1000}), M.Calibration.new({capacity = 1000})
	local function record(model, now)
		check(model:record({weapon = "Custom", range = "long", mode = "auto", errorStuds = 1, now = now,
			residual = V.new(1, 0, 0), velocity = V.new(10, 0, 0)}))
	end
	record(fast, 0.1)
	record(slow, 0.1)
	for i = 1, 100 do record(fast, 0.1 + i * 0.02) end
	for i = 1, 10 do record(slow, 0.1 + i * 0.2) end
	near(fast:suggest("Custom", "long"), slow:suggest("Custom", "long"), 1e-12)
	local previous = fast:suggest("Custom", "long")
	record(fast, 2.1)
	near(fast:suggest("Custom", "long"), previous)
end)

test("calibration rejects invalid scalar metadata without changing accumulated diagnostics", function()
	local calibration = M.Calibration.new()
	local good = {weapon = "Default", range = "close", mode = "auto", errorStuds = 2, now = 2}
	check(calibration:record(good))
	local original = calibration:summary("Default", "close")
	local malformed = {{"weapon", "Unknown"}, {"range", "far"}, {"mode", "other"},
		{"errorStuds", -1}, {"errorStuds", 0 / 0}, {"errorStuds", math.huge}, {"now", 0 / 0}, {"now", 1}}
	for _, bad in ipairs(malformed) do
		local measurement = clone(good)
		measurement[bad[1]] = bad[2]
		check(not calibration:record(measurement))
	end
	check(not calibration:record(nil))
	sameData(calibration:summary("Default", "close"), original)
end)

test("calibration confidence follows trained samples remaining in the bounded window", function()
	local calibration = M.Calibration.new({capacity = 3})
	local function record(mode, now)
		check(calibration:record({weapon = "Revolver", range = "close", mode = mode, now = now,
			errorStuds = 1, residual = V.new(1, 0, 0), velocity = V.new(10, 0, 0)}))
	end
	for now = 1, 3 do record("auto", now) end
	near(calibration:summary("Revolver", "close").confidenceSamples, 3)
	for now = 4, 6 do
		record("manual", now)
		near(calibration:summary("Revolver", "close").confidenceSamples, 6 - now)
	end
	near(calibration:summary("Revolver", "close").suggestedOffsetSeconds, 0)
	record("auto", 7)
	near(calibration:summary("Revolver", "close").confidenceSamples, 1)
	near(calibration:summary("Revolver", "close").suggestedOffsetSeconds, 0.1 * (1 - math.exp(-0.1 / 2)))
end)

test("stale calibration suggestions expire without deleting error diagnostics", function()
	local calibration = M.Calibration.new({freshnessSeconds = 5})
	local function record(now)
		check(calibration:record({weapon = "Custom", range = "long", mode = "auto", now = now,
			errorStuds = 1, residual = V.new(1, 0, 0), velocity = V.new(10, 0, 0)}))
	end
	record(1)
	local first = calibration:summary("Custom", "long", 2)
	check(first.suggestedOffsetSeconds > 0)
	near(first.confidenceSamples, 1)
	local expired = calibration:summary("Custom", "long", 7)
	near(expired.suggestedOffsetSeconds, 0)
	near(expired.confidenceSamples, 0)
	near(expired.autoCount, 1)
	near(expired.autoRMSEStuds, 1)
	local suggestion, confidence = calibration:suggest("Custom", "long", 7)
	near(suggestion, 0)
	near(confidence, 0)
	record(8)
	local fresh = calibration:summary("Custom", "long", 8)
	near(fresh.autoCount, 2)
	near(fresh.confidenceSamples, 1)
	near(fresh.suggestedOffsetSeconds, first.suggestedOffsetSeconds)
end)

print(string.format("Standalone: %d tests, %d assertions, %d failures", tests, checks, failures))
assert(failures == 0, "standalone tests failed")
