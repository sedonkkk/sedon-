--!nonstrict
-- PINK DOT LOCK configuration. Prediction X/Y and offsets are seconds;
-- reference pings are RTT milliseconds, spatial values use Roblox studs.
local Settings = if script then require(script.Parent.Parent.shared.Settings) else require("../shared/Settings")
local Config = {}

-- The standalone builder copies this native literal to the editable file header.
Config.sourceLiteral = [=[{
 Enabled=true, LockKey=Enum.KeyCode.C, LockMode="Auto",
 FirstPersonFOV=120, ThirdPersonFOV=180,
 PredictionX=0.1205, PredictionY=0.0800, AutoPrediction=false,
 PingCompensation=true, PingSmoothing=0.8,
 PingReferences={{PingMs=55,X=0.113,Y=0.075},{PingMs=62,X=0.120,Y=0.080},{PingMs=70,X=0.128,Y=0.085}},
 MinPredictionX=0, MaxPredictionX=0.35, MinPredictionY=0, MaxPredictionY=0.35, PredictionSlew=0.06,
 MemoryTracking=true, VelocityPrediction=true, DistancePrediction=true, AccelerationPrediction=false,
 PredictionSmoothing=0.08, TargetPart="HumanoidRootPart", TargetPersistence=true, VisibilityCheck=true,
 ShowDot=true, DotSize=6, DotColor=Color3.fromRGB(255,105,180), DotTransparency=0,
 DotOutline=true, DotOutlineColor=Color3.fromRGB(255,255,255),
 ShowNotifications=true, WelcomeNotification=true, WelcomeDuration=4, NotificationDuration=2,
 WeaponProfile="Revolver", CloseOffset=0, MediumOffset=0, LongOffset=0, DebugMode=false,
 UpdateHz=30, PingHz=5, StaleAfter=0.6, ModeDwellSeconds=0.2, ModeEnterDistance=0.75, ModeExitDistance=1.5, MaxDistance=350,
 CloseDistance=40, MediumDistance=120,
 HistoryCapacity=12, HistoryWindow=0.3, VelocitySmoothing=0.06, AccelerationSmoothing=0.15,
 MaxObservedSpeed=120, MaxAcceleration=180, TeleportSlack=5, ReversalDotThreshold=-0.2,
 MaxAccelerationHorizon=0.18, MaxFlightSeconds=2,
 Profiles={
  Revolver={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
  Default={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
  Custom={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
 },
}]=]

local function color(r,g,b)
 if Color3 and type(Color3.fromRGB)=="function" then return Color3.fromRGB(r,g,b) end
 return {R=r/255,G=g/255,B=b/255}
end
local function lockKey()
 if Enum and Enum.KeyCode then return Enum.KeyCode.C end
 return "C"
end
function Config.defaults()
 return {
 Enabled=true, LockKey=lockKey(), LockMode="Auto",
 FirstPersonFOV=120, ThirdPersonFOV=180,
 PredictionX=0.1205, PredictionY=0.0800, AutoPrediction=false,
 PingCompensation=true, PingSmoothing=0.8,
 PingReferences={{PingMs=55,X=0.113,Y=0.075},{PingMs=62,X=0.120,Y=0.080},{PingMs=70,X=0.128,Y=0.085}},
 MinPredictionX=0, MaxPredictionX=0.35, MinPredictionY=0, MaxPredictionY=0.35, PredictionSlew=0.06,
 MemoryTracking=true, VelocityPrediction=true, DistancePrediction=true, AccelerationPrediction=false,
 PredictionSmoothing=0.08, TargetPart="HumanoidRootPart", TargetPersistence=true, VisibilityCheck=true,
 ShowDot=true, DotSize=6, DotColor=color(255,105,180), DotTransparency=0,
 DotOutline=true, DotOutlineColor=color(255,255,255),
 ShowNotifications=true, WelcomeNotification=true, WelcomeDuration=4, NotificationDuration=2,
 WeaponProfile="Revolver", CloseOffset=0, MediumOffset=0, LongOffset=0, DebugMode=false,
 UpdateHz=30, PingHz=5, StaleAfter=0.6, ModeDwellSeconds=0.2, ModeEnterDistance=0.75, ModeExitDistance=1.5, MaxDistance=350,
 CloseDistance=40, MediumDistance=120,
 HistoryCapacity=12, HistoryWindow=0.3, VelocitySmoothing=0.06, AccelerationSmoothing=0.15,
 MaxObservedSpeed=120, MaxAcceleration=180, TeleportSlack=5, ReversalDotThreshold=-0.2,
 MaxAccelerationHorizon=0.18, MaxFlightSeconds=2,
 Profiles={
  Revolver={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
  Default={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
  Custom={PredictionXOffset=0, PredictionYOffset=0, LatencyOffsetSeconds=0, CloseOffset=0, MediumOffset=0, LongOffset=0, Kind="Unknown", Speed=0, Gravity=0},
 },
}
end

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function bounded(value, minimum, maximum)
 return finite(value) and value>=minimum and value<=maximum
end
local function copy(value)
 if typeof(value)=="EnumItem" or typeof(value)=="Color3" then return value end
 if type(value)~="table" then return value end
 local result={}
 for key,child in value do result[key]=copy(child) end
 return result
end
local function merge(into, overrides)
 for key,value in overrides do
  if typeof(value)=="EnumItem" or typeof(value)=="Color3" then into[key]=value
  elseif key=="PingReferences" then into[key]=copy(value)
  elseif type(value)=="table" and type(into[key])=="table" then merge(into[key],value)
  else into[key]=copy(value) end
 end
 return into
end
local limits={
 FirstPersonFOV={1,2000},ThirdPersonFOV={1,2000},PredictionX={0,0.6},PredictionY={0,0.6},
 PingSmoothing={0.05,10},MinPredictionX={0,0.6},MaxPredictionX={0,0.6},MinPredictionY={0,0.6},MaxPredictionY={0,0.6},
 PredictionSlew={0.001,2},PredictionSmoothing={0,2},DotSize={1,40},DotTransparency={0,1},
 WelcomeDuration={0.1,30},NotificationDuration={0.1,30},CloseOffset={-0.2,0.2},MediumOffset={-0.2,0.2},LongOffset={-0.2,0.2},
 UpdateHz={5,60},PingHz={0.5,20},StaleAfter={0.05,2},ModeDwellSeconds={0.01,2},ModeEnterDistance={0.05,5},ModeExitDistance={0.1,10},
 MaxDistance={10,2000},CloseDistance={1,2000},MediumDistance={2,2000},
 HistoryCapacity={2,64},HistoryWindow={0.05,1},VelocitySmoothing={0.001,1},AccelerationSmoothing={0.01,2},
 MaxObservedSpeed={1,1000},MaxAcceleration={0,2000},TeleportSlack={0,100},ReversalDotThreshold={-1,1},
 MaxAccelerationHorizon={0,0.6},MaxFlightSeconds={0.05,5},
}
local profileLimits={PredictionXOffset={-0.2,0.2},PredictionYOffset={-0.2,0.2},LatencyOffsetSeconds={-0.2,0.2},
 CloseOffset={-0.2,0.2},MediumOffset={-0.2,0.2},LongOffset={-0.2,0.2},Speed={0,20000},Gravity={0,1000}}
local function known(object, defaults, path)
 if type(object)~="table" or getmetatable(object)~=nil then return false,path.." debe ser una tabla simple" end
 for key,value in object do
  if type(key)~="string" or defaults[key]==nil then return false,path..": campo desconocido "..tostring(key) end
  local expected=defaults[key]
  if type(expected)=="boolean" and type(value)~="boolean" then return false,path.."."..key.." debe ser booleano" end
  if type(expected)=="number" and not finite(value) then return false,path.."."..key.." debe ser un número finito" end
  if type(expected)=="string" and key~="LockKey" and type(value)~="string" then return false,path.."."..key.." debe ser texto" end
 end
 return true
end
local function colorOK(value)
 if typeof(value)=="Color3" then return bounded(value.R,0,1) and bounded(value.G,0,1) and bounded(value.B,0,1) end
 if type(value)~="table" or getmetatable(value)~=nil then return false end
 for key in value do if key~="R" and key~="G" and key~="B" then return false end end
 return bounded(value.R,0,1) and bounded(value.G,0,1) and bounded(value.B,0,1)
end
local function keyOK(value)
 if typeof(value)=="EnumItem" then return tostring(value.EnumType)=="Enum.KeyCode" end
 if type(value)=="string" then return #value>0 and #value<=32 and string.match(value,"^%w+$")~=nil end
 -- Native-enum-shaped test doubles let numerical tests run without Roblox.
 if type(value)=="table" and getmetatable(value)==nil then
  for key in value do if key~="Name" and key~="EnumType" then return false end end
  return type(value.Name)=="string" and value.EnumType=="KeyCode"
 end
 return false
end
local function validate(config)
 local defaults=Config.defaults()
 local ok,message=known(config,defaults,"Config")
 if not ok then return false,message end
 for key in defaults do
  if config[key]==nil then return false,"Falta Config."..key end
 end
 for key,bounds in limits do
  if not bounded(config[key],bounds[1],bounds[2]) then return false,key.." fuera de rango" end
 end
 if config.HistoryCapacity%1~=0 then return false,"HistoryCapacity debe ser entero" end
 if config.LockMode~="Auto" and config.LockMode~="FirstPerson" and config.LockMode~="ThirdPerson" then return false,"LockMode desconocido" end
 if not keyOK(config.LockKey) then return false,"LockKey debe ser Enum.KeyCode" end
 if not colorOK(config.DotColor) or not colorOK(config.DotOutlineColor) then return false,"Color del DOT inválido" end
 if type(config.TargetPart)~="string" or #config.TargetPart==0 or #config.TargetPart>80 then return false,"TargetPart inválido" end
 if config.MinPredictionX>config.MaxPredictionX or config.MinPredictionY>config.MaxPredictionY then return false,"Límites de predicción invertidos" end
 if not bounded(config.PredictionX,config.MinPredictionX,config.MaxPredictionX)
  or not bounded(config.PredictionY,config.MinPredictionY,config.MaxPredictionY) then return false,"Predicción manual fuera de límites" end
 if config.ModeEnterDistance>=config.ModeExitDistance then return false,"ModeEnterDistance debe ser menor que ModeExitDistance" end
 if config.CloseDistance>=config.MediumDistance then return false,"Rangos de distancia invertidos" end
 if type(config.Profiles)~="table" or getmetatable(config.Profiles)~=nil then return false,"Profiles inválidos" end
 for name in config.Profiles do if defaults.Profiles[name]==nil then return false,"Perfil desconocido" end end
 if defaults.Profiles[config.WeaponProfile]==nil then return false,"WeaponProfile desconocido" end
 for name in defaults.Profiles do if config.Profiles[name]==nil then return false,"Falta Profiles."..name end end
 for name,profile in config.Profiles do
  ok,message=known(profile,defaults.Profiles[name],"Profiles."..name)
  if not ok then return false,message end
  for key,bounds in profileLimits do if not bounded(profile[key],bounds[1],bounds[2]) then return false,"Profiles."..name.."."..key.." fuera de rango" end end
  if profile.Kind~="Unknown" and profile.Kind~="Hitscan" and profile.Kind~="Projectile" then return false,"Kind desconocido" end
  if profile.Kind=="Projectile" and profile.Speed<=0 then return false,"Projectile requiere Speed positivo" end
 end
 local points=config.PingReferences
 if type(points)~="table" or getmetatable(points)~=nil then return false,"PingReferences inválido" end
 local count=0
 for key in points do
  if type(key)~="number" or key%1~=0 or key<1 or key>32 then return false,"Índice de PingReferences inválido" end
  count+=1
 end
 if count<1 then return false,"PingReferences requiere puntos" end
 local previous=-math.huge
 for i=1,count do
  local point=points[i]
  ok,message=known(point,{PingMs=0,X=0,Y=0},"PingReferences")
  if not ok then return false,message end
  if not bounded(point.PingMs,0,2000) or point.PingMs<=previous
   or not bounded(point.X,0,0.6)
   or not bounded(point.Y,0,0.6) then return false,"PingReferences desordenado o fuera de límites" end
  previous=point.PingMs
 end
 return true
end
local function validateOverrides(overrides, defaults, path)
 local ok,message=known(overrides,defaults,path)
 if not ok then return false,message end
 for key,value in overrides do
  if key=="Profiles" then
   if type(value)~="table" or getmetatable(value)~=nil then return false,"Profiles debe ser una tabla simple" end
   for name,profile in value do
    if defaults.Profiles[name]==nil then return false,"Perfil desconocido" end
    ok,message=known(profile,defaults.Profiles[name],"Profiles."..name)
    if not ok then return false,message end
   end
  elseif type(value)=="table" and key~="DotColor" and key~="DotOutlineColor" and key~="LockKey" and key~="PingReferences" then
   return false,path.."."..key..": tipo incorrecto"
  end
 end
 return true
end
function Config.new(overrides)
 if overrides==nil then return Config.defaults() end
 local defaults=Config.defaults()
 local ok,message=validateOverrides(overrides,defaults,"Config")
 if not ok then return nil,message end
 -- Known-shape checks precede recursion, so functions, cyclic objects, Instances
 -- and unknown nested keys cannot become retained setup/configuration values.
 for _,key in {"DotColor","DotOutlineColor"} do
  if overrides[key]~=nil and not colorOK(overrides[key]) then return nil,"Color del DOT inválido" end
 end
 if overrides.LockKey~=nil and not keyOK(overrides.LockKey) then return nil,"LockKey inválido" end
 if overrides.PingReferences~=nil then
  -- A shallow shape check prevents recursive-copying of cyclic point objects.
  local points=overrides.PingReferences
  if type(points)~="table" or getmetatable(points)~=nil then return nil,"PingReferences inválido" end
  for index,point in points do
   if type(index)~="number" or index%1~=0 or index<1 or index>32 then return nil,"Índice de PingReferences inválido" end
   ok,message=known(point,{PingMs=0,X=0,Y=0},"PingReferences")
   if not ok then return nil,message end
  end
 end
 local normalized=merge(defaults,overrides)
 if type(normalized.LockKey)=="string" and Enum then
  local resolved,key=pcall(function() return Enum.KeyCode[normalized.LockKey] end)
  if not resolved or key==nil then return nil,"LockKey no existe en Enum.KeyCode" end
  normalized.LockKey=key
 end
 ok,message=validate(normalized)
 if not ok then return nil,message end
 return normalized
end
function Config.validate(config) return validate(config) end
function Config.toSettings(config, into)
 local settings=into or Settings.new()
 settings.enabled=config.Enabled; settings.autoPrediction=config.AutoPrediction
 settings.pingSmoothingSeconds=config.PingSmoothing; settings.distancePrediction=config.DistancePrediction
 settings.velocityPrediction=config.VelocityPrediction; settings.accelerationPrediction=config.AccelerationPrediction
 settings.memoryTracking=config.MemoryTracking; settings.updateHz=config.UpdateHz
 settings.maxTargetDistanceStuds=config.MaxDistance; settings.historyCapacity=config.HistoryCapacity
 settings.historyWindowSeconds=config.HistoryWindow; settings.velocitySmoothingSeconds=config.VelocitySmoothing
 settings.accelerationSmoothingSeconds=config.AccelerationSmoothing; settings.maxObservedSpeedStuds=config.MaxObservedSpeed
 settings.maxAccelerationStuds=config.MaxAcceleration; settings.teleportSlackStuds=config.TeleportSlack
 settings.reversalDotThreshold=config.ReversalDotThreshold; settings.maxAccelerationHorizonSeconds=config.MaxAccelerationHorizon
 settings.staleAfterSeconds=config.StaleAfter; settings.latencySlewSecondsPerSecond=config.PredictionSlew
 settings.maxFlightSeconds=config.MaxFlightSeconds
 return settings
end
return Config
