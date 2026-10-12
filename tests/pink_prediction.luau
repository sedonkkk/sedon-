--!nonstrict
-- Pure CLI regression tests for PINK DOT LOCK configuration and prediction.
-- These exercise the numerical contract; they do not claim a Roblox, Da Hood,
-- replication, projectile, or weapon integration has been tested in-game.
local V = require("./Vector")
local Config = require("../src/pink/Config")
local Prediction = require("../src/pink/Prediction")
local zero = V.new(0, 0, 0)
local tests, checks, failures = 0, 0, 0

local function check(condition, message)
 checks += 1
 assert(condition, message or "assertion failed")
end

local function near(actual, expected, tolerance, message)
 check(type(actual) == "number" and actual == actual
  and math.abs(actual - expected) <= (tolerance or 1e-9),
  (message or "numeric mismatch") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
end

local function vectorNear(actual, expected, tolerance, message)
 check(actual ~= nil and (actual - expected).Magnitude <= (tolerance or 1e-7),
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

local function configuration(overrides)
 local config, message = Config.new(overrides)
 check(config ~= nil, "configuration rejected: " .. tostring(message))
 return config
end

local function predictor(overrides)
 return Prediction.new(configuration(overrides))
end

local function moving(overrides, velocity, offset)
 local p = predictor(overrides)
 velocity = velocity or V.new(10, 20, 30)
 offset = offset or zero
 check(p:observe(0, offset, "Running"))
 check(p:observe(0.1, offset + velocity * 0.1, "Running"))
 return p, velocity, offset
end

test("independent defaults preserve the requested manual values", function()
 local a, b = Config.defaults(), Config.defaults()
 check(a ~= b)
 near(a.PredictionX, 0.1205)
 near(a.PredictionY, 0.0800)
 check(a.AutoPrediction == false)
 check(a.LockMode == "Auto")
 near(a.FirstPersonFOV, 120)
 near(a.ThirdPersonFOV, 180)
 near(a.DotSize, 6)
 near(a.DotColor.R, 1)
 near(a.DotColor.G, 105 / 255)
 near(a.DotColor.B, 180 / 255)
 near(a.DotTransparency, 0)
 check(a.DotOutline)
 check(a.MemoryTracking and a.VelocityPrediction and a.DistancePrediction)
 check(not a.AccelerationPrediction)
 a.PredictionX = 0.2
 near(b.PredictionX, 0.1205)
 local c = configuration()
 near(c.PredictionX, 0.1205)
 near(c.PredictionY, 0.0800)
end)

test("configuration rejects malformed inputs with an actionable message", function()
 local invalid = {
  {PredictionX = 0 / 0}, {PredictionY = math.huge}, {PredictionX = -1},
  {PredictionY = -math.huge}, {AutoPrediction = "true"},
  {LockMode = "CamLock"}, {PredictionSmoothing = -0.01},
  {DotSize = 0}, {UnknownSetting = true},
 }
 for _, overrides in invalid do
  local config, message = Config.new(overrides)
  check(config == nil, "accepted invalid configuration")
  check(type(message) == "string" and #message > 0, "missing validation message")
 end
end)

test("nested profile and calibration inputs are copied on normalization", function()
 local input = Config.defaults()
 local config = configuration(input)
 check(config.PingReferences ~= input.PingReferences)
 check(config.PingReferences[1] ~= input.PingReferences[1])
 check(config.Profiles ~= input.Profiles)
 check(config.Profiles.Revolver ~= input.Profiles.Revolver)
 input.PingReferences[1].X = 0.25
 input.Profiles.Revolver.PredictionXOffset = 0.08
 near(config.PingReferences[1].X, 0.113)
 near(config.Profiles.Revolver.PredictionXOffset, 0)
 local other = Config.defaults()
 config.PingReferences[1].Y = 0.2
 config.Profiles.Revolver.LatencyOffsetSeconds = 0.08
 near(other.PingReferences[1].Y, 0.075)
 near(other.Profiles.Revolver.LatencyOffsetSeconds, 0)
end)

test("calibration rows must be finite ordered and complete", function()
 local invalid = {
  {}, {{PingMs = 55, X = 0.113}},
  {{PingMs = 62, X = 0.120, Y = 0.080}, {PingMs = 55, X = 0.113, Y = 0.075}},
  {{PingMs = 55, X = 0.113, Y = 0.075}, {PingMs = 55, X = 0.120, Y = 0.080}},
  {{PingMs = 0 / 0, X = 0.113, Y = 0.075}},
  {{PingMs = 55, X = math.huge, Y = 0.075}},
  {{PingMs = 55, X = 0.113, Y = -0.001}},
 }
 for _, rows in invalid do
  local config, message = Config.new({PingReferences = rows})
  check(config == nil, "accepted invalid calibration rows")
  check(type(message) == "string" and #message > 0)
 end
 local config = configuration({PingReferences = {
  {PingMs = 8, X = 0.050, Y = 0.040},
  {PingMs = 55, X = 0.113, Y = 0.075},
  {PingMs = 62, X = 0.120, Y = 0.080},
  {PingMs = 70, X = 0.128, Y = 0.085},
  {PingMs = 180, X = 0.160, Y = 0.110},
 }})
 near(#config.PingReferences, 5)
end)

test("range relationships and profile physics reject inconsistent values", function()
 local invalid = {
  {MinPredictionX = 0.3, MaxPredictionX = 0.2},
  {MinPredictionY = 0.2, MaxPredictionY = 0.1},
  {CloseDistance = 150, MediumDistance = 120},
  {ModeEnterDistance = 2, ModeExitDistance = 1},
  {HistoryCapacity = 3.5}, {StaleAfter = 0},
  {WeaponProfile = "Missing"},
 }
 for _, overrides in invalid do
  local config, message = Config.new(overrides)
  check(config == nil, "accepted inconsistent configuration")
  check(type(message) == "string" and #message > 0)
 end
 for _, kind in {"Invented", "Projectile"} do
  local input = Config.defaults()
  input.Profiles.Revolver.Kind = kind
  input.Profiles.Revolver.Speed = 0
  local config, message = Config.new(input)
  check(config == nil, "accepted unknown or zero-speed projectile physics")
  check(type(message) == "string" and #message > 0)
 end
 local input = Config.defaults()
 input.Profiles.Revolver.PredictionXOffset = 0 / 0
 check(Config.new(input) == nil)
end)

test("shared settings map the configurable motion filters", function()
 local config = configuration({
  MemoryTracking = false, VelocityPrediction = false, AccelerationPrediction = true,
  HistoryCapacity = 7, HistoryWindow = 0.2, VelocitySmoothing = 0.03,
  AccelerationSmoothing = 0.12, MaxObservedSpeed = 90, MaxAcceleration = 160,
  TeleportSlack = 7, ReversalDotThreshold = -0.4,
  MaxAccelerationHorizon = 0.15, StaleAfter = 0.8,
 })
 local settings = Config.toSettings(config)
 check(settings.memoryTracking == false)
 check(settings.velocityPrediction == false)
 check(settings.accelerationPrediction == true)
 near(settings.historyCapacity, 7)
 near(settings.historyWindowSeconds, 0.2)
 near(settings.velocitySmoothingSeconds, 0.03)
 near(settings.accelerationSmoothingSeconds, 0.12)
 near(settings.maxObservedSpeedStuds, 90)
 near(settings.maxAccelerationStuds, 160)
 near(settings.teleportSlackStuds, 7)
 near(settings.reversalDotThreshold, -0.4)
 near(settings.maxAccelerationHorizonSeconds, 0.15)
 near(settings.staleAfterSeconds, 0.8)
end)

test("manual X applies to X and Z while Y uses its own seconds", function()
 local p, velocity = moving({MemoryTracking = false, PredictionSmoothing = 0})
 local output = p:predict(zero, 0.1)
 check(output ~= nil)
 vectorNear(output.rawPosition, V.new(1 + 10 * 0.1205, 2 + 20 * 0.0800, 3 + 30 * 0.1205))
 vectorNear(output.position, output.rawPosition)
 local later = p:predict(zero, 0.15)
 vectorNear(later.rawPosition, V.new(1 + velocity.X * 0.1705, 2 + velocity.Y * 0.1300, 3 + velocity.Z * 0.1705))
end)

test("manual prediction is unchanged by widely different ping samples", function()
 local p = moving({MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.008, 0))
 local first = p:predict(zero, 0.1)
 check(p:samplePing(0.180, 0.1))
 local second = p:predict(zero, 0.1)
 vectorNear(second.rawPosition, first.rawPosition)
 vectorNear(second.rawPosition, V.new(2.205, 3.6, 6.615))
end)

test("velocity prediction can be disabled without moving the visual observation", function()
 local p = moving({MemoryTracking = false, VelocityPrediction = false, PredictionSmoothing = 0})
 local output = p:predict(zero, 0.2)
 check(output ~= nil)
 vectorNear(output.rawPosition, V.new(1, 2, 3))
end)

test("observations reject duplicates out-of-order and malformed data", function()
 local p = predictor({MemoryTracking = false, PredictionSmoothing = 0})
 check(p:observe(0, zero, "Running"))
 check(p:observe(0.1, V.new(1, 0, 0), "Running"))
 check(not p:observe(0.1, V.new(99, 0, 0), "Running"))
 check(not p:observe(0.05, zero, "Running"))
 check(not p:observe(0 / 0, zero, "Running"))
 check(not p:observe(0.2, V.new(0 / 0, 0, 0), "Running"))
 check(not p:observe(0.2, {}, "Running"))
 check(not p:observe(0.2, V.new(2, 0, 0), 7))
 check(not p:observe(0.2, V.new(2, 0, 0), false))
 local output = p:predict(zero, 0.1)
 vectorNear(output.rawPosition, V.new(2.205, 0, 0))
 near(p.history:latest().t, 0.1)
end)

test("stale and impossible future observations do not produce predictions", function()
 local empty = predictor()
 check(empty:predict(zero, 0) == nil)
 local p = moving({MemoryTracking = false})
 check(p:predict(zero, 0.1 + 0.601) == nil)
 check(p:predict(zero, 0.049) == nil)
 check(p:predict(zero, 0 / 0) == nil)
end)

test("jumps and sudden lateral reversal reset stale velocity memory", function()
 local p = predictor({PredictionSmoothing = 0})
 check(p:observe(0, zero, "Running"))
 check(p:observe(0.1, V.new(1, 0, 0), "Running"))
 local before = p.history.resets
 check(p:observe(0.2, V.new(2, 3, 0), "Jumping"))
 near(p.history.resets, before + 1)
 vectorNear(p.history.velocity, V.new(10, 30, 0))
 vectorNear(p.history.acceleration, zero)
 before = p.history.resets
 check(p:observe(0.3, V.new(1, 6, 0), "Jumping"))
 near(p.history.resets, before + 1)
 vectorNear(p.history.velocity, V.new(-10, 30, 0))
 vectorNear(p.history.acceleration, zero)
 local output = p:predict(zero, 0.3)
 vectorNear(output.rawPosition, V.new(1 - 10 * 0.1205, 6 + 30 * 0.08, 0))
end)

test("teleports and long gaps rebase instead of extrapolating enormous speeds", function()
 local p = moving({MemoryTracking = false, PredictionSmoothing = 0, MaxDistance = 2000}, V.new(10, 0, 0))
 check(p:observe(0.2, V.new(1000, 30, -600), "Running"))
 vectorNear(p.history.velocity, zero)
 vectorNear(p:predict(zero, 0.2).rawPosition, V.new(1000, 30, -600))
 check(p:observe(1, V.new(1001, 30, -600), "Running"))
 vectorNear(p.history.velocity, zero)
 vectorNear(p:predict(zero, 1).rawPosition, V.new(1001, 30, -600))
end)

test("anomalous speeds inside teleport tolerance are rejected", function()
 local p = predictor({MemoryTracking = false, PredictionSmoothing = 0, MaxObservedSpeed = 20})
 check(p:observe(0, zero, "Running"))
 check(not p:observe(0.01, V.new(0.21, 0, 0), "Running"))
 near(p.history:latest().t, 0)
 check(p:observe(0.1, V.new(1, 0, 0), "Running"))
 vectorNear(p.history.velocity, V.new(10, 0, 0))
end)

test("memory tracking stays bounded and converges on regular movement", function()
 local p = predictor({HistoryCapacity = 5, HistoryWindow = 0.12, PredictionSmoothing = 0})
 for i = 0, 240 do
  local t = i / 120
  check(p:observe(t, V.new(12 * t, 0, -8 * t), "Running"))
  check(#p.history.samples <= 5)
  local samples = p.history.samples
  check(#samples <= 2 or samples[#samples].t - samples[1].t <= 0.12 + 1e-9)
 end
 vectorNear(p.history.velocity, V.new(12, 0, -8), 1e-8)
 vectorNear(p:predict(zero, 2).rawPosition, V.new(24 + 12 * 0.1205, 0, -16 - 8 * 0.1205), 1e-8)
end)

test("manual prediction diagnostics report seconds and round-trip milliseconds", function()
 local p = moving({MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.062, 0))
 local output = p:predict(zero, 0.15)
 near(output.baseX, 0.1205)
 near(output.baseY, 0.08)
 near(output.predictionX, 0.1205)
 near(output.predictionY, 0.08)
 near(output.rawPingMs, 62)
 near(output.smoothedPingMs, 62)
 near(output.ageSeconds, 0.05)
 near(output.sampleTime, 0.1)
 near(output.createdAt, 0.15)
 near(output.flightSeconds, 0)
 check(output.status == "Manual")
 check(output.weaponProfile == "Revolver")
 check(output.physicsVerified == false)
 vectorNear(output.currentPosition, V.new(1, 2, 3))
 vectorNear(output.velocity, V.new(10, 20, 30))
 vectorNear(output.acceleration, zero)
end)

test("automatic X and Y interpolate calibration points and clamp endpoints", function()
 local cases = {
  {8, 0.113, 0.075}, {55, 0.113, 0.075}, {58.5, 0.1165, 0.0775},
  {62, 0.120, 0.080}, {66, 0.124, 0.0825}, {70, 0.128, 0.085},
  {180, 0.128, 0.085},
 }
 for _, row in cases do
  local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0})
  check(p:samplePing(row[1] / 1000, 0))
  local output = p:predict(zero, 0.1)
  check(output.status == "Auto")
  near(output.baseX, row[2])
  near(output.baseY, row[3])
  near(output.predictionX, row[2])
  near(output.predictionY, row[3])
  vectorNear(output.rawPosition, V.new(1 + 10 * row[2], 2 + 20 * row[3], 3 + 30 * row[2]))
 end
end)

test("automatic calibrated horizons include the ping exactly once", function()
 local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.062, 0))
 local output = p:predict(zero, 0.1)
 near(output.predictionX, 0.120)
 near(output.predictionY, 0.080)
 vectorNear(output.rawPosition, V.new(2.2, 3.6, 6.6))
 check(math.abs(output.predictionX - (0.120 + 0.031)) > 0.02,
  "round-trip half-ping was added to a calibrated total horizon")
end)

test("automatic prediction supports additional calibration points", function()
 local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0,
  PingReferences = {
   {PingMs = 8, X = 0.050, Y = 0.040},
   {PingMs = 55, X = 0.113, Y = 0.075},
   {PingMs = 62, X = 0.120, Y = 0.080},
   {PingMs = 70, X = 0.128, Y = 0.085},
   {PingMs = 180, X = 0.160, Y = 0.110},
  },
 })
 check(p:samplePing(0.125, 0))
 local output = p:predict(zero, 0.1)
 near(output.predictionX, 0.144)
 near(output.predictionY, 0.0975)
end)

test("missing ping and disabled ping compensation use a clear manual fallback", function()
 for _, overrides in {{AutoPrediction = true}, {AutoPrediction = true, PingCompensation = false}} do
  overrides.MemoryTracking = false
  overrides.PredictionSmoothing = 0
  local p = moving(overrides)
  if overrides.PingCompensation == false then check(p:samplePing(0.07, 0)) end
  local output = p:predict(zero, 0.1)
  check(output.status == "AutoFallback")
  near(output.baseX, 0.1205)
  near(output.baseY, 0.08)
  vectorNear(output.rawPosition, V.new(2.205, 3.6, 6.615))
 end
 local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.07, 0))
 check(p:predict(zero, 0.1).status == "Auto")
 p:samplePing(nil, 0.1)
 local output = p:predict(zero, 0.1)
 check(output.status == "AutoFallback")
 near(output.baseX, 0.1205)
 near(output.baseY, 0.08)
end)

test("ping smoothing uses elapsed seconds independently of sampling frequency", function()
 local function run(hz)
  local p = predictor({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0, PingSmoothing = 0.8})
  check(p:samplePing(0.055, 0))
  for i = 1, hz do check(p:samplePing(0.070, i / hz)) end
  check(p:observe(0.9, V.new(9, 0, 0), "Running"))
  check(p:observe(1, V.new(10, 0, 0), "Running"))
  return p:predict(zero, 1)
 end
 local fast, slow = run(100), run(10)
 local expected = 70 + (55 - 70) * math.exp(-1 / 0.8)
 near(fast.rawPingMs, 70)
 near(slow.rawPingMs, 70)
 near(fast.smoothedPingMs, expected, 1e-10)
 near(slow.smoothedPingMs, expected, 1e-10)
 near(fast.predictionX, slow.predictionX, 1e-12)
 near(fast.predictionY, slow.predictionY, 1e-12)
end)

test("ping validation rejects impossible samples without changing accepted data", function()
 local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.062, 0))
 for _, bad in {0 / 0, math.huge, -math.huge, -0.01, 3} do
  check(not p:samplePing(bad, 0.1))
 end
 check(not p:samplePing(0.07, 0))
 check(not p:samplePing(0.07, -0.1))
 check(not p:samplePing(0.07, math.huge))
 local output = p:predict(zero, 0.1)
 near(output.rawPingMs, 62)
 near(output.smoothedPingMs, 62)
 near(output.predictionX, 0.12)
