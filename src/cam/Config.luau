--!nonstrict
-- V3 visible scale has one explicit, provisional linear calibration to seconds.
local PinkConfig = if script then require(script.Parent.Parent.pink.Config) else require("../pink/Config")
local Config = {}

-- The standalone builder copies this literal to the editable file header.
Config.sourceLiteral = [=[{
 Enabled=false, HitPart="UpperTorso",
 PredictionX=13.15, PredictionY=13.15, Smoothness=0.405, Radius=180,
 LogoAssetId="rbxassetid://COLOCAR_ID_REAL", DebugMode=false, NotificationCooldown=3,
 Fly=false, FlyKeybind="V", FlySpeed=65, Speed=false, SpeedKeybind="G", WalkSpeed=24,
 FlyUpKey="Space", FlyDownKey="LeftControl", FlySmoothing=0.10, FlyMaxForce=100000,
 MovementAuthorized=false, MovementMode="Auto", LocalMovementAllowed=false,
 ESPAuthorized=false, ESPUnlimitedRange=false, ESPFarDistance=350, ESPFarUpdateHz=3,
 VerticalControl=true, RisingHorizon=0.055, FallingHorizon=0.045, ApexHorizon=0.025,
 MaxVerticalLead=2.25, MaxVerticalSpeed=85, MaxVerticalVelocityChange=450, ApexVelocity=3,
 LandingHoldSeconds=0.10, ReversalDamping=true, ReversalWindow=0.08, ReversalScale=0.5,
 AngularSafety=true, PitchMaxSpeed=180, PitchMaxAcceleration=1200, CloseSafetyDistance=8,
 MovementProbeSeconds=0.8, MovementMinimumSpeed=1,
 ReferenceScale=13.15, ReferenceHorizontalSeconds=0.1205, ReferenceVerticalSeconds=0.0800,
 MinScale=0, MaxScale=100, TrackingMode="Fixed", AdaptiveMinTau=0.008, AdaptiveMaxTau=0.06,
 AdaptiveErrorDegrees=8, AdaptiveGainSmoothing=0.08, CriticalFrequency=18,
 AngularMaxSpeed=720, AngularMaxAcceleration=4000, SmartSelection=false,
 TargetPartGraceSeconds=0.15, ReacquireOnLoss=false, TargetGraceSeconds=0.2, ReleaseRadiusMultiplier=1.3, TargetVisibilityHz=10,
 MotionFilter="Memory", FilterMinCutoff=1, FilterBeta=0.05, AlphaBetaAlpha=0.85, AlphaBetaBeta=0.05,
 ESP=false, Hitboxes=false, Names=false, ESPTargetMode="All", ESPUsername="",
 ESPUpdateHz=10, ESPMaxDistance=350, ESPOcclusionMode="VisibleOnly", ESPLowPerformanceMode=true,
 ShowFOV=false,
 -- Internal settings: these intentionally have no extra GUI controls.
 LockKey="C", AutoPrediction=false, PingCompensation=true, PingSmoothing=0.8,
 PingReferences={{PingMs=55,X=0.113,Y=0.075},{PingMs=62,X=0.120,Y=0.080},{PingMs=70,X=0.128,Y=0.085}},
 MinPredictionX=0, MaxPredictionX=0.35, MinPredictionY=0, MaxPredictionY=0.35, PredictionSlew=0.06,
 MemoryTracking=true, VelocityPrediction=true, DistancePrediction=true, AccelerationPrediction=false,
 CameraDebugMode=false, CameraDebugInterval=0.5,
 PredictionSmoothing=0, VisibilityCheck=true, FallbackR6=true, RespectScriptableCamera=true,
 MaxDistance=350, AcquisitionInterval=0.25,
 CloseDistance=40, MediumDistance=120, CloseOffset=0, MediumOffset=0, LongOffset=0,
 ShowNotifications=true, WelcomeNotification=true, WelcomeDuration=3, NotificationDuration=2,
 InitializationTimeout=8, InitializationPollInterval=0.05, UpdateHz=30, PingHz=5, StaleAfter=0.6,
 HistoryCapacity=12, HistoryWindow=0.3, VelocitySmoothing=0.06, AccelerationSmoothing=0.15,
 MaxObservedSpeed=120, MaxAcceleration=180, TeleportSlack=5, ReversalDotThreshold=-0.2,
 MaxAccelerationHorizon=0.18,
}]=]

