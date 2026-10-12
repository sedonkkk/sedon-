--!nonstrict
-- All temporal values are seconds; all spatial values are Roblox studs.
local Settings = {}
local defaults = {
 enabled = true, autoPrediction = true, manualDelaySeconds = 0.08,
 pingSmoothingSeconds = 0.8, latencyOffsetSeconds = 0,
 minDelaySeconds = 0, maxDelaySeconds = 0.35,
 distancePrediction = true, velocityPrediction = true, accelerationPrediction = true,
 memoryTracking = true, debugVisualization = false, weapon = "RevolverLab",
 weaponOffsets = {RevolverLab = 0, ProjectileLab = 0},
 updateHz = 30, maxTargetDistanceStuds = 350, fovPixels = 180,
 simulationDelaySeconds = 0, historyCapacity = 12, historyWindowSeconds = 0.3,
 velocitySmoothingSeconds = 0.06, accelerationSmoothingSeconds = 0.15,
 maxObservedSpeedStuds = 120, maxAccelerationStuds = 180,
 teleportSlackStuds = 5, reversalDotThreshold = -0.2,
 maxAccelerationHorizonSeconds = 0.18, staleAfterSeconds = 0.6,
 latencySlewSecondsPerSecond = 0.12, maxFlightSeconds = 2,
 -- Calibration points use ONE-WAY ping, not user-facing round-trip milliseconds.
 -- Zero until measurements justify a nonzero replication/processing bias.
 pingCalibration = {
  {pingSeconds = 0.004, offsetSeconds = 0},
  {pingSeconds = 0.03, offsetSeconds = 0},
  {pingSeconds = 0.075, offsetSeconds = 0},
  {pingSeconds = 0.09, offsetSeconds = 0},
 },
}
function Settings.new()
 local s = table.clone(defaults)
 s.weaponOffsets = table.clone(defaults.weaponOffsets)
 s.pingCalibration = {}
 for _, point in defaults.pingCalibration do
  table.insert(s.pingCalibration, table.clone(point))
 end
 return s
end
local limits = {
 manualDelaySeconds={0,0.6},pingSmoothingSeconds={0.05,10},latencyOffsetSeconds={-0.2,0.2},
 minDelaySeconds={0,0.6},maxDelaySeconds={0,0.6},updateHz={5,60},
 maxTargetDistanceStuds={10,2000},fovPixels={20,1000},simulationDelaySeconds={0,0.25},
 historyCapacity={2,64},historyWindowSeconds={0.05,1},velocitySmoothingSeconds={0.001,1},
 accelerationSmoothingSeconds={0.01,2},maxObservedSpeedStuds={1,1000},
 maxAccelerationStuds={0,2000},teleportSlackStuds={0,100},reversalDotThreshold={-1,1},
 maxAccelerationHorizonSeconds={0,0.6},staleAfterSeconds={0.05,2},
 latencySlewSecondsPerSecond={0.001,2},maxFlightSeconds={0.05,5},
}
function Settings.validate(s)
 for name, bounds in limits do
  local value = s[name]
  if type(value) ~= "number" or value ~= value or value < bounds[1] or value > bounds[2] then
   return false, name .. " fuera de rango"
  end
 end
 for name, value in defaults do
  if type(value) == "boolean" and type(s[name]) ~= "boolean" then return false, name .. " debe ser booleano" end
 end
 if s.minDelaySeconds > s.maxDelaySeconds then return false, "minDelaySeconds supera maxDelaySeconds" end
 if s.historyCapacity % 1 ~= 0 then return false, "historyCapacity debe ser entero" end
 if s.weapon ~= "RevolverLab" and s.weapon ~= "ProjectileLab" then return false, "Perfil desconocido" end
 if type(s.weaponOffsets) ~= "table" then return false, "Faltan ajustes por arma" end
 for _,name in {"RevolverLab", "ProjectileLab"} do
  local value=s.weaponOffsets[name]
  if type(value)~="number" or value~=value or math.abs(value)>0.2 then return false, "Offset de arma fuera de rango" end
 end
 if type(s.pingCalibration) ~= "table" or #s.pingCalibration == 0 then return false, "Falta tabla de calibración" end
 local previous = -math.huge
 for _, point in s.pingCalibration do
  if type(point) ~= "table" or type(point.pingSeconds) ~= "number" or type(point.offsetSeconds) ~= "number" then
   return false, "Punto de calibración inválido"
  end
  if point.pingSeconds ~= point.pingSeconds or point.offsetSeconds ~= point.offsetSeconds
   or point.pingSeconds <= previous or point.pingSeconds > 1 or point.pingSeconds < 0
   or math.abs(point.offsetSeconds) > 0.2 then return false, "Calibración desordenada o fuera de rango" end
  previous = point.pingSeconds
 end
 return true
end
return Settings