end)

test("automatic calibration slew limits change in seconds per elapsed second", function()
 local p = predictor({AutoPrediction = true, MemoryTracking = false,
  PredictionSmoothing = 0, PredictionSlew = 0.006, PingSmoothing = 0.05})
 check(p:samplePing(0.055, 0))
 check(p:observe(0, zero, "Running"))
 local first = p:predict(zero, 0)
 near(first.baseX, 0.113)
 near(first.baseY, 0.075)
 check(p:samplePing(0.070, 1))
 check(p:observe(0.9, V.new(9, 0, 0), "Running"))
 check(p:observe(1, V.new(10, 0, 0), "Running"))
 local nextOutput = p:predict(zero, 1)
 near(nextOutput.baseX, 0.119)
 near(nextOutput.baseY, 0.081)
 local repeated = p:predict(zero, 1)
 near(repeated.baseX, nextOutput.baseX)
 near(repeated.baseY, nextOutput.baseY)
 local later = p:predict(zero, 1.01)
 check(math.abs(later.baseX - nextOutput.baseX) <= 0.006 * 0.01 + 1e-12)
 check(math.abs(later.baseY - nextOutput.baseY) <= 0.006 * 0.01 + 1e-12)
end)

test("revolver axis latency and range offsets are each applied once", function()
 local cases = {{30, "Close", 0.009}, {50, "Medium", 0.013}, {150, "Long", 0.017}}
 for _, row in cases do
  local input = Config.defaults()
  input.MemoryTracking = false
  input.PredictionSmoothing = 0
  input.CloseOffset, input.MediumOffset, input.LongOffset = 0.004, 0.006, 0.008
  local profile = input.Profiles.Revolver
  profile.PredictionXOffset, profile.PredictionYOffset = 0.01, 0.02
  profile.LatencyOffsetSeconds = 0.03
  profile.CloseOffset, profile.MediumOffset, profile.LongOffset = 0.005, 0.007, 0.009
  local p = moving(input, V.new(10, 0, 10), V.new(row[1] - 1, 0, -1))
  local output = p:predict(zero, 0.1)
  local x = 0.1205 + 0.01 + 0.03 + row[3]
  local y = 0.08 + 0.02 + 0.03 + row[3]
  check(output.range == row[2])
  near(output.distanceStuds, row[1])
  near(output.baseX, 0.1205)
  near(output.baseY, 0.08)
  near(output.predictionX, x)
  near(output.predictionY, y)
  vectorNear(output.rawPosition, V.new(row[1] + 10 * x, 0, 10 * x))
  near(output.flightSeconds, 0)
  check(output.physicsVerified == false, "an unverified Revolver profile claimed verified physics")
  near(input.PredictionX, 0.1205)
  near(input.PredictionY, 0.08)
 end
end)

