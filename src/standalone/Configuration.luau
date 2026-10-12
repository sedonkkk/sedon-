--!nonstrict
-- Portable configuration for the authorized, local laboratory.
-- Times are seconds, RTT is milliseconds, distances and speeds use Roblox studs.
-- Revolver is an editable laboratory assumption, not third-party weapon data.
local Settings = if script then require(script.Parent.Parent.shared.Settings) else require("../shared/Settings")
local Weapons = if script then require(script.Parent.Parent.shared.Weapons) else require("../shared/Weapons")

local Configuration = {}
local PROFILE_NAMES = {"Revolver", "Default", "Custom"}
local RANGE_NAMES = {"close", "medium", "long"}
local PROFILE_KEYS = {
 kind = true, speed = true, gravity = true, cooldown = true, spreadRadians = true,
 radius = true, latencyOffsetSeconds = true, manualDelaySeconds = true, rangeOffsets = true,
}
local TOP_KEYS = {
 core = true, activeProfile = true, pingCompensation = true,
 predictionSmoothingSeconds = true, adaptiveCalibration = true, useSimulatedPing = true,
 simulatedRTTMilliseconds = true, simulatedObservationDelaySeconds = true,
 targetMode = true, profiles = true,
}
local PROFILE_LIMITS = {
 speed = {0, 20000}, gravity = {0, 1000}, cooldown = {0.01, 10},
 spreadRadians = {0, math.pi}, radius = {0, 20},
 latencyOffsetSeconds = {-0.2, 0.2}, manualDelaySeconds = {0, 0.6},
}

local function finite(value)
 return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function plainTable(value)
 return type(value) == "table" and getmetatable(value) == nil
end

local function knownKeys(object, allowed, location)
 if not plainTable(object) then return false, location .. " debe ser un objeto simple" end
 for key in object do
  if type(key) ~= "string" or not allowed[key] then
   return false, location .. ": campo desconocido " .. tostring(key)
  end
 end
 return true
end

local function bounded(value, bounds)
 return finite(value) and value >= bounds[1] and value <= bounds[2]
end

local function laboratoryProfile(name)
 local original = Weapons.get(name)
 local profile = {}
 for key in PROFILE_KEYS do
  if key ~= "manualDelaySeconds" and key ~= "rangeOffsets" then profile[key] = original[key] end
 end
 profile.manualDelaySeconds = 0.08
 -- Range offsets stay zero until measurements justify a signed correction.
 profile.rangeOffsets = {close = 0, medium = 0, long = 0}
 return profile
end

function Configuration.new()
 return {
  core = Settings.new(), activeProfile = "Revolver", pingCompensation = true,
  predictionSmoothingSeconds = 0.08, adaptiveCalibration = false, useSimulatedPing = true,
  simulatedRTTMilliseconds = 90, simulatedObservationDelaySeconds = 0.05,
  targetMode = "Simulated",
  profiles = {
   Revolver = laboratoryProfile("RevolverLab"),
   Default = laboratoryProfile("RevolverLab"),
   Custom = laboratoryProfile("ProjectileLab"),
  },
 }
end

local function validateCore(core, partial)
 local defaults = Settings.new()
 local allowed = {}
 for key in defaults do allowed[key] = true end
 local ok, message = knownKeys(core, allowed, "core")
 if not ok then return false, message end
 for key, value in core do
  local expected = defaults[key]
  if type(expected) ~= "table" and type(value) ~= type(expected) then
   return false, "core." .. key .. ": tipo incorrecto"
  end
  if type(value) == "number" and not finite(value) then return false, "core." .. key .. ": número no finito" end
 end
 if core.weaponOffsets ~= nil then
  ok, message = knownKeys(core.weaponOffsets, {RevolverLab = true, ProjectileLab = true}, "core.weaponOffsets")
  if not ok then return false, message end
  for _, key in {"RevolverLab", "ProjectileLab"} do
   local value = core.weaponOffsets[key]
   if (not partial or value ~= nil) and not bounded(value, {-0.2, 0.2}) then
    return false, "core.weaponOffsets." .. key .. " fuera de rango"
   end
  end
 end
 if core.pingCalibration ~= nil then
  local points = core.pingCalibration
  if not plainTable(points) then return false, "core.pingCalibration debe ser una lista simple" end
  local count = 0
  for key in points do
   if type(key) ~= "number" or key % 1 ~= 0 or key < 1 or key > 32 then
    return false, "core.pingCalibration: índice inválido"
   end
   count += 1
  end
  if count == 0 or count > 32 then return false, "core.pingCalibration requiere entre 1 y 32 puntos" end
  local previous = -math.huge
  for index = 1, count do
   local point = points[index]
   ok, message = knownKeys(point, {pingSeconds = true, offsetSeconds = true}, "core.pingCalibration")
   if not ok then return false, message end
   if not bounded(point.pingSeconds, {0, 1}) or not bounded(point.offsetSeconds, {-0.2, 0.2})
    or point.pingSeconds <= previous then
    return false, "core.pingCalibration desordenada o fuera de rango"
   end
   previous = point.pingSeconds
  end
 end
 if not partial then return Settings.validate(core) end
 return true
end