Config.HitParts = {"Head", "UpperTorso", "HumanoidRootPart"}
Config.hitParts = Config.HitParts
Config.numericLimits = {
 RisingHorizon={0,0.35}, FallingHorizon={0,0.35}, ApexHorizon={0,0.35},
 MaxVerticalLead={0,20}, MaxVerticalSpeed={1,200}, MaxVerticalVelocityChange={1,5000}, ApexVelocity={0.1,20},
 LandingHoldSeconds={0,0.5}, ReversalWindow={0.01,1}, ReversalScale={0,1},
 PitchMaxSpeed={1,1000}, PitchMaxAcceleration={1,20000}, CloseSafetyDistance={0,30},
 MovementProbeSeconds={0.2,5}, MovementMinimumSpeed={0.1,10}, ESPFarDistance={10,2000}, ESPFarUpdateHz={1,10},
 PredictionX={0,1000}, PredictionY={0,1000}, ReferenceScale={0.001,1000},
 ReferenceHorizontalSeconds={0,0.6}, ReferenceVerticalSeconds={0,0.6}, MinScale={0,1000}, MaxScale={0.001,1000},
 AdaptiveMinTau={0.001,1}, AdaptiveMaxTau={0.001,1}, AdaptiveErrorDegrees={0.01,180}, AdaptiveGainSmoothing={0,1},
 CriticalFrequency={0.1,100}, AngularMaxSpeed={1,5000}, AngularMaxAcceleration={1,50000},
 TargetPartGraceSeconds={0,1}, TargetGraceSeconds={0,2}, ReleaseRadiusMultiplier={1,3}, TargetVisibilityHz={1,30},
 FilterMinCutoff={0.01,100}, FilterBeta={0,10}, AlphaBetaAlpha={0.01,1}, AlphaBetaBeta={0.001,1}, Smoothness={0,1}, Radius={1,2000},
 CameraDebugInterval={0.1,10}, NotificationCooldown={0.1,30},
 FlySpeed={1,200}, WalkSpeed={1,100}, FlySmoothing={0,1}, FlyMaxForce={1000,10000000},
 ESPUpdateHz={1,30}, ESPMaxDistance={10,2000},
 PingSmoothing={0.05,10}, MinPredictionX={0,0.6}, MaxPredictionX={0,0.6}, MinPredictionY={0,0.6}, MaxPredictionY={0,0.6},
 PredictionSlew={0.001,2}, PredictionSmoothing={0,2}, MaxDistance={10,2000}, AcquisitionInterval={0.05,2},
 CloseDistance={1,2000}, MediumDistance={2,2000}, CloseOffset={-0.2,0.2}, MediumOffset={-0.2,0.2}, LongOffset={-0.2,0.2},
 WelcomeDuration={0.1,30}, NotificationDuration={0.1,30}, InitializationTimeout={0.1,30}, InitializationPollInterval={0.01,1},
 UpdateHz={5,60}, PingHz={0.5,20}, StaleAfter={0.05,2}, HistoryCapacity={2,64}, HistoryWindow={0.05,1},
 VelocitySmoothing={0.001,1}, AccelerationSmoothing={0.01,2}, MaxObservedSpeed={1,1000}, MaxAcceleration={0,2000},
 TeleportSlack={0,100}, ReversalDotThreshold={-1,1}, MaxAccelerationHorizon={0,0.6},
}
Config.limits = Config.numericLimits
Config.controls = {
 {key="Enabled",label="Enable",kind="toggle",tab="MAIN"},
 {key="HitPart",label="Hit Part",kind="choice",options=Config.HitParts,tab="MAIN"},
 {key="PredictionX",label="Prediction X",kind="number",decimals=2,tab="MAIN"},
 {key="PredictionY",label="Prediction Y",kind="number",decimals=2,tab="MAIN"},
 {key="Smoothness",label="Smoothness",kind="number",decimals=3,tab="MAIN"},
 {key="Radius",label="Radius",kind="number",decimals=0,tab="MAIN"},
 {key="Fly",label="Fly",kind="toggle",tab="MISC",section="MOVEMENT"},
 {key="FlyKeybind",label="Fly Keybind",kind="keybind",tab="MISC",section="MOVEMENT"},
 {key="FlySpeed",label="Fly Speed",kind="number",decimals=0,tab="MISC",section="MOVEMENT"},
 {key="Speed",label="Speed",kind="toggle",tab="MISC",section="MOVEMENT"},
 {key="SpeedKeybind",label="Speed Keybind",kind="keybind",tab="MISC",section="MOVEMENT"},
 {key="WalkSpeed",label="Walk Speed",kind="number",decimals=0,tab="MISC",section="MOVEMENT"},
 {key="ESP",label="ESP",kind="toggle",tab="MISC",section="ESP"},
 {key="Hitboxes",label="Hitboxes",kind="toggle",tab="MISC",section="ESP"},
 {key="Names",label="Names",kind="toggle",tab="MISC",section="ESP"},
 {key="ESPTargetMode",label="Target Mode",kind="choice",options={"All","Specific Player"},tab="MISC",section="ESP"},
 {key="ESPUsername",label="Player Username",kind="text",tab="MISC",section="ESP"},
}
Config.keyFields={LockKey=true,FlyKeybind=true,SpeedKeybind=true,FlyUpKey=true,FlyDownKey=true}