test("disabling distance prediction excludes both global and weapon range offsets", function()
 local input = Config.defaults()
 input.DistancePrediction, input.MemoryTracking, input.PredictionSmoothing = false, false, 0
 input.LongOffset = 0.07
 local profile = input.Profiles.Revolver
 profile.LongOffset = 0.06
 profile.PredictionXOffset = 0.01
 profile.PredictionYOffset = 0.02
 profile.LatencyOffsetSeconds = 0.03
 local p = moving(input, V.new(10, 0, 10), V.new(149, 0, -1))
 local output = p:predict(zero, 0.1)
 check(output.range == "Long")
 near(output.predictionX, 0.1605)
 near(output.predictionY, 0.13)
 near(output.flightSeconds, 0)
 vectorNear(output.rawPosition, V.new(151.605, 0, 1.605))
end)

test("final adjusted axis horizons obey independent configurable bounds", function()
 for _, offset in {-0.1, 0.1} do
  local input = Config.defaults()
  input.MinPredictionX, input.MaxPredictionX = 0.1, 0.14
  input.MinPredictionY, input.MaxPredictionY = 0.07, 0.1
  input.Profiles.Revolver.PredictionXOffset = offset
  input.Profiles.Revolver.PredictionYOffset = offset
  input.MemoryTracking, input.PredictionSmoothing = false, 0
  local p = moving(input)
  local output = p:predict(zero, 0.1)
  near(output.predictionX, if offset < 0 then 0.1 else 0.14)
  near(output.predictionY, if offset < 0 then 0.07 else 0.1)
  near(output.baseX, 0.1205)
  near(output.baseY, 0.08)
 end
end)

