--!nonstrict
-- PINK DOT LOCK | edit Config here. X/Y and all offsets are seconds.
-- The dot shows the observed part, never the predicted aim point.
-- Camera stays free. Public client APIs only; no weapon integration for Da Hood.
local Config = {
 Enabled=true, LockKey=(Enum and Enum.KeyCode.C or "C"), LockMode="Auto",
 FirstPersonFOV=120, ThirdPersonFOV=180,
 PredictionX=0.1205, PredictionY=0.0800, AutoPrediction=false,
 PingCompensation=true, PingSmoothing=0.8,
 PingReferences={{PingMs=55,X=0.113,Y=0.075},{PingMs=62,X=0.120,Y=0.080},{PingMs=70,X=0.128,Y=0.085}},
 MinPredictionX=0, MaxPredictionX=0.35, MinPredictionY=0, MaxPredictionY=0.35, PredictionSlew=0.06,
 MemoryTracking=true, VelocityPrediction=true, DistancePrediction=true, AccelerationPrediction=false,
 PredictionSmoothing=0.08, TargetPart="HumanoidRootPart", TargetPersistence=true, VisibilityCheck=true,
 ShowDot=true, DotSize=6, DotColor=(Color3 and Color3.fromRGB(255,105,180) or {R=255/255,G=105/255,B=180/255}), DotTransparency=0,
 DotOutline=true, DotOutlineColor=(Color3 and Color3.fromRGB(255,255,255) or {R=255/255,G=255/255,B=255/255}),
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
-- Generated from src/pink and existing shared algorithms. No remote dependencies.
local factories, cache, loading = {}, {}, {}
local function loadModule(name)
 if cache[name] then return cache[name] end
 assert(factories[name], "Unknown embedded module: " .. tostring(name))
 assert(not loading[name], "Circular embedded dependency: " .. name)
 loading[name] = true
 local ok, value = pcall(factories[name], loadModule)
 loading[name] = nil
 if not ok then error("Module " .. name .. ": " .. tostring(value), 2) end
 assert(type(value)=="table", "Embedded module must return a table: " .. name)
 cache[name] = value
 return value
end
-- BEGIN Settings | sha256 690e426507b50eb0549ccf3372308831f26149f82e6b3bcb4ec6ba0b9b3a6bb5
factories["Settings"] = function(loadModule)
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
end
-- END Settings
-- BEGIN Latency | sha256 6a0d5690b75f2adea9ce41b46a7b4e52a209aa011c9505621014fcf5288b1e8b
factories["Latency"] = function(loadModule)
--!nonstrict
-- Time-based EMA: smoothing is independent of event/frame frequency.
local Latency = {}
Latency.__index = Latency
local function finite(n)
 return type(n)=="number" and n==n and math.abs(n)<math.huge
end
function Latency.new(settings)
 return setmetatable({settings=settings,raw=0,smoothed=0,lastTime=nil,lastDelayTime=nil,delay=nil},Latency)
end
function Latency:sample(oneWaySeconds, now)
 if not finite(oneWaySeconds) or oneWaySeconds<0 or oneWaySeconds>1 or not finite(now) then return false end
 if self.lastTime and now<=self.lastTime then return false end
 self.raw=oneWaySeconds
 if not self.lastTime then self.smoothed=oneWaySeconds
 else
  local alpha=1-math.exp(-(now-self.lastTime)/self.settings.pingSmoothingSeconds)
  self.smoothed += alpha*(oneWaySeconds-self.smoothed)
 end
 self.lastTime=now
 return true
end
function Latency:calibrationOffset(ping)
 local points=self.settings.pingCalibration
 if ping<=points[1].pingSeconds then return points[1].offsetSeconds end
 for i=2,#points do
  local a,b=points[i-1],points[i]
  if ping<=b.pingSeconds then
   local f=(ping-a.pingSeconds)/(b.pingSeconds-a.pingSeconds)
   return a.offsetSeconds+(b.offsetSeconds-a.offsetSeconds)*f
  end
 end
 return points[#points].offsetSeconds
end
function Latency:estimate(now, weaponOffset)
 local s=self.settings
 local desired=if s.autoPrediction then self.smoothed+self:calibrationOffset(self.smoothed) else s.manualDelaySeconds
 desired=math.clamp(desired+s.latencyOffsetSeconds+(weaponOffset or 0),s.minDelaySeconds,s.maxDelaySeconds)
 if self.delay==nil then self.delay=desired
 else
  local dt=math.max(0,now-(self.lastDelayTime or now))
  local step=s.latencySlewSecondsPerSecond*dt
  self.delay += math.clamp(desired-self.delay,-step,step)
  self.delay=math.clamp(self.delay,s.minDelaySeconds,s.maxDelaySeconds)
 end
 self.lastDelayTime=now
 return self.delay
end
return Latency
end
-- END Latency
-- BEGIN MotionHistory | sha256 e2d7d2c3eef688354efd53c01fdbeb2dd15ed4fe14d8d90a4e578bceee5941b8
factories["MotionHistory"] = function(loadModule)
--!nonstrict
-- Bounded per-target memory. A timestamp must refer to the observation itself,
-- never to the time a delayed packet was received.
local MotionHistory={}
MotionHistory.__index=MotionHistory
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vectorOK(v)
 if typeof(v)~="Vector3" and type(v)~="table" then return false end
 return finite(v.X) and finite(v.Y) and finite(v.Z) and finite(v.Magnitude)
end
local function limit(v,cap)
 local mag=v.Magnitude
 return if mag>cap and mag>0 then v*(cap/mag) else v
end
function MotionHistory.new(settings)
 return setmetatable({settings=settings,samples={},velocity=nil,acceleration=nil,resets=0,rejected=0},MotionHistory)
end
function MotionHistory:reset(sample,velocity)
 self.samples={sample}
 self.velocity=velocity
 self.acceleration=sample.position*0
 self.resets+=1
end
function MotionHistory:observe(sample)
 local s=self.settings
 if type(sample)~="table" or not finite(sample.t) or not vectorOK(sample.position)
  or (sample.velocity~=nil and not vectorOK(sample.velocity)) or type(sample.state)~="string" then
  self.rejected+=1; return false
 end
 local last=self.samples[#self.samples]
 if last and sample.t<=last.t then self.rejected+=1;return false end
 local zero=sample.position*0
 local reported=sample.velocity
 if reported and reported.Magnitude>s.maxObservedSpeedStuds then self.rejected+=1;return false end
 if not last then self:reset(sample,reported or zero);return true end
 local dt=sample.t-last.t
 local displacement=sample.position-last.position
 if dt>s.staleAfterSeconds or displacement.Magnitude>s.maxObservedSpeedStuds*dt+s.teleportSlackStuds then
  -- Teleport/respawn: rebase rather than extrapolating across a discontinuity.
  self:reset(sample,reported or zero);return true
 end
 local measured=displacement/dt
 if measured.Magnitude>s.maxObservedSpeedStuds then self.rejected+=1;return false end
 local instantaneous=reported or measured
 local oldVelocity=self.velocity or zero
 local reversal=oldVelocity.Magnitude>1 and instantaneous.Magnitude>1
  and oldVelocity:Dot(instantaneous)/(oldVelocity.Magnitude*instantaneous.Magnitude)<s.reversalDotThreshold
 -- A lateral turn while jumping can be hidden by the shared vertical velocity.
 local oldHorizontal=math.sqrt(oldVelocity.X*oldVelocity.X+oldVelocity.Z*oldVelocity.Z)
 local newHorizontal=math.sqrt(instantaneous.X*instantaneous.X+instantaneous.Z*instantaneous.Z)
 if oldHorizontal>1 and newHorizontal>1
  and (oldVelocity.X*instantaneous.X+oldVelocity.Z*instantaneous.Z)/(oldHorizontal*newHorizontal)<s.reversalDotThreshold then
  reversal=true
 end
 if sample.state~=last.state or reversal or not s.memoryTracking then
  self:reset(sample,instantaneous);return true
 end
 table.insert(self.samples,sample)
 while #self.samples>s.historyCapacity or (#self.samples>2 and sample.t-self.samples[1].t>s.historyWindowSeconds) do
  table.remove(self.samples,1)
 end
 -- Weighted recent displacement estimate, blended with instantaneous velocity.
 -- Native velocity can be omitted; then the same filter runs on position deltas.
 local oldest=self.samples[1]
 local span=sample.t-oldest.t
 local recent=if span>0 then (sample.position-oldest.position)/span else instantaneous
 local input=instantaneous*0.75+recent*0.25
 local alpha=1-math.exp(-dt/s.velocitySmoothingSeconds)
 self.velocity=limit(oldVelocity+(input-oldVelocity)*alpha,s.maxObservedSpeedStuds)
 local acceleration=limit((self.velocity-oldVelocity)/dt,s.maxAccelerationStuds)
 local beta=1-math.exp(-dt/s.accelerationSmoothingSeconds)
 self.acceleration=limit((self.acceleration or zero)+(acceleration-(self.acceleration or zero))*beta,s.maxAccelerationStuds)
 return true
end
function MotionHistory:latest()
 return self.samples[#self.samples]
end
return MotionHistory
end
-- END MotionHistory
-- BEGIN Ballistics | sha256 a9b8797e468d5203faf6632ec47196fc9dad86bc97f0a9bec1d5992757261a6b
factories["Ballistics"] = function(loadModule)
--!nonstrict
-- Straight-flight interception, plus optional gravity displacement correction.
-- With gravity we refine the low-arc travel time numerically and verify that
-- |aim-origin| = speed*time; unreachable solutions return nil rather than a lie.
local Ballistics={}
function Ballistics.intercept(origin,position,velocity,speed,maxTime)
 if type(speed)~="number" or speed<=0 or speed~=speed or speed==math.huge then return nil end
 local r=position-origin
 local a=velocity:Dot(velocity)-speed*speed
 local b=2*r:Dot(velocity)
 local c=r:Dot(r)
 if c<1e-8 then return 0 end
 local t=nil
 if math.abs(a)<1e-8 then
  if math.abs(b)>1e-8 then local x=-c/b;if x>=0 then t=x end end
 else
  local discriminant=b*b-4*a*c
  if discriminant>=0 then
   -- Stable quadratic roots avoid cancellation when b is large.
   local q=-0.5*(b+(if b>=0 then 1 else -1)*math.sqrt(discriminant))
   local x1=q/a
   local x2=if math.abs(q)>1e-12 then c/q else -b/(2*a)
   if x1>=0 then t=x1 end
   if x2>=0 and (not t or x2<t) then t=x2 end
  end
 end
 if t and t<=maxTime then return t end
 return nil
end
function Ballistics.solve(origin,basePosition,velocity,acceleration,profile,maxTime,leadMoving,accelHorizon)
 local zero=basePosition*0
 if profile.kind~="projectile" then return {flightSeconds=0,position=basePosition,aimpoint=basePosition} end
 local v=if leadMoving then velocity else zero
 local a=if leadMoving then acceleration else zero
 local t=Ballistics.intercept(origin,basePosition,v,profile.speed,maxTime)
 if not t then return nil end
 local gravity=profile.gravity or 0
 local up=zero -- Works both with Roblox Vector3 and a test vector adapter.
 -- Construct upward displacement by components without depending on Vector3.new.
 -- Supplied by Predictor as an optional unit vector for CLI portability.
 up=profile.upVector or zero
 local function at(time)
  local used=math.min(time,accelHorizon or time)
  local p=basePosition+v*time+a*(used*time-0.5*used*used)
  return p,p+up*(0.5*gravity*time*time)
 end
 for _=1,16 do
  local _,aim=at(t)
  local nextT=(aim-origin).Magnitude/profile.speed
  if nextT>maxTime or nextT~=nextT then return nil end
  if math.abs(nextT-t)<0.00001 then t=nextT;break end
  t=nextT
 end
 local p,aim=at(t)
 if math.abs((aim-origin).Magnitude-profile.speed*t)>0.05 then return nil end
 return {flightSeconds=t,position=p,aimpoint=aim}
end
return Ballistics
end
-- END Ballistics
-- BEGIN Config | sha256 633f476f01181c7bda115304534382c7468f974cccdb7f580872dac8ca5123c2
factories["Config"] = function(loadModule)
--!nonstrict
-- PINK DOT LOCK configuration. Prediction X/Y and offsets are seconds;
-- reference pings are RTT milliseconds, spatial values use Roblox studs.
local Settings = loadModule("Settings")
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
end
-- END Config
-- BEGIN ModeDetector | sha256 4b515fe1f8d371b57f807e7f49b5d4bbbf246fd5383181146c3605d645f9b4cb
factories["ModeDetector"] = function(loadModule)
--!nonstrict
-- Pure camera-mode classification. No camera writes, Roblox services or targets.
-- Auto requires corroborated camera-to-head AND camera-to-focus distances;
-- proximity to the head alone is insufficient (e.g. a third-person obstruction).
local ModeDetector = {}
ModeDetector.__index = ModeDetector

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function distance(value)
	return finite(value) and value >= 0
end

local function resetPending(self)
	self.pendingMode = nil
	self.pendingSince = nil
end

function ModeDetector.new(config)
	return setmetatable({
		config = config or {},
		mode = "ThirdPerson",
		pendingMode = nil,
		pendingSince = nil,
		lastTime = nil,
	}, ModeDetector)
end

function ModeDetector:update(now, observation)
	-- Bad/out-of-order time cannot satisfy a dwell interval.
	if not finite(now) or (self.lastTime ~= nil and now < self.lastTime) then
		resetPending(self)
		return self.mode
	end
	self.lastTime = now
	local config = self.config
	local override = config.LockMode
	if override == "FirstPerson" or override == "ThirdPerson" then
		self.mode = override
		resetPending(self)
		return self.mode
	end
	if type(observation) ~= "table" then
		resetPending(self)
		return self.mode
	end
	-- The runtime obtains this explicit setting from Player.CameraMode.
	-- It is strong evidence and does not need the heuristic's dwell interval.
	if observation.forcedFirstPerson == true then
		self.mode = "FirstPerson"
		resetPending(self)
		return self.mode
	end

	local enter = config.ModeEnterDistance
	local exit = config.ModeExitDistance
	local dwell = config.ModeDwellSeconds
	if not distance(enter) then enter = 0.75 end
	if not distance(exit) or exit <= enter then exit = math.max(1.5, enter + 0.75) end
	if not distance(dwell) then dwell = 0.2 end

	local desired = nil
	if observation.subjectIsLocal == false then
		-- A confirmed different subject is not local first-person evidence.
		desired = "ThirdPerson"
	elseif observation.subjectIsLocal == true
		and distance(observation.headDistance) and distance(observation.focusDistance) then
		if observation.headDistance <= enter and observation.focusDistance <= enter then
			desired = "FirstPerson"
		elseif observation.headDistance >= exit and observation.focusDistance >= exit then
			desired = "ThirdPerson"
		end
	end

	-- Missing data and the hysteresis band preserve the established mode, but
	-- invalidate pending evidence so separated near samples cannot accumulate.
	if desired == nil or desired == self.mode then
		resetPending(self)
		return self.mode
	end
	if self.pendingMode ~= desired then
		self.pendingMode = desired
		self.pendingSince = now
	end
	if now - self.pendingSince >= dwell then
		self.mode = desired
		resetPending(self)
	end
	return self.mode
end

return ModeDetector
end
-- END ModeDetector
-- BEGIN Selection | sha256 6eba2e0a7820977b4839c9ec9b24a83b60aa7fc387931309ef4df2b20d0498cf
factories["Selection"] = function(loadModule)
--!nonstrict
-- Pure screen-space acquisition. Persistence and character lifetime belong
-- to Session; being offscreen later must never invalidate an existing lock.
local Selection = {}

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function components(value)
	local kind = typeof(value)
	if type(value) ~= "table" and kind ~= "Vector2" and kind ~= "Vector3" then
		return nil
	end
	if not finite(value.X) or not finite(value.Y) then
		return nil
	end
	return value.X, value.Y
end

function Selection.reference(mode, viewportSize, mousePosition, inset)
	local width, height = components(viewportSize)
	if width == nil or width <= 0 or height <= 0 then
		return nil
	end
	if mode == "FirstPerson" then
		-- WorldToViewportPoint coordinates omit the GUI inset. Do not add it to
		-- the first-person reference; the viewport center is already correct.
		return { X = width / 2, Y = height / 2 }
	end
	if mode ~= "ThirdPerson" then
		return nil
	end
	local mouseX, mouseY = components(mousePosition)
	if mouseX == nil then
		return nil
	end
	local insetX, insetY = 0, 0
	if inset ~= nil then
		insetX, insetY = components(inset)
		if insetX == nil then
			return nil
		end
	end
	-- UserInputService.GetMouseLocation includes the GUI inset, while projected
	-- candidates use WorldToViewportPoint. Convert exactly once.
	local x, y = mouseX - insetX, mouseY - insetY
	if not finite(x) or not finite(y) then
		return nil
	end
	return { X = x, Y = y }
end

function Selection.isSelectable(candidate)
	if type(candidate) ~= "table" or candidate.valid ~= true
		or candidate.visible ~= true or candidate.onScreen ~= true
		or not finite(candidate.distanceStuds) or candidate.distanceStuds < 0 then
		return false
	end
	local point = candidate.screenPosition
	local x = components(point)
	if x == nil then
		return false
	end
	-- Vector2 has no Z member. Vector3 projection or a plain table may include
	-- depth; when supplied, positive finite depth is mandatory.
	local kind = typeof(point)
	if kind == "Vector3" or type(point) == "table" then
		local depth = point.Z
		if depth ~= nil and (not finite(depth) or depth <= 0) then
			return false
		end
	end
	return true
end

local function squaredDistance(candidate, reference)
	local referenceX, referenceY = components(reference)
	if referenceX == nil or not Selection.isSelectable(candidate) then
		return nil
	end
	local x, y = components(candidate.screenPosition)
	local dx, dy = x - referenceX, y - referenceY
	local value = dx * dx + dy * dy
	return finite(value) and value or nil
end

function Selection.within(candidate, reference, fov)
	if not finite(fov) or fov < 0 then
		return false
	end
	local squared = squaredDistance(candidate, reference)
	return squared ~= nil and squared <= fov * fov
end

function Selection.nearest(candidates, reference, fov)
	if type(candidates) ~= "table" or not finite(fov) or fov < 0
		or components(reference) == nil then
		return nil
	end
	local winner = nil
	local closestSquared = fov * fov
	for _, candidate in ipairs(candidates) do
		local squared = squaredDistance(candidate, reference)
		if squared ~= nil and squared <= closestSquared then
			-- Keep input ordering for exact ties instead of oscillating based on
			-- unrelated world distance or unstable player enumeration.
			if winner == nil or squared < closestSquared then
				winner = candidate
				closestSquared = squared
			end
		end
	end
	return winner
end

return Selection
end
-- END Selection
-- BEGIN Prediction | sha256 2e3d17af6457258489c42f77cd1dfed51c2e437292da729032a844b1816fe7dd
factories["Prediction"] = function(loadModule)
--!nonstrict
-- X/Z use PredictionX seconds; Y uses PredictionY seconds. These configurable
-- references are empirical horizons, not universal properties of a weapon.
-- Auto references already contain the requested delay: RTT is NEVER added
-- again. Only the independently known observation age is integrated once.
local Config = loadModule("Config")
local MotionHistory = loadModule("MotionHistory")
local Latency = loadModule("Latency")
local Ballistics = loadModule("Ballistics")
local Prediction = {}
Prediction.__index = Prediction

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vectorOK(v)
 local ok,result=pcall(function()
  return v~=nil and finite(v.X) and finite(v.Y) and finite(v.Z) and finite(v.Magnitude)
 end)
 return ok and result
end
local function makeVector(reference,x,y,z)
 if Vector3 and type(Vector3.new)=="function" then return Vector3.new(x,y,z) end
 -- The repository's CLI Vector adapter exposes its constructor on instances.
 if type(reference)=="table" and type(reference.new)=="function" then return reference.new(x,y,z) end
 return nil
end
local function policyState()
 return {baseX=nil,baseY=nil,lastBaseTime=nil,position=nil,targetPosition=nil,lastPositionTime=nil}
end
function Prediction.new(config)
 local normalized,message=Config.new(config)
 assert(normalized,message or "Configuración de predicción inválida")
 local settings=Config.toSettings(normalized)
 return setmetatable({config=normalized,settings=settings,history=MotionHistory.new(settings),
  latency=Latency.new(settings),pingAvailable=false,policies={active=policyState(),manual=policyState(),auto=policyState()}},Prediction)
end
function Prediction:_sync()
 Config.toSettings(self.config,self.settings)
end
function Prediction:reset()
 self:_sync()
 self.history=MotionHistory.new(self.settings);self.latency=Latency.new(self.settings)
 self.pingAvailable=false
 self.policies={active=policyState(),manual=policyState(),auto=policyState()}
end
function Prediction:observe(t,position,state)
 self:_sync()
 local previous=self.history:latest()
 local accepted=self.history:observe({t=t,position=position,state=if state==nil then "Running" else state})
 if accepted and previous then
  local dt=t-previous.t
  if dt>self.config.StaleAfter or (position-previous.position).Magnitude>self.config.MaxObservedSpeed*dt+self.config.TeleportSlack then
   -- A teleport/gap rebases the output filter as well as the motion estimator.
   -- Ordinary velocity-mode updates still retain time-based output smoothing.
   for _,policy in self.policies do policy.position=nil;policy.targetPosition=nil;policy.lastPositionTime=nil end
  end
 end
 return accepted
end
function Prediction:samplePing(rttSeconds,now)
 if not finite(now) then return false end
 self:_sync()
 if rttSeconds==nil then
  self.latency=Latency.new(self.settings);self.pingAvailable=false
  for _,state in self.policies do state.baseX=nil;state.baseY=nil;state.lastBaseTime=nil end
  return true
 end
 if not finite(rttSeconds) or rttSeconds<0 or rttSeconds>2 then return false end
 local accepted=self.latency:sample(rttSeconds/2,now)
 if accepted then self.pingAvailable=true end
 return accepted
end
local function interpolate(points,pingMs)
 if pingMs<=points[1].PingMs then return points[1].X,points[1].Y end
 for i=2,#points do
  local a,b=points[i-1],points[i]
  if pingMs<=b.PingMs then
   local f=(pingMs-a.PingMs)/(b.PingMs-a.PingMs)
   return a.X+(b.X-a.X)*f,a.Y+(b.Y-a.Y)*f
  end
 end
 local last=points[#points]
 return last.X,last.Y
end
function Prediction:_bases(policy,now,state)
 local c=self.config
 if policy=="Manual" then return c.PredictionX,c.PredictionY,"Manual" end
 if not c.PingCompensation or not self.pingAvailable then
  return c.PredictionX,c.PredictionY,"AutoFallback"
 end
 local x,y=interpolate(c.PingReferences,self.latency.smoothed*2000)
 x=math.clamp(x,c.MinPredictionX,c.MaxPredictionX)
 y=math.clamp(y,c.MinPredictionY,c.MaxPredictionY)
 if state.baseX~=nil then
  local step=c.PredictionSlew*math.max(0,now-(state.lastBaseTime or now))
  x=state.baseX+math.clamp(x-state.baseX,-step,step)
  y=state.baseY+math.clamp(y-state.baseY,-step,step)
 end
 state.baseX=x;state.baseY=y;state.lastBaseTime=now
 return x,y,"Auto"
end
function Prediction:_predict(origin,now,policy,key)
 local c=self.config
 if not c.Enabled or not finite(now) or not vectorOK(origin) then return nil end
 self:_sync()
 local sample=self.history:latest()
 if not sample then return nil end
 local age=now-sample.t
 if age< -0.05 or age>c.StaleAfter then return nil end
 age=math.max(0,age)
 local distance=(sample.position-origin).Magnitude
 if distance>c.MaxDistance then return nil end
 local range=if distance<c.CloseDistance then "Close" elseif distance<c.MediumDistance then "Medium" else "Long"
 local state=self.policies[key]
 -- Equivalent fractional frame timestamps can differ by floating point noise.
 if (state.lastBaseTime and now<state.lastBaseTime-1e-7)
  or (state.lastPositionTime and now<state.lastPositionTime-1e-7) then return nil end
 now=math.max(now,state.lastBaseTime or now,state.lastPositionTime or now)
 local baseX,baseY,status=self:_bases(policy,now,state)
 local profile=c.Profiles[c.WeaponProfile]
 local distanceOffset=if c.DistancePrediction then c[range.."Offset"]+profile[range.."Offset"] else 0
 local x=math.clamp(baseX+profile.PredictionXOffset+profile.LatencyOffsetSeconds+distanceOffset,c.MinPredictionX,c.MaxPredictionX)
 local y=math.clamp(baseY+profile.PredictionYOffset+profile.LatencyOffsetSeconds+distanceOffset,c.MinPredictionY,c.MaxPredictionY)
 local zero=sample.position*0
 local velocity=if c.VelocityPrediction then self.history.velocity or zero else zero
 local acceleration=if c.VelocityPrediction and c.MemoryTracking and c.AccelerationPrediction then self.history.acceleration or zero else zero
 local hx,hy=x+age,y+age
 local ux,uy=math.min(hx,c.MaxAccelerationHorizon),math.min(hy,c.MaxAccelerationHorizon)
 local lead=makeVector(sample.position,
  velocity.X*hx+acceleration.X*(ux*hx-0.5*ux*ux),
  velocity.Y*hy+acceleration.Y*(uy*hy-0.5*uy*uy),
  velocity.Z*hx+acceleration.Z*(ux*hx-0.5*ux*ux))
 if not lead then return nil end
 local rawTarget=sample.position+lead
 local rawAim=rawTarget
 local flight=0
 local physicsStatus="Unknown"
 if profile.Kind=="Hitscan" then physicsStatus="ConfiguredHitscan" end
 if profile.Kind=="Projectile" and c.DistancePrediction then
  local currentVelocity=makeVector(sample.position,velocity.X+acceleration.X*ux,
   velocity.Y+acceleration.Y*uy,velocity.Z+acceleration.Z*ux)
  local up=makeVector(sample.position,0,1,0)
  local result=Ballistics.solve(origin,rawTarget,currentVelocity,zero,
   {kind="projectile",speed=profile.Speed,gravity=profile.Gravity,upVector=up},
   c.MaxFlightSeconds,c.VelocityPrediction,c.MaxAccelerationHorizon)
  if not result then return nil end
  rawTarget=result.position;rawAim=result.aimpoint;flight=result.flightSeconds
  physicsStatus="ConfiguredProjectile"
 elseif profile.Kind=="Projectile" then physicsStatus="DistanceDisabled" end

 -- The output and corresponding target reference share an EMA, independent
 -- for active/manual/auto policies. The visual DOT never uses this filter.
 local dt=if state.lastPositionTime then math.max(0,now-state.lastPositionTime) else 0
 local alpha=if c.PredictionSmoothing>0 then 1-math.exp(-dt/c.PredictionSmoothing) else 1
 if state.position==nil then
  state.position=rawAim;state.targetPosition=rawTarget
 else
  state.position=state.position+(rawAim-state.position)*alpha
  state.targetPosition=state.targetPosition+(rawTarget-state.targetPosition)*alpha
 end
 state.lastPositionTime=now
 return {position=state.position,rawPosition=rawAim,targetPosition=state.targetPosition,rawTargetPosition=rawTarget,
  currentPosition=sample.position,velocity=velocity,acceleration=acceleration,distanceStuds=distance,
  ageSeconds=age,predictionX=x,predictionY=y,baseX=baseX,baseY=baseY,
  rawPingMs=if self.pingAvailable then self.latency.raw*2000 else nil,
  smoothedPingMs=if self.pingAvailable then self.latency.smoothed*2000 else nil,
  status=status,flightSeconds=flight,physicsVerified=false,physicsStatus=physicsStatus,
  sampleTime=sample.t,createdAt=now,range=range,weaponProfile=c.WeaponProfile,policy=policy,
  state=sample.state}
end
function Prediction:predict(origin,now,policyOverride)
 if policyOverride~=nil and policyOverride~="Manual" and policyOverride~="Auto" then return nil end
 local policy=policyOverride or (if self.config.AutoPrediction then "Auto" else "Manual")
 local key=if policyOverride=="Manual" then "manual" elseif policyOverride=="Auto" then "auto" else "active"
 return self:_predict(origin,now,policy,key)
end
function Prediction:predictComparisons(origin,now)
 return {active=self:predict(origin,now),manual=self:predict(origin,now,"Manual"),auto=self:predict(origin,now,"Auto")}
end
return Prediction
end
-- END Prediction
-- BEGIN Overlay | sha256 8a5aea0b51469e96358086fa8d314ff60572997860da0a10493735aa913bfd8d
factories["Overlay"] = function(loadModule)
--!nonstrict
-- Display-only overlay: the dot receives an observed position, never a prediction.
-- All controls remain with Roblox; there are no buttons or input connections.
local Overlay = {}
Overlay.__index = Overlay
local FADE_SECONDS = 0.18

local function create(self, className, properties, parent)
	local object = Instance.new(className)
	-- Track before property assignment so construction failures leave no orphans.
	table.insert(self.owned, object)
	for key, value in pairs(properties) do object[key] = value end
	object.Parent = parent
	return object
end
local function finite(number)
	return type(number) == "number" and number == number and math.abs(number) < math.huge
end
local function xy(point)
	if point == nil then return nil end
	local ok, x, y = pcall(function() return point.X, point.Y end)
	if ok and finite(x) and finite(y) then return x, y end
	return nil
end

function Overlay.new(playerGui, config)
	local self = setmetatable({ config = config or {}, owned = {}, destroyed = false }, Overlay)
	local ok, problem = pcall(function()
		local settings = self.config
		local hotPink, white = Color3.fromRGB(255, 105, 180), Color3.fromRGB(255, 255, 255)
		self.gui = create(self, "ScreenGui", {
			Name = "PinkDotLock", ResetOnSpawn = false, IgnoreGuiInset = true,
			ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 40,
		}, playerGui)
		self.dot = create(self, "Frame", {
			Name = "PinkDot", Active = false, BackgroundColor3 = settings.DotColor or hotPink,
			BackgroundTransparency = settings.DotTransparency or 0, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(settings.DotSize or 6, settings.DotSize or 6),
			Visible = false, ZIndex = 3,
		}, self.gui)
		create(self, "UICorner", { CornerRadius = UDim.new(1, 0) }, self.dot)
		if settings.DotOutline ~= false then
			create(self, "UIStroke", { Color = settings.DotOutlineColor or white,
				Thickness = 1, Transparency = 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
			}, self.dot)
		end
		self.toast = create(self, "CanvasGroup", {
			Name = "Notification", Active = false, BackgroundColor3 = Color3.fromRGB(0, 0, 0),
			BackgroundTransparency = 0.25, BorderSizePixel = 0,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -28),
			Size = UDim2.new(0.85, 0, 0, 72), GroupTransparency = 1, Visible = false,
			ZIndex = 5,
		}, self.gui)
		create(self, "UISizeConstraint", { MaxSize = Vector2.new(360, 72) }, self.toast)
		create(self, "UICorner", { CornerRadius = UDim.new(0, 9) }, self.toast)
		local accent = create(self, "Frame", {
			Name = "PinkAccent", Active = false, BackgroundColor3 = hotPink,
			BorderSizePixel = 0, Position = UDim2.fromOffset(0, 0), Size = UDim2.new(0, 4, 1, 0),
			ZIndex = 6,
		}, self.toast)
		create(self, "UICorner", { CornerRadius = UDim.new(0, 2) }, accent)
		self.title = create(self, "TextLabel", {
			Name = "Title", Active = false, BackgroundTransparency = 1, Text = "",
			TextColor3 = white, Font = Enum.Font.GothamBold, TextSize = 15,
			TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
			TextTruncate = Enum.TextTruncate.AtEnd,
			Position = UDim2.fromOffset(17, 9), Size = UDim2.new(1, -32, 0, 28), ZIndex = 6,
		}, self.toast)
		self.body = create(self, "TextLabel", {
			Name = "Body", Active = false, BackgroundTransparency = 1, Text = "",
			TextColor3 = white, Font = Enum.Font.Gotham, TextSize = 11,
			TextTransparency = 0.12, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Center, TextWrapped = true,
			Position = UDim2.fromOffset(17, 37), Size = UDim2.new(1, -32, 0, 25), ZIndex = 6,
		}, self.toast)
	end)
	if not ok then
		self:destroy()
		error("PINK DOT LOCK overlay: " .. tostring(problem), 2)
	end
	return self
end

function Overlay:setDot(viewportPoint, onScreen, inset)
	if self.destroyed then return false end
	local x, y = xy(viewportPoint)
	if not onScreen or self.config.ShowDot == false or not x then self:hideDot(); return false end
	local insetX, insetY = xy(inset)
	-- WorldToViewportPoint omits the GUI inset; this full-screen GUI includes it.
	self.dot.Position = UDim2.fromOffset(x + (insetX or 0), y + (insetY or 0))
	self.dot.Visible = true
	return true
end

function Overlay:hideDot()
	if not self.destroyed then self.dot.Visible = false end
end

function Overlay:notify(message, now, duration, subtitle)
	if self.destroyed then return false end
	if self.config.ShowNotifications == false then
		self.toast.Visible = false
		self.noticeStart = nil
		return false
	end
	if not finite(now) then return false end
	duration = duration or self.config.NotificationDuration or 2
	if not finite(duration) or duration <= 0 then return false end
	self.title.Text = tostring(message or "")
	self.body.Text = subtitle and tostring(subtitle) or ""
	self.body.Visible = subtitle ~= nil and subtitle ~= ""
	self.title.Position = UDim2.fromOffset(17, self.body.Visible and 9 or 0)
	self.title.Size = UDim2.new(1, -32, 0, self.body.Visible and 28 or 72)
	self.noticeStart, self.noticeDuration = now, duration
	self.toast.GroupTransparency = 1
	self.toast.Position = UDim2.new(0.5, 0, 1, -20)
	self.toast.Visible = true
	return true
end

function Overlay:step(now)
	if self.destroyed or not self.noticeStart or not finite(now) then return end
	if self.config.ShowNotifications == false then
		self.toast.Visible = false
		self.noticeStart = nil
		return
	end
	local elapsed = math.max(0, now - self.noticeStart)
	if elapsed >= self.noticeDuration then
		self.toast.Visible = false
		self.toast.GroupTransparency = 1
		self.noticeStart = nil
		return
	end
	local fade = math.min(FADE_SECONDS, self.noticeDuration / 2)
	local visibility = math.clamp(math.min(elapsed / fade, (self.noticeDuration - elapsed) / fade), 0, 1)
	-- Smoothstep is time-based and creates no tweens or scheduled callbacks.
	visibility = visibility * visibility * (3 - 2 * visibility)
	self.toast.GroupTransparency = 1 - visibility
	self.toast.Position = UDim2.new(0.5, 0, 1, -20 - 8 * visibility)
end

function Overlay:destroy()
	if self.destroyed then return end
	self.destroyed = true
	self.noticeStart = nil
	for index = #self.owned, 1, -1 do
		pcall(function() self.owned[index]:Destroy() end)
	end
	table.clear(self.owned)
end

return Overlay
end
-- END Overlay
-- BEGIN Runtime | sha256 928acec346a1874296db3f92cd79488d30f7dd4865390cc6e47fb4bdd993d02d
factories["Runtime"] = function(loadModule)
--!nonstrict
-- Read-only audit: no Instances, event connections, camera writes or remote calls.
-- A ready report means the public client APIs used here exist, not that a
-- third-party experience's shot integration has been implemented or verified.
local Runtime = {}

local function member(object, key)
	if object == nil then return nil end
	local ok, result = pcall(function() return object[key] end)
	return if ok then result else nil
end
local function callable(object, key)
	return type(member(object, key)) == "function"
end
local function call(object, key, ...)
	local method = member(object, key)
	if type(method) ~= "function" then return false end
	return pcall(method, object, ...)
end
local function requireMethod(report, object, key, description)
	if callable(object, key) then return true end
	table.insert(report.missing, description or key)
	return false
end
local function requireSignal(report, object, key, description)
	local signal = member(object, key)
	if signal and callable(signal, "Connect") then return true end
	table.insert(report.missing, description or key)
	return false
end

function Runtime.check(config)
	config = config or {}
	local report = { ready = false, missing = {}, warnings = {}, services = {},
		capabilities = { networkPing = false, camera = false, visibility = false } }
	for _, requirement in {
		{"Instance.new", Instance, "new"}, {"Vector3.new", Vector3, "new"},
		{"Vector2.new", Vector2, "new"}, {"UDim.new", UDim, "new"},
		{"UDim2.new", UDim2, "new"}, {"UDim2.fromOffset", UDim2, "fromOffset"},
		{"UDim2.fromScale", UDim2, "fromScale"}, {"Color3.fromRGB", Color3, "fromRGB"},
		{"table.clone", table, "clone"}, {"table.clear", table, "clear"},
		{"math.clamp", math, "clamp"},
	} do requireMethod(report, requirement[2], requirement[3], requirement[1]) end
	if Enum == nil or type(Enum) == "boolean" or type(Enum) == "number" or type(Enum) == "string"
		or type(Enum) == "function" then
		table.insert(report.missing, "Enum de Roblox")
	end
	if type(typeof) ~= "function" then table.insert(report.missing, "typeof de Luau") end
	if config.VisibilityCheck ~= false then
		requireMethod(report, RaycastParams, "new", "RaycastParams.new para VisibilityCheck")
	end

	if not callable(game, "GetService") then
		table.insert(report.missing, "game:GetService del cliente Roblox")
	else
		for _, name in {"Players", "RunService", "UserInputService", "GuiService", "Workspace"} do
			local ok, service = call(game, "GetService", name)
			if ok and service then report.services[name] = service
			else table.insert(report.missing, "Servicio " .. name) end
		end
	end
	local services = report.services
	if services.RunService then
		local ok, client = call(services.RunService, "IsClient")
		if not ok or client ~= true then table.insert(report.missing, "RunService:IsClient() debe ser true") end
		requireSignal(report, services.RunService, "RenderStepped", "RunService.RenderStepped.Connect")
	end
	if services.Players then
		requireMethod(report, services.Players, "GetPlayers", "Players:GetPlayers")
		requireSignal(report, services.Players, "PlayerRemoving", "Players.PlayerRemoving.Connect")
		report.player = member(services.Players, "LocalPlayer")
		if not report.player then table.insert(report.missing, "Players.LocalPlayer")
		else
			if requireMethod(report, report.player, "FindFirstChild", "LocalPlayer:FindFirstChild") then
				local ok, gui = call(report.player, "FindFirstChild", "PlayerGui")
				if ok and gui then report.playerGui = gui
				else table.insert(report.missing, "LocalPlayer.PlayerGui") end
			end
			requireMethod(report, report.player, "WaitForChild", "LocalPlayer:WaitForChild")
		end
		if report.playerGui then
			requireMethod(report, report.playerGui, "FindFirstChild", "PlayerGui:FindFirstChild")
		end
	end
	if services.UserInputService then
		local input = services.UserInputService
		requireSignal(report, input, "InputBegan", "UserInputService.InputBegan.Connect")
		requireMethod(report, input, "GetMouseLocation", "UserInputService:GetMouseLocation")
		requireMethod(report, input, "GetFocusedTextBox", "UserInputService:GetFocusedTextBox")
	end
	if services.GuiService then requireMethod(report, services.GuiService, "GetGuiInset", "GuiService:GetGuiInset") end
	report.world = services.Workspace or workspace
	if not report.world then table.insert(report.missing, "Workspace de Roblox")
	else
		requireMethod(report, report.world, "GetServerTimeNow", "Workspace:GetServerTimeNow")
		report.capabilities.visibility = callable(report.world, "Raycast")
		if config.VisibilityCheck ~= false then requireMethod(report, report.world, "Raycast", "Workspace:Raycast para VisibilityCheck") end
		local camera = member(report.world, "CurrentCamera")
		if not camera then table.insert(report.missing, "Workspace.CurrentCamera")
		else
			report.capabilities.camera = requireMethod(report, camera, "WorldToViewportPoint", "Camera:WorldToViewportPoint")
		end
	end
	report.capabilities.networkPing = callable(report.player, "GetNetworkPing")
	if not report.capabilities.networkPing then
		table.insert(report.warnings, "GetNetworkPing no está disponible; AutoPrediction debe usar los valores manuales de PredictionX/Y.")
	end
	if not report.player or not report.playerGui or not report.capabilities.camera then
		table.insert(report.warnings, "El cliente aún no está listo; vuelve a iniciar después de cargar LocalPlayer, PlayerGui y CurrentCamera.")
	end
	report.ready = #report.missing == 0
	return report
end

function Runtime.errorMessage(report)
	if type(report) ~= "table" then return "No se pudo comprobar el cliente nativo de Roblox." end
	local missing = {}
	for _, item in report.missing or {} do
		if type(item) == "string" then table.insert(missing, item) end
	end
	if #missing == 0 then
		return if report.ready then "Cliente nativo de Roblox disponible." else "El cliente de Roblox no está listo."
	end
	return "PINK DOT LOCK no se puede iniciar. Falta: " .. table.concat(missing, "; ") .. "."
end
function Runtime.reportFailure(message)
	local logger = if type(warn) == "function" then warn elseif type(print) == "function" then print else nil
	if logger then
		local text = if type(message) == "string" then message else Runtime.errorMessage(message)
		pcall(logger, "[PINK DOT LOCK | Load Failed] " .. text)
	end
end

return Runtime
end
-- END Runtime
-- BEGIN ShotAdapter | sha256 db9d19dfa68910914063c6a8495f8955989eba335530af725f39cd6a945fe9d3
factories["ShotAdapter"] = function(loadModule)
--!nonstrict
-- Comparison adapter for an OWNED/authorized shooting system. No remotes,
-- interception, camera writes, HTTP, or game-specific integration live here.
-- referenceTime must come from the actual independent shot/reference measurement;
-- this module never manufactures a reference timestamp from prediction horizons.
local ShotAdapter = {}
ShotAdapter.__index = ShotAdapter
local POLICIES = { "active", "manual", "auto" }

local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function vector(value)
	if typeof(value) ~= "Vector3" and type(value) ~= "table" then return false end
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function position(record)
	return record and (record.targetPosition or record.position)
end
local function cloneFrozen(value, depth)
	if type(value) ~= "table" then return value end
	if depth > 5 then return nil end
	local copy = table.clone(value)
	for key, child in pairs(copy) do
		if type(child) == "table" then copy[key] = cloneFrozen(child, depth + 1) end
	end
	return table.freeze(copy)
end
local function difference(predicted, actual)
	local x, y, z = predicted.X - actual.X, predicted.Y - actual.Y, predicted.Z - actual.Z
	local horizontal = math.sqrt(x * x + z * z)
	local errorStuds = math.sqrt(x * x + y * y + z * z)
	if not finite(errorStuds) then return nil end
	return { signedX = x, signedY = y, signedZ = z, horizontalStuds = horizontal, errorStuds = errorStuds }
end
local function isValid(self, ticket)
	if not self.isTargetValid then return true end
	local ok, valid = pcall(self.isTargetValid, ticket)
	return ok and valid == true
end

function ShotAdapter.new(options)
	assert(type(options) == "table" and type(options.getSnapshot) == "function", "getSnapshot callback required")
	assert(type(options.clock) == "function", "independent clock callback required")
	assert(options.fire == nil or type(options.fire) == "function", "fire must be an owned callback")
	assert(options.onMeasurement == nil or type(options.onMeasurement) == "function", "invalid measurement callback")
	assert(options.isTargetValid == nil or type(options.isTargetValid) == "function", "invalid target validation callback")
	local maxAge = options.maxAge or 0.6
	local capacity = options.capacity or 120
	assert(finite(maxAge) and maxAge > 0 and maxAge <= 10, "invalid maxAge")
	assert(finite(capacity) and capacity >= 1 and capacity <= 5000 and capacity % 1 == 0, "invalid capacity")
	return setmetatable({
		getSnapshot = options.getSnapshot, clock = options.clock, fireCallback = options.fire,
		onMeasurement = options.onMeasurement, isTargetValid = options.isTargetValid,
		capacity = capacity, maxAge = maxAge, tickets = {}, ticketOrder = {}, records = {},
		nextId = 0, destroyed = false,
	}, ShotAdapter)
end

function ShotAdapter:capture()
	if self.destroyed then return nil, "destroyed" end
	local now = self.clock()
	if not finite(now) then return nil, "invalid-clock" end
	local ok, snapshot = pcall(self.getSnapshot)
	if not ok or type(snapshot) ~= "table" then return nil, "no-snapshot" end
	if not finite(snapshot.targetUserId) or snapshot.targetUserId % 1 ~= 0 then return nil, "invalid-target" end
	if not finite(snapshot.createdAt) or snapshot.createdAt > now + 0.05 or now - snapshot.createdAt > self.maxAge then
		return nil, "stale-snapshot"
	end
	if not finite(snapshot.sampleTime) or snapshot.sampleTime > now + 0.05 or now - snapshot.sampleTime > self.maxAge then
		return nil, "stale-sample"
	end
	for _, policy in POLICIES do
		if type(snapshot[policy]) ~= "table" or not vector(position(snapshot[policy])) or not vector(snapshot[policy].position) then
			return nil, "invalid-" .. policy .. "-prediction"
		end
	end
	self.nextId += 1
	local ticket = table.freeze({
		id = self.nextId, targetUserId = snapshot.targetUserId,
		character = snapshot.character, part = snapshot.part,
		capturedAt = now, createdAt = snapshot.createdAt, sampleTime = snapshot.sampleTime,
		active = cloneFrozen(snapshot.active, 0), manual = cloneFrozen(snapshot.manual, 0), auto = cloneFrozen(snapshot.auto, 0),
		aimpointActive = cloneFrozen(snapshot.active.position, 0),
	})
	if not isValid(self, ticket) then return nil, "target-invalid" end
	self.tickets[ticket.id] = { ticket = ticket, consumed = false }
	table.insert(self.ticketOrder, ticket.id)
	if #self.ticketOrder > self.capacity then self.tickets[table.remove(self.ticketOrder, 1)] = nil end
	return ticket
end

function ShotAdapter:fire()
	if self.destroyed then return nil, "destroyed" end
	if not self.fireCallback then return nil, "no-fire-callback" end
	local ticket, err = self:capture()
	if not ticket then return nil, err end
	local ok = pcall(self.fireCallback, ticket)
	if not ok then return nil, "fire-callback-failed" end
	return ticket
end

function ShotAdapter:record(ticketOrId, reference)
	if self.destroyed then return nil, "destroyed" end
	local id = if type(ticketOrId) == "table" then ticketOrId.id else ticketOrId
	local entry = self.tickets[id]
	if not entry then return nil, "unknown-ticket" end
	if type(ticketOrId) == "table" and ticketOrId ~= entry.ticket then return nil, "unknown-ticket" end
	if entry.consumed then return nil, "duplicate-reference" end
	local ticket = entry.ticket
	local now = self.clock()
	if not finite(now) then return nil, "invalid-clock" end
	if now - ticket.capturedAt > self.maxAge then return nil, "stale-ticket" end
	if not isValid(self, ticket) then return nil, "target-invalid" end
	if type(reference) ~= "table" or reference.accepted ~= true then return nil, "reference-not-accepted" end
	if reference.targetUserId ~= ticket.targetUserId then return nil, "target-mismatch" end
	if reference.character ~= nil and ticket.character ~= nil and reference.character ~= ticket.character then
		return nil, "character-mismatch"
	end
	if not vector(reference.actualPosition) then return nil, "invalid-reference-position" end
	if not finite(reference.referenceTime) or reference.referenceTime < ticket.capturedAt or reference.referenceTime > now + 0.05 then
		return nil, "invalid-reference-time"
	end
	if reference.actualAimPoint ~= nil and not vector(reference.actualAimPoint) then return nil, "invalid-reference-aimpoint" end
	local record = {
		ticketId = ticket.id, targetUserId = ticket.targetUserId,
		capturedAt = ticket.capturedAt, sampleTime = ticket.sampleTime,
		referenceTime = reference.referenceTime, actualPosition = cloneFrozen(reference.actualPosition, 0),
	}
	for _, policy in POLICIES do
		local prediction = ticket[policy]
		local delta = difference(position(prediction), reference.actualPosition)
		if not delta then return nil, "nonfinite-error" end
		delta.position = position(prediction)
		delta.weaponProfile = prediction.weaponProfile or prediction.weapon or "unknown"
		delta.range = prediction.range or "unknown"
		record[policy] = table.freeze(delta)
	end
	if reference.actualAimPoint then
		local aim = difference(ticket.aimpointActive, reference.actualAimPoint)
		if not aim then return nil, "nonfinite-aim-error" end
		record.activeAimErrorStuds = aim.errorStuds
	end
	entry.consumed = true
	record = table.freeze(record)
	table.insert(self.records, record)
	if #self.records > self.capacity then table.remove(self.records, 1) end
	if self.onMeasurement then pcall(self.onMeasurement, record) end
	return record
end

local function bucket()
	return { count = 0, squareSum = 0, horizontalSum = 0, verticalSum = 0, signedX = 0, signedY = 0, signedZ = 0 }
end
local function accumulate(b, delta)
	b.count += 1
	b.squareSum += delta.errorStuds * delta.errorStuds
	b.horizontalSum += delta.horizontalStuds * delta.horizontalStuds
	b.verticalSum += delta.signedY * delta.signedY
	b.signedX += delta.signedX; b.signedY += delta.signedY; b.signedZ += delta.signedZ
end
local function metrics(b)
	local count = b.count
	return {
		count = count,
		rmseStuds = if count > 0 then math.sqrt(b.squareSum / count) else nil,
		horizontalRMSEStuds = if count > 0 then math.sqrt(b.horizontalSum / count) else nil,
		verticalRMSEStuds = if count > 0 then math.sqrt(b.verticalSum / count) else nil,
		meanSignedX = if count > 0 then b.signedX / count else nil,
		meanSignedY = if count > 0 then b.signedY / count else nil,
		meanSignedZ = if count > 0 then b.signedZ / count else nil,
	}
end
function ShotAdapter:summary()
	local totals, byWeaponRange = {}, {}
	for _, policy in POLICIES do totals[policy] = bucket() end
	for _, record in self.records do
		for _, policy in POLICIES do
			local delta = record[policy]
			accumulate(totals[policy], delta)
			local weapon = byWeaponRange[delta.weaponProfile]
			if not weapon then weapon = {}; byWeaponRange[delta.weaponProfile] = weapon end
			local range = weapon[delta.range]
			if not range then range = {}; weapon[delta.range] = range end
			if not range[policy] then range[policy] = bucket() end
			accumulate(range[policy], delta)
		end
	end
	for _, weapon in byWeaponRange do
		for _, range in weapon do
			for policy, b in range do range[policy] = metrics(b) end
		end
	end
	return { measurementCount = #self.records,
		active = metrics(totals.active), manual = metrics(totals.manual), auto = metrics(totals.auto), byWeaponRange = byWeaponRange }
end

function ShotAdapter:destroy()
	if self.destroyed then return end
	self.destroyed = true
	table.clear(self.tickets); table.clear(self.ticketOrder); table.clear(self.records)
	self.getSnapshot = nil; self.clock = nil; self.fireCallback = nil
	self.isTargetValid = nil; self.onMeasurement = nil
end

return ShotAdapter
end
-- END ShotAdapter
-- BEGIN Session | sha256 c6567adc41636c5d57c37882ed4a773ed9aaac93b43e6c374f33a2291b0e3bdd
factories["Session"] = function(loadModule)
--!nonstrict
-- Public client APIs only. Selection and prediction never write camera,
-- character rotation, mouse state, or any experience's weapon communications.
local Config = loadModule("Config")
local Prediction = loadModule("Prediction")
local ModeDetector = loadModule("ModeDetector")
local Selection = loadModule("Selection")
local Overlay = loadModule("Overlay")
local Runtime = loadModule("Runtime")
local ShotAdapter = loadModule("ShotAdapter")
local Session = {}
Session.__index = Session
local OWNER_NAME = "PinkDotLock_Owner_v1"
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v) return v and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function disconnect(list)
 for _, c in list do pcall(function() c:Disconnect() end) end
 table.clear(list)
end
local function connect(list, signal, callback)
 local c = signal:Connect(callback)
 table.insert(list,c)
 return c
end

function Session:_clock()
 local t=self.world:GetServerTimeNow()
 assert(finite(t),"Invalid client clock")
 return t
end
function Session:_origin()
 local character=self.player.Character
 local head=character and character:FindFirstChild("Head")
 if head and head:IsA("BasePart") and vector(head.Position) then return head.Position end
 local root=character and character:FindFirstChild("HumanoidRootPart")
 if root and root:IsA("BasePart") and vector(root.Position) then return root.Position end
 local camera=self.world.CurrentCamera
 return camera and camera.CFrame and camera.CFrame.Position
end
function Session:_targetData(player)
 if self.destroyed or not player or player==self.player or player.Parent~=self.services.Players then return nil end
 local character=player.Character
 if not character or not character:IsDescendantOf(self.world) then return nil end
 local humanoid=character:FindFirstChildOfClass("Humanoid")
 local part=character:FindFirstChild(self.config.TargetPart)
 if not humanoid or not finite(humanoid.Health) or humanoid.Health<=0
  or not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) or not vector(part.Position) then return nil end
 local origin=self:_origin()
 if not vector(origin) then return nil end
 local distance=(part.Position-origin).Magnitude
 if not finite(distance) or distance>self.config.MaxDistance then return nil end
 return {player=player,character=character,part=part,humanoid=humanoid,distanceStuds=distance,valid=true}
end
function Session:IsValidTarget(player)
 return self:_targetData(player)~=nil
end
function Session:_visible(candidate)
 if not self.config.VisibilityCheck then return true end
 local origin=self:_origin()
 if not vector(origin) then return false end
 self.rayParams.FilterDescendantsInstances=if self.player.Character then {self.player.Character} else {}
 local direction=candidate.part.Position-origin
 if direction.Magnitude<=0.001 then return true end
 local result=self.world:Raycast(origin,direction,self.rayParams)
 return result==nil or (result.Instance~=nil and result.Instance:IsDescendantOf(candidate.character))
end
function Session:_mode(t,camera)
 local character=self.player.Character
 local humanoid=character and character:FindFirstChildOfClass("Humanoid")
 local head=character and character:FindFirstChild("Head")
 local cameraPosition=camera.CFrame and camera.CFrame.Position
 local focusPosition=camera.Focus and camera.Focus.Position
 local headDistance=if head and vector(head.Position) and vector(cameraPosition) then (cameraPosition-head.Position).Magnitude else nil
 local focusDistance=if vector(cameraPosition) and vector(focusPosition) then (cameraPosition-focusPosition).Magnitude else nil
 return self.modeDetector:update(t,{
  forcedFirstPerson=self.player.CameraMode==Enum.CameraMode.LockFirstPerson,
  subjectIsLocal=humanoid~=nil and camera.CameraSubject==humanoid,
  headDistance=headDistance,focusDistance=focusDistance,
 })
end
function Session:_view(t)
 local camera=self.world.CurrentCamera
 assert(camera and type(camera.WorldToViewportPoint)=="function","CurrentCamera is unavailable")
 local size=camera.ViewportSize
 assert(size and finite(size.X) and finite(size.Y) and size.X>0 and size.Y>0,"Camera viewport is unavailable")
 local inset=self.services.GuiService:GetGuiInset()
 assert(inset and finite(inset.X) and finite(inset.Y),"GUI inset is unavailable")
 self.mode=self:_mode(t,camera)
 local mouse=self.services.UserInputService:GetMouseLocation()
 local reference=Selection.reference(self.mode,size,mouse,inset)
 assert(reference,"Selection reference is unavailable")
 return camera,inset,reference,if self.mode=="FirstPerson" then self.config.FirstPersonFOV else self.config.ThirdPersonFOV
end
function Session:_candidate(data,camera)
 local point,onScreen=camera:WorldToViewportPoint(data.part.Position)
 data.screenPosition=point
 data.onScreen=onScreen==true and vector(point) and point.Z>0
 data.visible=self:_visible(data)
 return data
end
function Session:_notify(message,subtitle,duration)
 if self.overlay then self.overlay:notify(message,self:_clock(),duration or self.config.NotificationDuration,subtitle) end
end
function Session:GetLockedTarget()
 return if self.locked and not self.destroyed then self.locked.player else nil
end
function Session:GetPrediction()
 return if not self.destroyed and self.comparisons then self.comparisons.active else nil
end
function Session:GetPredictedPosition()
 local record=self:GetPrediction()
 return record and record.position
end
function Session:LockTarget(player)
 if self.destroyed or not self.config.Enabled then return false,"Disabled" end
 if self.locked then return false,"Already Locked" end
 local t=self:_clock()
 local camera,inset,reference,fov=self:_view(t)
 local selected
 if player then
  local data=self:_targetData(player)
  if data then
   local candidate=self:_candidate(data,camera)
   if Selection.within(candidate,reference,fov) then selected=candidate end
  end
 else
  -- Enumerate players only on an explicit lock request, never each render.
  local candidates={}
  for _, p in self.services.Players:GetPlayers() do
   local data=self:_targetData(p)
   if data then table.insert(candidates,self:_candidate(data,camera)) end
  end
  selected=Selection.nearest(candidates,reference,fov)
 end
 if not selected then return false,"No valid visible target in FOV" end
 self.locked=selected
 self.prediction:reset()
 self.nextPing=nil
 self.comparisons=nil
 self.nextObservation=t
 self.lastError=nil
 local function lost()
  if self.locked==selected then self:UnlockTarget("Target Lost") end
 end
 connect(self.targetConnections,selected.humanoid.Died,lost)
 connect(self.targetConnections,selected.character.AncestryChanged,function()
  if not selected.character:IsDescendantOf(self.world) then lost() end
 end)
 connect(self.targetConnections,selected.part.AncestryChanged,function()
  if not selected.part:IsDescendantOf(selected.character) then lost() end
 end)
 if selected.player.CharacterRemoving then
  connect(self.targetConnections,selected.player.CharacterRemoving,function(character)
   if character==selected.character then lost() end
  end)
 end
 self:_step(t)
 if self.locked then self:_notify("Locked: "..tostring(selected.player.Name)) end
 return self.locked~=nil,if self.locked then "Locked" else "Target Lost"
end
function Session:UnlockTarget(reason)
 if not self.locked then return false end
 self.locked=nil
 disconnect(self.targetConnections)
 self.prediction:reset()
 self.comparisons=nil
 self.nextObservation=nil
 if self.overlay then self.overlay:hideDot() end
 if not self.destroyed then self:_notify(reason or "Unlocked") end
 return true
end
function Session:_ping(t)
 if self.nextPing and t<self.nextPing then return end
 self.nextPing=t+1/self.config.PingHz
 local ok,rtt=pcall(function() return self.player:GetNetworkPing() end)
 self.prediction:samplePing(if ok and finite(rtt) and rtt>=0 and rtt<=2 then rtt else nil,t)
end
function Session:_step(t)
 if self.destroyed then return end
 if not self.config.Enabled then self:destroy();return end
 local camera,inset,reference,fov=self:_view(t)
 self:_ping(t)
 if self.locked then
  local data=self:_targetData(self.locked.player)
  if not data or data.character~=self.locked.character or data.part~=self.locked.part then
   self:UnlockTarget("Target Lost")
  else
   if not self.config.TargetPersistence and not Selection.within(self:_candidate(data,camera),reference,fov) then
    self:UnlockTarget("Target Lost")
   else
    local point,onScreen=camera:WorldToViewportPoint(data.part.Position)
    self.overlay:setDot(point,onScreen==true and vector(point) and point.Z>0,inset)
    if not self.nextObservation or t+1e-7>=self.nextObservation then
     self.nextObservation=t+1/self.config.UpdateHz
     local state=tostring(data.humanoid:GetState())
     -- A local capture timestamp is NOT the server's replication-production time.
     -- Derive remote velocity from recent positions; no future truth is supplied.
     self.prediction:observe(t,data.part.Position,state)
    end
    self.comparisons=self.prediction:predictComparisons(self:_origin(),t)
   end
  end
 else self.overlay:hideDot() end
 self.overlay:step(t)
 if self.config.DebugMode and (not self.nextDebug or t>=self.nextDebug) then
  self.nextDebug=t+1
  local p=self:GetPrediction()
  print("[PINK DOT LOCK]", "target="..tostring(self:GetLockedTarget()),"mode="..tostring(self.mode),
   "pingRTTms="..tostring(p and p.rawPingMs),"smoothedRTTms="..tostring(p and p.smoothedPingMs),
   "X="..tostring(p and p.predictionX),"Y="..tostring(p and p.predictionY),
   "velocity="..tostring(p and p.velocity),"current="..tostring(p and p.currentPosition),
   "predicted="..tostring(p and p.position),"distance="..tostring(p and p.distanceStuds),
   "age="..tostring(p and p.ageSeconds),"errorStuds="..tostring(self.lastError),
   "status="..tostring(if p then p.status else "Ready | No target"))
 end
end
function Session:CreateShotAdapter(fire)
 assert(not self.destroyed,"Session is unloaded")
 for i=#self.adapters,1,-1 do if self.adapters[i].destroyed then table.remove(self.adapters,i) end end
 assert(#self.adapters<32,"Too many active shot adapters")
 local adapter=ShotAdapter.new({
  clock=function() return self:_clock() end,
  getSnapshot=function()
   if self.destroyed or not self.locked then return nil end
   local t=self:_clock()
   self:_step(t)
   if not self.locked or not self.comparisons or not self.comparisons.active then return nil end
   local p=self.comparisons.active
   return {targetUserId=self.locked.player.UserId,character=self.locked.character,part=self.locked.part,
    sampleTime=p.sampleTime,createdAt=t,active=p,manual=self.comparisons.manual,auto=self.comparisons.auto}
  end,
  isTargetValid=function(ticket)
   return not self.destroyed and self.locked~=nil and self.locked.player.UserId==ticket.targetUserId
    and self.locked.character==ticket.character and self.locked.part==ticket.part
    and self:IsValidTarget(self.locked.player)
  end,
  fire=fire,capacity=120,maxAge=1,
  onMeasurement=function(record)
   self.lastError=record.active and record.active.errorStuds
  end,
 })
 table.insert(self.adapters,adapter)
 return adapter
end
function Session:SetEnabled(enabled)
 assert(type(enabled)=="boolean","Enabled must be boolean")
 if not enabled then self:destroy();return true end
 return not self.destroyed
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true
 self.config.Enabled=false
 self.locked=nil;self.comparisons=nil
 disconnect(self.targetConnections)
 disconnect(self.connections)
 for _, adapter in self.adapters do pcall(function() adapter:destroy() end) end
 table.clear(self.adapters)
 if self.prediction then self.prediction:reset() end
 if self.overlay then self.overlay:destroy() end
 if self.owner then self.owner:Destroy() end
end
Session.Unload=Session.destroy

function Session.notifyFailure(report,message)
 Runtime.reportFailure(message)
 -- A failure toast owns a short-lived GUI only; it never registers a session.
 if not report or not report.playerGui or not task or type(task.delay)~="function" then return end
 local overlay
 local ok=pcall(function()
  local timeOK,t=pcall(function() return report.world:GetServerTimeNow() end)
  if not timeOK or not finite(t) then t=os.clock() end
  local previous=report.playerGui:FindFirstChild("PinkDotLock_LoadFailure")
  if previous then previous:Destroy() end
  local cfg=assert(Config.new({ShowDot=false,ShowNotifications=true}))
  overlay=Overlay.new(report.playerGui,cfg)
  overlay.gui.Name="PinkDotLock_LoadFailure"
  overlay:notify("PINK DOT LOCK | Load Failed",t,2)
  overlay:step(t+0.18)
  task.delay(2,function() overlay:destroy() end)
 end)
 if not ok and overlay then overlay:destroy() end
end
function Session.init(options,report)
 local config,message=Config.new(options)
 assert(config,message)
 report=report or Runtime.check(config)
 assert(report.ready,Runtime.errorMessage(report))
 local self=setmetatable({config=config,services=report.services,player=report.player,world=report.world,
  playerGui=report.playerGui,connections={},targetConnections={},adapters={},destroyed=false},Session)
 local old=report.playerGui:FindFirstChild(OWNER_NAME)
 if old and not old:IsA("BindableEvent") then error("Owner namespace is occupied by another object") end
 if not config.Enabled then
  if old then old:Fire() end
  self.destroyed=true
  return self
 end
 local ok,err=pcall(function()
  self.prediction=Prediction.new(config)
  self.modeDetector=ModeDetector.new(config)
  self.overlay=Overlay.new(self.playerGui,config)
  self.ui=self.overlay
  connect(self.connections,self.overlay.gui.Destroying,function() self:destroy() end)
  if typeof(script)=="Instance" and script.Destroying then
   connect(self.connections,script.Destroying,function() self:destroy() end)
  end
  if config.VisibilityCheck then
   self.rayParams=RaycastParams.new()
   self.rayParams.FilterType=Enum.RaycastFilterType.Exclude
   self.rayParams.IgnoreWater=true
  end
  self.owner=Instance.new("BindableEvent")
  self.owner.Name=OWNER_NAME
  connect(self.connections,self.owner.Event,function() self:destroy() end)
  connect(self.connections,self.services.Players.PlayerRemoving,function(player)
   if self.locked and self.locked.player==player then self:UnlockTarget("Target Lost") end
  end)
  connect(self.connections,self.services.UserInputService.InputBegan,function(input,processed)
   if self.destroyed or processed or self.services.UserInputService:GetFocusedTextBox()~=nil then return end
   if input.KeyCode==self.config.LockKey then
    local succeeded,problem=pcall(function()
     if self.locked then self:UnlockTarget() else self:LockTarget() end
    end)
    if not succeeded then
     self:destroy()
     Session.notifyFailure(report,tostring(problem))
    end
   end
  end)
  -- Exercise view/clock/inset before announcing successful initialization.
  self:_step(self:_clock())
  connect(self.connections,self.services.RunService.RenderStepped,function()
   local succeeded,problem=pcall(function() self:_step(self:_clock()) end)
   if not succeeded then
    self:destroy()
    Session.notifyFailure(report,tostring(problem))
   end
  end)
 end)
 if not ok then self:destroy();error(err,2) end
 -- Keep the previous running session until the replacement is fully initialized.
 local committed,problem=pcall(function()
  -- Starting the toast at zero opacity can still fail; preserve the old owner
  -- until the replacement's final public-API writes have succeeded.
  if config.WelcomeNotification then
   local key=if typeof(config.LockKey)=="EnumItem" then config.LockKey.Name else tostring(config.LockKey)
   self:_notify("PINK DOT LOCK","Successfully Loaded | Press "..key.." to Lock",config.WelcomeDuration)
  end
  self.owner.Parent=self.playerGui
  if old then old:Fire() end
 end)
 if not committed then self:destroy();error(problem,2) end
 return self
end
return Session
end
-- END Session
local Modules = setmetatable({}, {__index=function(_, name) return loadModule(name) end})
local API = {Modules=Modules, getModule=loadModule, Config=Config}
function API.checkCompatibility(options) return loadModule("Runtime").check(options or Config) end
function API.tryInit(options)
 local normalized, problem = loadModule("Config").new(options or Config)
 local report = API.checkCompatibility(normalized or Config)
 API.compatibility = report
 if not normalized then report.ready=false;table.insert(report.missing,tostring(problem)) end
 if not report.ready then return nil, report end
 local ok, session = pcall(function() return loadModule("Session").init(normalized,report) end)
 if not ok then report.ready=false;table.insert(report.missing,"Initialization: "..tostring(session));return nil,report end
 API.session=session
 return session, report
end
function API.init(options)
 local session, report=API.tryInit(options)
 if not session then error(loadModule("Runtime").errorMessage(report),2) end
 return session
end
for _, name in {"GetLockedTarget","GetPredictedPosition","GetPrediction","LockTarget","UnlockTarget","IsValidTarget","CreateShotAdapter","SetEnabled","Unload"} do
 API[name]=function(...)
  if not API.session then return nil,"Not initialized" end
  return API.session[name](API.session,...)
 end
end
if game and not PINK_DOT_NO_AUTOSTART then
 local session,report=API.tryInit(Config)
 if not session then loadModule("Session").notifyFailure(report,loadModule("Runtime").errorMessage(report)) end
end
return API