Config.fields = {}
for _,field in Config.controls do
 local bounds=Config.numericLimits[field.key]
 if bounds then field.min=bounds[1];field.max=bounds[2] end
 Config.fields[field.key]=field
end

function Config.defaults()
 return {
  Enabled=false, HitPart="UpperTorso",
  PredictionX=13.15, PredictionY=13.15, Smoothness=0.405, Radius=180,
  LogoAssetId="rbxassetid://COLOCAR_ID_REAL", DebugMode=false, NotificationCooldown=3,
  Fly=false, FlyKeybind="V", FlySpeed=65, Speed=false, SpeedKeybind="G", WalkSpeed=24,
  FlyUpKey="Space", FlyDownKey="LeftControl", FlySmoothing=0.10, FlyMaxForce=100000,
  MovementAuthorized=false, MovementMode="Auto", LocalMovementAllowed=false,
 ESPAuthorized=false, ESPUnlimitedRange=false, ESPFarDistance=350, ESPFarUpdateHz=3,
 VerticalControl=true, RisingHorizon=0.055, FallingHorizon=0.045, ApexHorizon=0.025,
 MaxVerticalLead=2.25, MaxVerticalSpeed=85, MaxVerticalVelocityChange=450, ApexVelocity=3,
 LandingHoldSeconds=0.10, ReversalDamping=true, ReversalWindow=0.08, ReversalScale=0.5,
 AngularSafety=true, PitchMaxSpeed=180, PitchMaxAcceleration=1200, CloseSafetyDistance=8,
 MovementProbeSeconds=0.8, MovementMinimumSpeed=1,
 ReferenceScale=13.15, ReferenceHorizontalSeconds=0.1205, ReferenceVerticalSeconds=0.0800,
 MinScale=0, MaxScale=100, TrackingMode="Fixed", AdaptiveMinTau=0.008, AdaptiveMaxTau=0.06,
 AdaptiveErrorDegrees=8, AdaptiveGainSmoothing=0.08, CriticalFrequency=18,
 AngularMaxSpeed=720, AngularMaxAcceleration=4000, SmartSelection=false,
 TargetPartGraceSeconds=0.15, ReacquireOnLoss=false, TargetGraceSeconds=0.2, ReleaseRadiusMultiplier=1.3, TargetVisibilityHz=10,
 MotionFilter="Memory", FilterMinCutoff=1, FilterBeta=0.05, AlphaBetaAlpha=0.85, AlphaBetaBeta=0.05,
  ESP=false, Hitboxes=false, Names=false, ESPTargetMode="All", ESPUsername="",
  ESPUpdateHz=10, ESPMaxDistance=350, ESPOcclusionMode="VisibleOnly", ESPLowPerformanceMode=true,
  ShowFOV=false,
  LockKey="C", AutoPrediction=false, PingCompensation=true, PingSmoothing=0.8,
  PingReferences={{PingMs=55,X=0.113,Y=0.075},{PingMs=62,X=0.120,Y=0.080},{PingMs=70,X=0.128,Y=0.085}},
  MinPredictionX=0, MaxPredictionX=0.35, MinPredictionY=0, MaxPredictionY=0.35, PredictionSlew=0.06,
  MemoryTracking=true, VelocityPrediction=true, DistancePrediction=true, AccelerationPrediction=false,
  CameraDebugMode=false, CameraDebugInterval=0.5,
  PredictionSmoothing=0, VisibilityCheck=true, FallbackR6=true, RespectScriptableCamera=true,
  MaxDistance=350, AcquisitionInterval=0.25,
  CloseDistance=40, MediumDistance=120, CloseOffset=0, MediumOffset=0, LongOffset=0,
  ShowNotifications=true, WelcomeNotification=true, WelcomeDuration=3, NotificationDuration=2,
  InitializationTimeout=8, InitializationPollInterval=0.05, UpdateHz=30, PingHz=5, StaleAfter=0.6,
  HistoryCapacity=12, HistoryWindow=0.3, VelocitySmoothing=0.06, AccelerationSmoothing=0.15,
  MaxObservedSpeed=120, MaxAcceleration=180, TeleportSlack=5, ReversalDotThreshold=-0.2,
  MaxAccelerationHorizon=0.18,
 }