test("prediction position EMA is time based at different frame rates", function()
 local function run(hz)
  local p = predictor({VelocityPrediction = false, PredictionSmoothing = 0.08})
  check(p:observe(0, zero, "Running"))
  vectorNear(p:predict(zero, 0).position, zero)
  check(p:observe(0.01, V.new(1, 0, 0), "Running"))
  p:predict(zero, 0.01)
  local output
  for i = 1, hz * 0.4 do output = p:predict(zero, 0.01 + i / hz) end
  local repeated = p:predict(zero, 0.41)
  vectorNear(repeated.position, output.position, 1e-12)
  vectorNear(output.rawPosition, V.new(1, 0, 0))
  return output.position
 end
 local fast, slow = run(120), run(30)
 local expected = V.new(1 - math.exp(-0.41 / 0.08), 0, 0)
 vectorNear(fast, expected, 1e-10)
 vectorNear(slow, expected, 1e-10)
 vectorNear(fast, slow, 1e-10)
end)

test("manual and automatic comparison policies keep independent smoothing state", function()
 local input = configuration({MemoryTracking = false, PredictionSmoothing = 0.08})
 local p = Prediction.new(input)
 check(p:samplePing(0.070, 0))
 check(p:observe(0, zero, "Running"))
 local initial = p:predictComparisons(zero, 0)
 check(initial.active.status == "Manual")
 vectorNear(initial.manual.position, zero)
 vectorNear(initial.auto.position, zero)
 check(p:observe(0.1, V.new(1, 2, 3), "Running"))
 local outputs = p:predictComparisons(zero, 0.1)
 local alpha = 1 - math.exp(-0.1 / 0.08)
 vectorNear(outputs.manual.rawPosition, V.new(2.205, 3.6, 6.615))
 vectorNear(outputs.auto.rawPosition, V.new(2.28, 3.7, 6.84))
 vectorNear(outputs.manual.position, outputs.manual.rawPosition * alpha)
 vectorNear(outputs.auto.position, outputs.auto.rawPosition * alpha)
 vectorNear(outputs.active.position, outputs.manual.position)
 local same = p:predictComparisons(zero, 0.1)
 vectorNear(same.manual.position, outputs.manual.position)
 vectorNear(same.auto.position, outputs.auto.position)
 vectorNear(p:predict(zero, 0.1, "Auto").position, outputs.auto.position)
 vectorNear(p:predict(zero, 0.1, "Manual").position, outputs.manual.position)
 near(input.PredictionX, 0.1205)
 near(input.PredictionY, 0.08)
 check(input.AutoPrediction == false)
 check(p:predict(zero, 0.1).status == "Manual")
end)

