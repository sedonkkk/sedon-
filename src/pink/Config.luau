--!nonstrict
-- PINK DOT LOCK configuration. Prediction X/Y and offsets are seconds;
-- reference pings are RTT milliseconds, spatial values use Roblox studs.
local Settings = if script then require(script.Parent.Parent.shared.Settings) else require("../shared/Settings")
local Config = {}

-- The standalone builder copies this native literal to the editable file header.
Config.sourceLiteral = [=[{
 Enabled=true, LockKey="C", LockMode="Auto",
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
 InitializationTimeout=8, InitializationPollInterval=0.05,
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
function Config.defaults()
 return {
 Enabled=true, LockKey="C", LockMode="Auto",
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
 InitializationTimeout=8, InitializationPollInterval=0.05,
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
  -- LockKey was validated before merge. Preserve its canonical reference even
  -- when an external host reports a different typeof; never clone an Enum.
  if key=="LockKey" then into[key]=value
  elseif typeof(value)=="EnumItem" or typeof(value)=="Color3" then into[key]=value
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
 InitializationTimeout={0.1,30},InitializationPollInterval={0.01,1},
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
local function describe(problem)
 local ok,message=pcall(tostring,problem)
 return if ok then message else "error de API sin representación textual"
end
local function sameEnum(a,b)
 if rawequal(a,b) then return true end
 -- Native userdata may use value equality across engine wrappers. Plain Lua
 -- tables must be the actual canonical reference, so __eq cannot forge keys.
 if type(a)=="userdata" and type(b)=="userdata" then
  local ok,equal=pcall(function() return a==b end)
  return ok and equal
 end
 return false
end
-- Without Roblox, numerical CLI tests may retain known key names as text.
-- A client still requires native Enum/services in Runtime; never use arbitrary
-- strings or enum-shaped tables as a substitute for a usable native key.
local offlineKeys={}
for code=string.byte("A"),string.byte("Z") do offlineKeys[string.char(code)]=true end
for i=1,15 do offlineKeys["F"..i]=true end
for name in string.gmatch("Zero One Two Three Four Five Six Seven Eight Nine Space Tab Return Escape Backspace Delete Insert Home End PageUp PageDown Up Down Left Right LeftShift RightShift LeftControl RightControl LeftAlt RightAlt CapsLock NumLock ScrollLock", "%S+") do
 offlineKeys[name]=true
end
function Config.normalizeLockKey(value)
 local name=if type(value)=="string" then value else nil
 if name and (#name==0 or #name>32 or not string.match(name,"^[A-Za-z][A-Za-z0-9]*$")) then
  return nil,"LockKey inválido: utiliza un nombre de Enum.KeyCode, por ejemplo C"
 end
 if Enum==nil then
  if name and offlineKeys[name] then return name end
  return nil,"LockKey inválido o inexistente; sin Enum nativo solo se admiten nombres conocidos para pruebas numéricas"
 end
 local enumOK,keyCode=pcall(function() return Enum.KeyCode end)
 if not enumOK or not keyCode then
  return nil,"LockKey: Enum.KeyCode no está disponible: "..describe(keyCode)
 end
 local candidate=value
 if name then
  local found,resolved=pcall(function() return keyCode[name] end)
  if not found or resolved==nil then
   return nil,"LockKey inexistente en Enum.KeyCode: "..name..(if found then "" else "; "..describe(resolved))
  end
  candidate=resolved
 elseif type(value)~="userdata" and type(value)~="table" then
  return nil,"LockKey inválido: se requiere un nombre o elemento de Enum.KeyCode"
 end
 local listed,items=pcall(function() return keyCode:GetEnumItems() end)
 if not listed or type(items)~="table" or #items==0 then
  return nil,"LockKey: no se pudieron validar los miembros de Enum.KeyCode: "..describe(items)
 end
 for _,canonical in ipairs(items) do
  if sameEnum(candidate,canonical) then
   local inspected,keyName,parent,indexed=pcall(function()
    local canonicalName=canonical.Name
    return canonicalName,canonical.EnumType,keyCode[canonicalName]
   end)
   if not inspected then return nil,"LockKey: error al verificar Enum.KeyCode: "..describe(keyName) end
   if type(keyName)~="string" or not sameEnum(parent,keyCode) or not sameEnum(indexed,canonical) then
    return nil,"LockKey inválido: no corresponde a un miembro canónico de Enum.KeyCode"
   end
   if keyName=="Unknown" or keyName=="None" then return nil,"LockKey inválido: "..keyName.." no identifica una tecla de bloqueo" end
   return canonical
  end
 end
 return nil,"LockKey inválido: el valor no pertenece a Enum.KeyCode"
end
function Config.keyName(value)
 if type(value)=="string" then return value end
 local ok,name=pcall(function() return value.Name end)
 return if ok and type(name)=="string" then name else "?"
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
 local resolvedKey,keyMessage=Config.normalizeLockKey(config.LockKey)
 if not resolvedKey then return false,keyMessage end
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
 if overrides==nil then overrides={} end
 local defaults=Config.defaults()
 local ok,message=validateOverrides(overrides,defaults,"Config")
 if not ok then return nil,message end
 -- Known-shape checks precede recursion, so functions, cyclic objects, Instances
 -- and unknown nested keys cannot become retained setup/configuration values.
 for _,key in {"DotColor","DotOutlineColor"} do
  if overrides[key]~=nil and not colorOK(overrides[key]) then return nil,"Color del DOT inválido" end
 end
 local resolvedKey,keyMessage=Config.normalizeLockKey(if overrides.LockKey~=nil then overrides.LockKey else defaults.LockKey)
 if not resolvedKey then return nil,keyMessage end
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
 normalized.LockKey=resolvedKey
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
