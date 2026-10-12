--!nonstrict
-- Error measurements only describe this laboratory's own known target motion.
-- No claim of ground truth is made for a remote or third-party target.
-- Signed residual = actual target position minus predicted target position.
local Calibration = {}
Calibration.__index = Calibration
local RANGE_NAMES = {close = true, medium = true, long = true}
local WEAPON_NAMES = {Revolver = true, Default = true, Custom = true}

local function finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function freshBucket()
 return {autoCount = 0, manualCount = 0, autoSquaredError = 0, manualSquaredError = 0,
  confidenceSamples = 0, suggestedOffsetSeconds = 0, lastTime = nil}
end

local function resetLearning(bucket)
 bucket.confidenceSamples = 0; bucket.suggestedOffsetSeconds = 0
 bucket.lastCorrectionTime = nil
 for _, entry in bucket.entries or {} do entry.trained = false end
end

function Calibration.new(options)
 options = if type(options) == "table" then options else {}
 -- A two-second EMA, minimum 2 studs/s, and ±150 ms recommendation cap keep
 -- noisy or nearly stationary motion from producing large temporal corrections.
 local tau = if finite(options.smoothingSeconds) then math.clamp(options.smoothingSeconds, 0.05, 30) else 2
 local minimumSpeed = if finite(options.minimumSpeedStuds) then math.clamp(options.minimumSpeedStuds, 2, 100) else 2
 local maxOffset = if finite(options.maxOffsetSeconds) then math.clamp(options.maxOffsetSeconds, 0.001, 0.15) else 0.15
 local capacity = if finite(options.capacity) then math.clamp(math.floor(options.capacity), 1, 1000) else 120
 local freshness = if finite(options.freshnessSeconds) then math.clamp(options.freshnessSeconds, 0.1, 60) else 5
 return setmetatable({buckets = {}, smoothingSeconds = tau, minimumSpeedStuds = minimumSpeed,
  maxOffsetSeconds = maxOffset, capacity = capacity, freshnessSeconds = freshness}, Calibration)
end

function Calibration:clear()
 table.clear(self.buckets)
end

local function validVector(value)
 if value == nil then return false end
 local ok, result = pcall(function()
  return finite(value.X) and finite(value.Y) and finite(value.Z) and type(value.Dot) == "function"
 end)
 return ok and result
end

function Calibration:record(measurement)
 if type(measurement) ~= "table" then return false, "Medición inválida" end
 local weapon, range, mode = measurement.weapon, measurement.range, measurement.mode
 if not WEAPON_NAMES[weapon] or not RANGE_NAMES[range] then return false, "Perfil o rango desconocido" end
 if mode ~= "auto" and mode ~= "manual" then return false, "Modo de medición inválido" end
 local error, now = measurement.errorStuds, measurement.now
 if not finite(error) or error < 0 or error > 10000 or not finite(now) then return false, "Error o tiempo inválido" end
 local key = weapon .. ":" .. range
 local bucket = self.buckets[key]
 if not bucket then bucket = freshBucket(); self.buckets[key] = bucket end
 if bucket.lastTime and now < bucket.lastTime then return false, "Tiempo de medición anterior" end
 bucket.lastTime = now
 -- A correction needs recent stable motion. Old confidence must not authorize
 -- repeated changes after a pause, target turn, or a long stationary interval.
 if bucket.lastCorrectionTime and now - bucket.lastCorrectionTime > self.freshnessSeconds then resetLearning(bucket) end
 local entries = bucket.entries
 if not entries then entries = {}; bucket.entries = entries end
 local entry = {mode = mode, squaredError = error * error, trained = false}
 table.insert(entries, entry)
 if mode == "auto" then bucket.autoCount += 1; bucket.autoSquaredError += error * error
 else bucket.manualCount += 1; bucket.manualSquaredError += error * error end
 if #entries > self.capacity then
  local oldest = table.remove(entries, 1)
  if oldest.mode == "auto" then bucket.autoCount -= 1; bucket.autoSquaredError -= oldest.squaredError
  else bucket.manualCount -= 1; bucket.manualSquaredError -= oldest.squaredError end
  if oldest.trained then bucket.confidenceSamples -= 1 end
  if bucket.confidenceSamples == 0 then resetLearning(bucket) end
 end

 -- Manual measurements only feed the comparison metrics. They never train the
 -- automatic recommendation, even when vectors are available.
 local residual, velocity = measurement.residual, measurement.velocity
 if mode == "auto" and validVector(residual) and validVector(velocity) then
  local ok, speedSquared, projection = pcall(function()
   return velocity:Dot(velocity), residual:Dot(velocity)
  end)
  if ok and finite(speedSquared) and finite(projection) and speedSquared > self.minimumSpeedStuds ^ 2 then
   local correction = math.clamp(projection / speedSquared, -self.maxOffsetSeconds, self.maxOffsetSeconds)
   local previous = bucket.lastCorrectionTime
   -- Use a short first interval, so the first sample is damped too. Equal-time
   -- duplicates cannot move the estimate, regardless of frame or sample rate.
   local dt = if bucket.lastTrainingTimestamp == now then 0 elseif previous then math.max(0, now - previous) else 0.1
   local alpha = 1 - math.exp(-dt / self.smoothingSeconds)
   bucket.suggestedOffsetSeconds = math.clamp(
    bucket.suggestedOffsetSeconds + (correction - bucket.suggestedOffsetSeconds) * alpha,
    -self.maxOffsetSeconds, self.maxOffsetSeconds)
   if dt > 0 then
    bucket.lastCorrectionTime = now; bucket.lastTrainingTimestamp = now
    entry.trained = true; bucket.confidenceSamples += 1
   end
  end
 end
 return true
end

function Calibration:summary(weapon, range, now)
 local bucket = if WEAPON_NAMES[weapon] and RANGE_NAMES[range] then self.buckets[weapon .. ":" .. range] else nil
 bucket = bucket or freshBucket()
 -- Optional caller time permits expiry even if no measurements have arrived.
 -- Reading a summary never changes the measurement window or live state.
 local stale = finite(now) and bucket.lastCorrectionTime ~= nil
  and now - bucket.lastCorrectionTime > self.freshnessSeconds
 return {
  autoCount = bucket.autoCount, manualCount = bucket.manualCount,
  autoRMSEStuds = if bucket.autoCount > 0 then math.sqrt(math.max(0, bucket.autoSquaredError) / bucket.autoCount) else 0,
  manualRMSEStuds = if bucket.manualCount > 0 then math.sqrt(math.max(0, bucket.manualSquaredError) / bucket.manualCount) else 0,
  suggestedOffsetSeconds = if stale then 0 else bucket.suggestedOffsetSeconds,
  confidenceSamples = if stale then 0 else bucket.confidenceSamples,
 }
end

function Calibration:suggest(weapon, range, now)
 local summary = self:summary(weapon, range, now)
 return summary.suggestedOffsetSeconds, summary.confidenceSamples
end

return Calibration