test("configured projectile flight uses studs per second and adds lead once", function()
 local input = Config.defaults()
 input.MemoryTracking, input.PredictionSmoothing = false, 0
 input.Profiles.Revolver.Kind = "Projectile"
 input.Profiles.Revolver.Speed = 200
 local p = moving(input, V.new(10, 0, 0), V.new(99, 0, 0))
 local output = p:predict(zero, 0.15)
 local atLaunch = 100 + 10 * (0.1205 + 0.05)
 local expectedFlight = atLaunch / (200 - 10)
 near(output.flightSeconds, expectedFlight, 1e-9)
 vectorNear(output.rawPosition, V.new(atLaunch + 10 * expectedFlight, 0, 0), 1e-8)
 vectorNear(output.rawTargetPosition, output.rawPosition)
 near(output.rawPosition.Magnitude, 200 * output.flightSeconds, 1e-8)
 near(output.predictionX, 0.1205)
 near(output.predictionY, 0.08)
 check(output.physicsStatus == "ConfiguredProjectile")
 check(output.physicsVerified == false)
end)

test("configured projectile gravity separates aim from future target position", function()
 local input = Config.defaults()
 input.PredictionSmoothing = 0
 input.Profiles.Revolver.Kind = "Projectile"
 input.Profiles.Revolver.Speed = 200
 input.Profiles.Revolver.Gravity = 20
 local p = predictor(input)
 check(p:observe(0, V.new(100, 0, 0), "Running"))
 local output = p:predict(zero, 0)
 check(output ~= nil)
 vectorNear(output.rawTargetPosition, V.new(100, 0, 0))
 near(output.rawPosition.X, 100)
 near(output.rawPosition.Y, 0.5 * 20 * output.flightSeconds * output.flightSeconds, 1e-8)
 near(output.rawPosition.Z, 0)
 near(output.rawPosition.Magnitude, 200 * output.flightSeconds, 0.0001)
 vectorNear(output.targetPosition, output.rawTargetPosition)
 vectorNear(output.position, output.rawPosition)
 check(output.physicsVerified == false)
end)