end

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function plain(value) return type(value)=="table" and getmetatable(value)==nil end
local function shape(overrides)
 if not plain(overrides) then return false,"Config debe ser una tabla simple" end
 local defaults=Config.defaults()
 for key,value in overrides do
  local expected=defaults[key]
  if type(key)~="string" or expected==nil then return false,"Config: campo desconocido "..tostring(key) end
  if Config.keyFields[key] then
   local resolved,message=PinkConfig.normalizeLockKey(value)
   if not resolved then return false,message end
  elseif key=="PingReferences" then
   if not plain(value) then return false,"PingReferences debe ser una tabla simple" end
   local count=0
   for index,point in value do
    if type(index)~="number" or index%1~=0 or index<1 or index>32 or not plain(point) then
     return false,"PingReferences: índice o punto inválido"
    end
    count+=1
    for name,number in point do
     if (name~="PingMs" and name~="X" and name~="Y") or not finite(number) then
      return false,"PingReferences: campo inválido"
     end
    end
    if not finite(point.PingMs) or not finite(point.X) or not finite(point.Y) then
     return false,"PingReferences: falta PingMs, X o Y"
    end
   end
   if count==0 then return false,"PingReferences debe ser una lista continua" end
   for index=1,count do if value[index]==nil then return false,"PingReferences debe ser una lista continua" end end
  elseif type(value)~=type(expected) or (type(expected)=="number" and not finite(value)) then
   return false,"Config."..key..": tipo inválido o número no finito"
  end
 end
 return true
end

local sharedFields={
 "Enabled","LockKey","AutoPrediction","PingCompensation","PingSmoothing","MinPredictionX","MaxPredictionX",
 "MinPredictionY","MaxPredictionY","PredictionSlew","MemoryTracking","VelocityPrediction","DistancePrediction",
 "AccelerationPrediction","PredictionSmoothing","VisibilityCheck","MaxDistance","CloseDistance","MediumDistance",
 "ShowNotifications","WelcomeNotification","WelcomeDuration","NotificationDuration","InitializationTimeout",
 "InitializationPollInterval","UpdateHz","PingHz","StaleAfter","HistoryCapacity","HistoryWindow","VelocitySmoothing",
 "AccelerationSmoothing","MaxObservedSpeed","MaxAcceleration","TeleportSlack","ReversalDotThreshold","MaxAccelerationHorizon",
}

-- A validated native PINK prediction configuration, with no invented weapon
-- speed/gravity. Only existing motion, range and RTT calibration are reused.
function Config.toPredictionConfig(config)
 local legacy=PinkConfig.defaults()
 for _,key in sharedFields do legacy[key]=config[key] end
 legacy.TargetPart=config.HitPart
 legacy.WeaponProfile="Default"
 legacy.PredictionX=math.clamp(config.PredictionX*config.ReferenceHorizontalSeconds/config.ReferenceScale,config.MinPredictionX,config.MaxPredictionX)
 legacy.PredictionY=math.clamp(config.PredictionY*config.ReferenceVerticalSeconds/config.ReferenceScale,config.MinPredictionY,config.MaxPredictionY)
 legacy.PingReferences={}
 for _,point in config.PingReferences do table.insert(legacy.PingReferences,table.clone(point)) end
 for _,range in {"Close","Medium","Long"} do legacy[range.."Offset"]=config[range.."Offset"] end
 return PinkConfig.new(legacy)
end