local function validateProfile(profile, partial, location)
 local ok, message = knownKeys(profile, PROFILE_KEYS, location)
 if not ok then return false, message end
 if (not partial or profile.kind ~= nil) and profile.kind ~= "hitscan" and profile.kind ~= "projectile" then
  return false, location .. ".kind debe ser hitscan o projectile"
 end
 for key, limits in PROFILE_LIMITS do
  if (not partial or profile[key] ~= nil) and not bounded(profile[key], limits) then
   return false, location .. "." .. key .. " fuera de rango"
  end
 end
 if profile.kind == "projectile" and profile.speed ~= nil and profile.speed <= 0 then
  return false, location .. ": el proyectil requiere velocidad positiva"
 end
 if not partial or profile.rangeOffsets ~= nil then
  ok, message = knownKeys(profile.rangeOffsets, {close = true, medium = true, long = true}, location .. ".rangeOffsets")
  if not ok then return false, message end
  for _, range in RANGE_NAMES do
   if (not partial or profile.rangeOffsets[range] ~= nil)
    and not bounded(profile.rangeOffsets[range], {-0.15, 0.15}) then
    return false, location .. ".rangeOffsets." .. range .. " fuera de rango"
   end
  end
 end
 return true
end

local function validateConfiguration(config, partial)
 local ok, message = knownKeys(config, TOP_KEYS, "configuration")
 if not ok then return false, message end
 local defaults = Configuration.new()
 for key, default in defaults do
  local value = config[key]
  if not partial or value ~= nil then
   if type(value) ~= type(default) then return false, key .. ": tipo incorrecto" end
  end
 end
 if (not partial or config.activeProfile ~= nil) and config.activeProfile ~= "Revolver"
  and config.activeProfile ~= "Default" and config.activeProfile ~= "Custom" then
  return false, "activeProfile desconocido"
 end
 if (not partial or config.targetMode ~= nil) and config.targetMode ~= "Simulated" and config.targetMode ~= "OwnCharacters" then
  return false, "targetMode debe ser Simulated o OwnCharacters"
 end
 for key, limits in {
  predictionSmoothingSeconds = {0, 1}, simulatedRTTMilliseconds = {0, 2000},
  simulatedObservationDelaySeconds = {0, 0.25},
 } do
  if (not partial or config[key] ~= nil) and not bounded(config[key], limits) then return false, key .. " fuera de rango" end
 end
 if not partial or config.core ~= nil then
  ok, message = validateCore(config.core, partial)
  if not ok then return false, message end
 end
 if not partial or config.profiles ~= nil then
  ok, message = knownKeys(config.profiles, {Revolver = true, Default = true, Custom = true}, "profiles")
  if not ok then return false, message end
  for _, name in PROFILE_NAMES do
   if not partial or config.profiles[name] ~= nil then
    ok, message = validateProfile(config.profiles[name], partial, "profiles." .. name)
    if not ok then return false, message end
   end
  end
 end
 return true
end

function Configuration.validate(config)
 return validateConfiguration(config, false)
end

local function copy(value)
 if type(value) ~= "table" then return value end
 local result = {}
 for key, child in value do result[key] = copy(child) end
 return result
end

local function merge(defaults, incoming)
 for key, value in incoming do
  if type(value) == "table" and key ~= "pingCalibration" then
   merge(defaults[key], value)
  else
   defaults[key] = copy(value)
  end
 end
 return defaults
end

-- Imports are atomic: invalid objects never touch the caller's live configuration.
-- Missing known fields receive fresh defaults; unknown fields are rejected.
function Configuration.import(decoded)
 local ok, message = validateConfiguration(decoded, true)
 if not ok then return nil, message end
 local config = merge(Configuration.new(), decoded)
 ok, message = Configuration.validate(config)
 if not ok then return nil, message end
 return config
end

function Configuration.createSnapshot(config)
 local ok, message = Configuration.validate(config)
 if not ok then return nil, message end
 return copy(config)
end

function Configuration.toEnvelope(config)
 local snapshot, message = Configuration.createSnapshot(config)
 if not snapshot then return nil, message end
 return {schemaVersion = 1, configuration = snapshot}
end

function Configuration.fromEnvelope(envelope)
 local ok, message = knownKeys(envelope, {schemaVersion = true, configuration = true}, "envelope")
 if not ok then return nil, message end
 if envelope.schemaVersion ~= 1 then return nil, "schemaVersion no compatible" end
 return Configuration.import(envelope.configuration)
end

function Configuration.rangeForDistance(distanceStuds)
 local distance = if finite(distanceStuds) then math.max(0, distanceStuds) else 0
 return if distance < 40 then "close" elseif distance < 120 then "medium" else "long"
end

function Configuration.getProfile(config, distanceStuds)
 local profile = copy(config.profiles[config.activeProfile])
 profile.name = config.activeProfile
 profile.latencyOffsetSeconds += profile.rangeOffsets[Configuration.rangeForDistance(distanceStuds)]
 return profile
end

function Configuration.prepareCore(config, _distanceStuds)
 local profile = config.profiles[config.activeProfile]
 config.core.manualDelaySeconds = profile.manualDelaySeconds
 -- Retain aliases accepted by the original core validator. The profile name used
 -- by prediction is separate, so its measured offsets are applied exactly once.
 config.core.weapon = if profile.kind == "projectile" then "ProjectileLab" else "RevolverLab"
 -- autoPrediction is the user's mode. Disabling ping compensation only zeroes
 -- the ping input in the runtime; it must not silently select manual prediction.
 return config.core
end

return Configuration