test("impossible or overlong projectile intercepts return no invented solution", function()
 for _, settings in {{Speed = 5, MaxFlightSeconds = 2}, {Speed = 200, MaxFlightSeconds = 0.2}} do
  local input = Config.defaults()
  input.MemoryTracking, input.PredictionSmoothing = false, 0
  input.MaxFlightSeconds = settings.MaxFlightSeconds
  input.Profiles.Revolver.Kind = "Projectile"
  input.Profiles.Revolver.Speed = settings.Speed
  local p = moving(input, V.new(10, 0, 0), V.new(99, 0, 0))
  check(p:predict(zero, 0.1) == nil)
 end
end)

test("distance prediction disables user-configured projectile flight", function()
 local input = Config.defaults()
 input.DistancePrediction, input.MemoryTracking, input.PredictionSmoothing = false, false, 0
 input.Profiles.Revolver.Kind = "Projectile"
 input.Profiles.Revolver.Speed = 200
 input.Profiles.Revolver.Gravity = 20
 local p = moving(input, V.new(10, 0, 0), V.new(99, 0, 0))
 local output = p:predict(zero, 0.1)
 near(output.flightSeconds, 0)
 vectorNear(output.rawPosition, V.new(101.205, 0, 0))
 vectorNear(output.rawTargetPosition, output.rawPosition)
 check(output.physicsStatus == "DistanceDisabled")
end)