function Config.new(overrides)
 if overrides==nil then overrides={} end
 local ok,message=shape(overrides)
 if not ok then return nil,message end
 local config=Config.defaults()
 for key,value in overrides do
  if key=="PingReferences" then
   config[key]={}
   for _,point in value do table.insert(config[key],table.clone(point)) end
  else config[key]=value end
 end
 for key,bounds in Config.numericLimits do
  if config[key]<bounds[1] or config[key]>bounds[2] then return nil,key.." fuera de rango" end
 end
 if config.MinScale>config.MaxScale or config.PredictionX<config.MinScale or config.PredictionX>config.MaxScale
  or config.PredictionY<config.MinScale or config.PredictionY>config.MaxScale then return nil,"Prediction scale fuera de límites configurados" end
 if config.AdaptiveMinTau>config.AdaptiveMaxTau then return nil,"Adaptive tau limits invertidos" end
 if not table.find({"Fixed","Adaptive","Critical"},config.TrackingMode) then return nil,"TrackingMode inválido" end
 if not table.find({"Memory","AlphaBeta","OneEuro"},config.MotionFilter) then return nil,"MotionFilter inválido" end
 if config.HistoryCapacity%1~=0 then return nil,"HistoryCapacity debe ser entero" end
 if not table.find(Config.HitParts,config.HitPart) then return nil,"HitPart desconocido" end
 if config.MinPredictionX>config.MaxPredictionX or config.MinPredictionY>config.MaxPredictionY then
  return nil,"Límites de predicción invertidos"
 end
 if config.CloseDistance>=config.MediumDistance then return nil,"Rangos de distancia invertidos" end
 -- Validate the empirical ping curve.
 local previous=-math.huge
 for _,point in config.PingReferences do
  if point.PingMs<0 or point.PingMs>2000 or point.PingMs<=previous
   or point.X<0 or point.X>0.6 or point.Y<0 or point.Y>0.6 then
   return nil,"PingReferences desordenado o fuera de límites"
  end
  previous=point.PingMs
 end
 if config.ESPTargetMode~="All" and config.ESPTargetMode~="Specific Player" then return nil,"ESP Target Mode inválido" end
 if not table.find({"Auto","Local","Server"},config.MovementMode) then return nil,"MovementMode inválido" end
 if not table.find({"VisibleOnly","AlwaysOnTop"},config.ESPOcclusionMode) then return nil,"ESPOcclusionMode inválido" end
 if #config.ESPUsername>20 or (config.ESPUsername~="" and not config.ESPUsername:match("^[%w_]+$")) then return nil,"Username inválido" end
 if config.LogoAssetId~="rbxassetid://COLOCAR_ID_REAL" and config.LogoAssetId~=""
  and not config.LogoAssetId:match("^rbxassetid://[1-9]%d*$") then return nil,"LogoAssetId requiere un ID real rbxassetid://" end
 for key in Config.keyFields do
  config[key],message=PinkConfig.normalizeLockKey(config[key])
  if not config[key] then return nil,key..": "..tostring(message) end
  local name=PinkConfig.keyName(config[key])
  if name:match("^Button") or name:match("^Thumbstick") or name:match("^DPad") then return nil,"Keybind requiere tecla de teclado" end
 end
 local used={}
 for _,key in {"LockKey","FlyKeybind","SpeedKeybind","FlyUpKey","FlyDownKey"} do
  local name=PinkConfig.keyName(config[key])
  if used[name] then return nil,"Keybind duplicado: "..name end
  used[name]=key
 end
 for _,key in {"LockKey","FlyKeybind","SpeedKeybind"} do
  local name=PinkConfig.keyName(config[key])
  if table.find({"W","A","S","D","Escape","Return","Tab","Backspace"},name) then return nil,"Tecla reservada: "..name end
 end
 for _,key in {"FlyUpKey","FlyDownKey"} do
  if table.find({"W","A","S","D","Escape","Return","Tab","Backspace"},PinkConfig.keyName(config[key])) then return nil,"Tecla de vuelo reservada" end
 end
 local legacy
 legacy,message=Config.toPredictionConfig(config)
 if not legacy then return nil,message end
 return config
end

function Config.validate(config)
 local normalized,message=Config.new(config)
 if not normalized then return false,message end
 local defaults=Config.defaults()
 for key in defaults do if config[key]==nil then return false,"Falta Config."..key end end
 return true
end
function Config.update(config,key,value)
 if type(key)~="string" or Config.defaults()[key]==nil then return nil,"Campo desconocido: "..tostring(key) end
 local nextConfig,message=Config.new(config)
 if not nextConfig then return nil,message end
 nextConfig[key]=value
 return Config.new(nextConfig)
end
function Config.updateField(config,key,value)
 local normalized,message=Config.update(config,key,value)
 if not normalized then return false,message end
 for name,child in normalized do config[name]=child end
 return true
end
Config.normalizeLockKey=PinkConfig.normalizeLockKey
Config.keyName=PinkConfig.keyName
return Config