test("bounded acceleration is opt-in and uses distinct axis horizons", function()
 local function run(enabled)
  local p = predictor({AccelerationPrediction = enabled, MaxAccelerationHorizon = 0.05, PredictionSmoothing = 0})
  for i = 0, 4 do
   local t = i / 10
   check(p:observe(t, V.new(5 * t * t, 10 * t * t, -2.5 * t * t), "Running"))
  end
  return p:predict(zero, 0.4)
 end
 local linear, curved = run(false), run(true)
 vectorNear(linear.acceleration, zero)
 check(curved.acceleration.Magnitude > 0)
 check(curved.acceleration.Magnitude <= 180 + 1e-8)
 near(curved.rawPosition.X - linear.rawPosition.X, curved.acceleration.X * (0.05 * 0.1205 - 0.5 * 0.05 * 0.05))
 near(curved.rawPosition.Y - linear.rawPosition.Y, curved.acceleration.Y * (0.05 * 0.0800 - 0.5 * 0.05 * 0.05))
 near(curved.rawPosition.Z - linear.rawPosition.Z, curved.acceleration.Z * (0.05 * 0.1205 - 0.5 * 0.05 * 0.05))
 vectorNear(linear.velocity, curved.velocity)
end)

test("disabled state bad origin policy and distant targets produce no output", function()
 local disabled = moving({Enabled = false})
 check(disabled:predict(zero, 0.1) == nil)
 local p = moving({MemoryTracking = false})
 check(p:predict({}, 0.1) == nil)
 check(p:predict(V.new(math.huge, 0, 0), 0.1) == nil)
 check(p:predict(zero, 0.1, "Invented") == nil)
 check(p:predict(V.new(-400, 0, 0), 0.1) == nil)
 local valid = p:predict(V.new(1, 2, 3), 0.1)
 check(valid ~= nil)
 near(valid.distanceStuds, 0)
end)

test("reset clears observation latency and every comparison policy", function()
 local p = moving({AutoPrediction = true, MemoryTracking = false, PredictionSmoothing = 0})
 check(p:samplePing(0.070, 0))
 local before = p:predictComparisons(zero, 0.1)
 check(before.active.status == "Auto")
 check(before.manual ~= nil and before.auto ~= nil)
 p:reset()
 check(p.history:latest() == nil)
 check(p:predict(zero, 0.1) == nil)
 local absent = p:predictComparisons(zero, 0.1)
 check(absent.active == nil and absent.manual == nil and absent.auto == nil)
 check(p:observe(2, V.new(20, 0, 0)))
 local output = p:predict(zero, 2)
 check(output.status == "AutoFallback")
 check(output.rawPingMs == nil and output.smoothedPingMs == nil)
 near(output.baseX, 0.1205)
 near(output.baseY, 0.08)
 vectorNear(output.position, V.new(20, 0, 0))
end)

print(string.format("PINK prediction: %d tests, %d assertions, %d failures", tests, checks, failures))
assert(failures == 0, "PINK prediction regression tests failed")
