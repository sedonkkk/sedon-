--!nonstrict
-- DH PREDICTION LAB — generated standalone version of the modular project.
-- Requires native Roblox client APIs; checks capabilities before creating its GUI.
-- External hosts are not certified; no security bypasses or protected remote calls.
-- Payload makes no external HTTP requests and has no local-file dependencies.
-- Source modules and reproducible generator remain in the original project.
-- Set INITIAL_CONFIGURATION below to a plain configuration table, or import JSON in Settings.
local INITIAL_CONFIGURATION = {targetMode="OwnCharacters", useSimulatedPing=false}
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
-- BEGIN Weapons | sha256 851da2da743f7b1989246fd7f16be0aebadfa16ad982ec666408ee0baf401474
factories["Weapons"] = function(loadModule)
--!nonstrict
-- Lab profiles, NOT measured properties of any third-party game.
-- Roblox gravity is deliberately disabled for ProjectileLab initially: calibration
-- starts with straight flight; setting gravity > 0 enables ballistic compensation.
local Weapons = {}
local profiles = {
 RevolverLab = table.freeze({name="RevolverLab",kind="hitscan",speed=0,gravity=0,
  cooldown=0.35,spreadRadians=0,radius=0,latencyOffsetSeconds=0}),
 ProjectileLab = table.freeze({name="ProjectileLab",kind="projectile",speed=180,gravity=0,
  cooldown=0.25,spreadRadians=0,radius=0.12,latencyOffsetSeconds=0}),
}
function Weapons.get(name)
 return profiles[name]
end
function Weapons.names()
 return {"RevolverLab", "ProjectileLab"}
end
return table.freeze(Weapons)
end
-- END Weapons
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
-- BEGIN Predictor | sha256 aa51a4475fc06ddb225fea857aad7ad72c74c3599b0c6d8975c5649419184f26
factories["Predictor"] = function(loadModule)
--!nonstrict
local Latency=loadModule("Latency")
local MotionHistory=loadModule("MotionHistory")
local Ballistics=loadModule("Ballistics")
local Predictor={}
Predictor.__index=Predictor
function Predictor.new(settings)
 return setmetatable({settings=settings,latency=Latency.new(settings),tracks={}},Predictor)
end
function Predictor:setPing(seconds,t) return self.latency:sample(seconds,t) end
function Predictor:observe(id,sample)
 if type(id)~="string" then return false end
 local history=self.tracks[id]
 if not history then history=MotionHistory.new(self.settings);self.tracks[id]=history end
 return history:observe(sample)
end
function Predictor:forget(id) self.tracks[id]=nil end
function Predictor:clear() table.clear(self.tracks) end
function Predictor:predict(id,origin,now,profile)
 local h=self.tracks[id]
 if not h or not profile then return nil end
 local sample=h:latest()
 if not sample then return nil end
 local age=now-sample.t
 if age< -0.05 or age>self.settings.staleAfterSeconds then return nil end
 age=math.max(0,age)
 local s=self.settings
 local weaponOffset=(profile.latencyOffsetSeconds or 0)+(s.weaponOffsets[profile.name] or 0)
 local delay=self.latency:estimate(now,weaponOffset)
 local zero=sample.position*0
 local v=if s.velocityPrediction then h.velocity else zero
 local a=if s.velocityPrediction and s.accelerationPrediction and s.memoryTracking then h.acceleration else zero
 local horizon=age+delay
 -- An acceleration estimate loses credibility over long horizons. Integrate it
 -- only over a bounded interval; do not treat an unknown future turn as known.
 local used=math.min(horizon,s.maxAccelerationHorizonSeconds)
 -- Accelerate for `used`, then keep the resulting velocity. This is continuous
 -- at the confidence boundary and agrees with the projectile launch velocity.
 local base=sample.position+v*horizon+a*(used*horizon-0.5*used*used)
 local currentV=v+a*used
 local ballisticProfile=profile
 if profile.gravity and profile.gravity>0 then
  ballisticProfile=table.clone(profile)
  -- Obtain unit Y from zero vector's constructor-free axes when passed by caller.
  ballisticProfile.upVector=profile.upVector
  if not ballisticProfile.upVector then
   if Vector3 then ballisticProfile.upVector=Vector3.new(0,1,0) else return nil end
  end
 end
 local solution=Ballistics.solve(origin,base,currentV,zero,ballisticProfile,s.maxFlightSeconds,
  s.distancePrediction and s.velocityPrediction,s.maxAccelerationHorizonSeconds)
 if not solution then return nil end
 local distance=(sample.position-origin).Magnitude
 local range=if distance<40 then "close" elseif distance<120 then "medium" else "long"
 return {position=solution.aimpoint,targetPosition=solution.position,delaySeconds=delay,
  velocity=v,acceleration=a,distanceStuds=distance,state=sample.state,
  rawPingSeconds=self.latency.raw,smoothedPingSeconds=self.latency.smoothed,
  flightSeconds=solution.flightSeconds,sampleTime=sample.t,
  predictionHorizonSeconds=horizon+solution.flightSeconds,range=range}
end
return Predictor
end
-- END Predictor
-- BEGIN Geometry | sha256 89bc14b87be4788f412feb7919773d3965145f7eb9e6a40ef0be61268a60c5be
factories["Geometry"] = function(loadModule)
--!nonstrict
-- Pure finite-segment geometry, shared by authoritative projectile simulation
-- and CLI tests. Accepts Roblox Vector3 or a compatible test vector adapter.
local Geometry = {}

function Geometry.closestOnSegment(point, from, to)
	local delta = to - from
	local denominator = delta:Dot(delta)
	local alpha = if denominator > 1e-9 then math.clamp((point - from):Dot(delta) / denominator, 0, 1) else 0
	return alpha, from + delta * alpha
end

-- First contact within [0, 1], never an intersection on an infinite ray.
-- Call with projectile minus target positions at both ends to include target motion.
function Geometry.sphereIntersection(relativeStart, relativeEnd, radius)
	local delta = relativeEnd - relativeStart
	local c = relativeStart:Dot(relativeStart) - radius * radius
	if c <= 0 then return 0 end
	local a = delta:Dot(delta)
	if a < 1e-12 then return nil end
	local b = 2 * relativeStart:Dot(delta)
	local discriminant = b * b - 4 * a * c
	if discriminant < 0 then return nil end
	local first = (-b - math.sqrt(discriminant)) / (2 * a)
	return if first >= 0 and first <= 1 then first else nil
end

return table.freeze(Geometry)
end
-- END Geometry
-- BEGIN Diagnostics | sha256 a004c53576dcf712cbc468fd5d5a56178dd6925d57a129d2b4a0661ba7dc73ea
factories["Diagnostics"] = function(loadModule)
--!nonstrict
-- Bounded records. Shot misses and prediction error have different denominators.
local Diagnostics={}
Diagnostics.__index=Diagnostics
function Diagnostics.new(capacity)
 return setmetatable({capacity=math.max(1,capacity or 256),shots={},predictions={}},Diagnostics)
end
local function append(list,value,capacity)
 table.insert(list,value)
 if #list>capacity then table.remove(list,1) end
end
function Diagnostics:recordShot(record)
 if type(record)~="table" or type(record.hit)~="boolean" or record.accepted==false then return false end
 append(self.shots,table.clone(record),self.capacity);return true
end
function Diagnostics:recordPrediction(record)
 local e=record and record.errorStuds
 if type(e)~="number" or e~=e or e<0 or e==math.huge then return false end
 append(self.predictions,table.clone(record),self.capacity);return true
end
function Diagnostics:clear() table.clear(self.shots);table.clear(self.predictions) end
function Diagnostics:summary()
 local hits,missSum,missCount=0,0,0
 local byWeapon={}
 for _, shot in self.shots do
  local hit=if type(shot.intendedHit)=="boolean" then shot.intendedHit else shot.hit
  hits+=if hit then 1 else 0
  local key=shot.weapon or "unknown"
  local bucket=byWeapon[key] or {shots=0,hits=0}
  byWeapon[key]=bucket;bucket.shots+=1;bucket.hits+=if hit then 1 else 0
  local miss=shot.missDistanceStuds
  if type(miss)=="number" and miss==miss and miss>=0 and miss<math.huge then missSum+=miss;missCount+=1 end
 end
 local sum=0
 for _, p in self.predictions do
  sum+=p.errorStuds*p.errorStuds
  local key=p.weapon or "unknown"
  local bucket=byWeapon[key] or {shots=0,hits=0}
  byWeapon[key]=bucket
  bucket.predictionCount=(bucket.predictionCount or 0)+1
  bucket.predictionSquareSum=(bucket.predictionSquareSum or 0)+p.errorStuds*p.errorStuds
 end
 local count=#self.predictions
 for _,b in byWeapon do
  b.hitRate=if b.shots>0 then b.hits/b.shots else 0
  b.predictionRMSEStuds=if b.predictionCount then math.sqrt(b.predictionSquareSum/b.predictionCount) else nil
 end
 return {shots=#self.shots,hits=hits,hitRate=if #self.shots>0 then hits/#self.shots else 0,
  predictionCount=count,predictionRMSEStuds=if count>0 then math.sqrt(sum/count) else nil,
  missDistanceMeanStuds=if missCount>0 then missSum/missCount else nil,byWeapon=byWeapon}
end
return Diagnostics
end
-- END Diagnostics
-- BEGIN Configuration | sha256 4c1a62bdb5caf8f8bce173e42172e88a986e21f6a5eaae2876ffc84aee904f9a
factories["Configuration"] = function(loadModule)
--!nonstrict
-- Portable configuration for the authorized, local laboratory.
-- Times are seconds, RTT is milliseconds, distances and speeds use Roblox studs.
-- Revolver is an editable laboratory assumption, not third-party weapon data.
local Settings = loadModule("Settings")
local Weapons = loadModule("Weapons")

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
end
-- END Configuration
-- BEGIN Calibration | sha256 734acede60ddcfa98b566efe5c52aa5ec484d15e9045f9985347143e5a39368b
factories["Calibration"] = function(loadModule)
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
end
-- END Calibration
-- BEGIN Interface | sha256 f7f310af95c5209f7085bcbe661b634930100707745c20a6c8835907436a70a8
factories["Interface"] = function(loadModule)
--!nonstrict
-- Native Roblox controls with portable configuration in an editable JSON field.
local Players = if game then game:GetService("Players") else nil
local UserInputService = if game then game:GetService("UserInputService") else nil
local Interface = {}
Interface.__index = Interface
local COLORS = if Color3 then {
	background = Color3.fromRGB(11, 18, 31), surface = Color3.fromRGB(19, 31, 51),
	input = Color3.fromRGB(29, 44, 69), text = Color3.fromRGB(228, 237, 251),
	muted = Color3.fromRGB(147, 169, 199), accent = Color3.fromRGB(69, 139, 245),
	error = Color3.fromRGB(255, 156, 147),
} else nil
local WIDTH, HEIGHT = 620, 670

local function make(className, properties, parent)
	local instance = Instance.new(className)
	local ok, message = pcall(function()
		instance.Parent = parent
		for key, value in pairs(properties) do instance[key] = value end
	end)
	if not ok then instance:Destroy(); error(message, 2) end
	return instance
end
local function corner(parent, radius)
	make("UICorner", { CornerRadius = UDim.new(0, radius or 7) }, parent)
end
local function label(parent, text, size)
	return make("TextLabel", {
		BackgroundTransparency = 1, Text = text, TextColor3 = COLORS.text,
		Font = Enum.Font.Gotham, TextSize = size or 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		Size = UDim2.fromScale(1, 1),
	}, parent)
end
local function button(parent, text, properties)
	local values = { BackgroundColor3 = COLORS.input, TextColor3 = COLORS.text,
		Text = text, Font = Enum.Font.GothamBold, TextSize = 12, BorderSizePixel = 0 }
	for key, value in pairs(properties or {}) do values[key] = value end
	local result = make("TextButton", values, parent)
	corner(result)
	return result
end

function Interface:_connect(signal, callback)
	local connection = signal:Connect(callback)
	table.insert(self.connections, connection)
	return connection
end
function Interface:_value(path)
	local node = self.config
	for segment in string.gmatch(path, "[^.]+") do
		if segment == "profile" and node == self.config then
			node = self.config.profiles and self.config.profiles[self.config.activeProfile]
		elseif type(node) == "table" then node = node[segment]
		else return nil end
	end
	return node
end
function Interface:_invoke(name, ...)
	local callback = self.callbacks[name]
	if type(callback) ~= "function" then
		self:setStatus("Acción no disponible: " .. name, true)
		return false
	end
	local ok, first, second = pcall(callback, ...)
	if not ok then self:setStatus(tostring(first), true); return false end
	return true, first, second
end
function Interface:_change(path, value)
	local invoked, accepted, message = self:_invoke("onChange", path, value)
	if invoked then
		self:setStatus(message or (accepted and "Configuración actualizada." or "Valor no válido."), not accepted)
	end
	self:refreshControls()
end
function Interface:_row(page, height)
	self.order += 1
	return make("Frame", { Name = "Row", BackgroundTransparency = 1,
		Size = UDim2.new(1, -6, 0, height or 40), LayoutOrder = self.order }, page)
end
function Interface:_note(page, text, height)
	local value = label(self:_row(page, height or 48), text, 12)
	value.TextColor3 = COLORS.muted
	value.TextWrapped = true
	value.TextYAlignment = Enum.TextYAlignment.Top
	return value
end
function Interface:_section(page, title)
	local value = label(self:_row(page, 28), string.upper(title), 11)
	value.Font = Enum.Font.GothamBold
	value.TextColor3 = COLORS.accent
end
function Interface:_metric(page, key, title, height)
	local row = self:_row(page, height or 27)
	local titleLabel = label(row, title, 12)
	titleLabel.TextColor3 = COLORS.muted
	titleLabel.Size = UDim2.fromScale(0.43, 1)
	local value = label(row, "—", 12)
	value.Position = UDim2.fromScale(0.43, 0)
	value.Size = UDim2.fromScale(0.57, 1)
	value.TextXAlignment = Enum.TextXAlignment.Right
	value.TextWrapped = height ~= nil
	if not height then value.TextTruncate = Enum.TextTruncate.AtEnd end
	self.metrics[key] = self.metrics[key] or {}
	table.insert(self.metrics[key], value)
end
function Interface:_toggle(page, title, path)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -95, 1, 0)
	local control = button(row, "", { Name = path, Size = UDim2.fromOffset(76, 28),
		Position = UDim2.new(1, -76, 0.5, -14) })
	self:_connect(control.Activated, function() self:_change(path, self:_value(path) ~= true) end)
	table.insert(self.controls, { kind = "toggle", path = path, instance = control })
end
function Interface:_number(page, title, path, minimum, maximum, decimals)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -125, 1, 0)
	local input = make("TextBox", { Name = path, BackgroundColor3 = COLORS.input,
		TextColor3 = COLORS.text, ClearTextOnFocus = false, Text = "", BorderSizePixel = 0,
		Size = UDim2.fromOffset(110, 30), Position = UDim2.new(1, -110, 0.5, -15),
		Font = Enum.Font.Gotham, TextSize = 12 }, row)
	corner(input)
	self:_connect(input.FocusLost, function()
		local value = tonumber(input.Text)
		if value == nil or value ~= value or math.abs(value) == math.huge then
			self:setStatus("Escribe un número finito.", true)
		elseif value < minimum or value > maximum then
			self:setStatus(string.format("Rango permitido: %g a %g.", minimum, maximum), true)
		else self:_change(path, value) end
		self:refreshControls()
	end)
	table.insert(self.controls, { kind = "number", path = path, instance = input, decimals = decimals or 3 })
end
function Interface:_closeDropdowns()
	for _, dropdown in ipairs(self.dropdowns) do
		dropdown.options.Visible = false
		dropdown.row.Size = UDim2.new(1, -6, 0, 40)
	end
end
function Interface:_dropdown(page, title, path, options)
	local row = self:_row(page)
	local titleLabel = label(row, title)
	titleLabel.Size = UDim2.new(1, -210, 0, 40)
	local control = button(row, "", { Name = path, Size = UDim2.fromOffset(198, 30),
		Position = UDim2.new(1, -198, 0, 5) })
	local choices = make("Frame", { Name = "Options", BackgroundColor3 = COLORS.input,
		BorderSizePixel = 0, Position = UDim2.new(1, -198, 0, 40),
		Size = UDim2.fromOffset(198, #options * 31 + 4), Visible = false }, row)
	corner(choices)
	for index, option in ipairs(options) do
		local optionLabel = type(option) == "table" and option.label or option
		local optionValue = option
		if type(option) == "table" then optionValue = option.value end
		local choice = button(choices, optionLabel, { Name = optionLabel,
			BackgroundTransparency = 1, Size = UDim2.new(1, -4, 0, 30),
			Position = UDim2.fromOffset(2, (index - 1) * 31 + 2) })
		self:_connect(choice.Activated, function()
			self:_closeDropdowns()
			self:_change(path, optionValue)
		end)
	end
	self:_connect(control.Activated, function()
		local show = not choices.Visible
		self:_closeDropdowns()
		choices.Visible = show
		row.Size = UDim2.new(1, -6, 0, show and (44 + #options * 31) or 40)
	end)
	table.insert(self.dropdowns, { row = row, options = choices })
	table.insert(self.controls, { kind = "dropdown", path = path, instance = control, options = options })
end
function Interface:_button(page, title, callback, name)
	local control = button(self:_row(page, 38), title, {
		Name = name or title, Size = UDim2.new(1, 0, 0, 34) })
	self:_connect(control.Activated, callback)
	return control
end
function Interface:refreshControls()
	if self.destroyed then return end
	for _, control in ipairs(self.controls) do
		local value = self:_value(control.path)
		if control.kind == "toggle" then
			control.instance.Text = value == true and "ON" or "OFF"
			control.instance.TextColor3 = value == true and COLORS.text or COLORS.muted
			control.instance.BackgroundColor3 = value == true and COLORS.accent or COLORS.input
		elseif control.kind == "number" then
			if not control.instance:IsFocused() then
				control.instance.Text = type(value) == "number"
					and string.format("%." .. control.decimals .. "f", value) or "—"
			end
		else
			local display = tostring(value)
			for _, option in ipairs(control.options) do
				if type(option) == "table" and option.value == value then display = option.label end
			end
			control.instance.Text = display .. "  ▾"
		end
	end
end
function Interface:setConfig(config)
	self.config = config
	self:refreshControls()
end
function Interface:setStatus(message, isError)
	if self.destroyed or not self.status then return end
	self.status.Text = tostring(message or "")
	self.status.TextColor3 = isError and COLORS.error or COLORS.muted
end
function Interface:_showPage(name)
	self:_closeDropdowns()
	for pageName, page in pairs(self.pages) do
		local selected = pageName == name
		page.Visible = selected
		self.tabs[pageName].TextColor3 = selected and COLORS.text or COLORS.muted
		self.tabs[pageName].BackgroundColor3 = selected and COLORS.accent or COLORS.surface
	end
end
function Interface:_setCollapsed(collapsed)
	self.collapsed = collapsed
	self.content.Visible = not collapsed
	self.tabStrip.Visible = not collapsed
	self.status.Visible = not collapsed
	self.fireButton.Visible = not collapsed
	self.panel.Size = UDim2.fromOffset(WIDTH, collapsed and 54 or HEIGHT)
	self.minimize.Text = collapsed and "+" or "−"
	self:_fit()
end
function Interface:_fit()
	local camera = workspace.CurrentCamera
	if not camera or not self.scale then return end
	local viewport = camera.ViewportSize
	self.scale.Scale = math.clamp(math.min((viewport.X - 24) / WIDTH, (viewport.Y - 32) / HEIGHT), 0.2, 1)
	local position = self.panel.Position
	self.panel.Position = UDim2.fromOffset(
		math.clamp(position.X.Offset, 0, math.max(0, viewport.X - self.panel.AbsoluteSize.X)),
		math.clamp(position.Y.Offset, 0, math.max(0, viewport.Y - self.panel.AbsoluteSize.Y))
	)
end
function Interface:_showText(text, message)
	if type(text) ~= "string" then self:setStatus("La exportación no devolvió texto JSON.", true); return end
	self.editor.Text = text
	self:_setCollapsed(false)
	self:_showPage("SETTINGS")
	-- UIListLayout updates asynchronously; the next metrics update sees its positions.
	self.pendingEditorScroll = true
	self:setStatus(message or "JSON listo para copiar desde el campo editable.")
end

function Interface.new(config, callbacks)
	assert(Players and UserInputService and COLORS, "La interfaz requiere las APIs de Roblox en un LocalScript")
	local self = setmetatable({ config = config, callbacks = callbacks or {},
		connections = {}, controls = {}, metrics = {}, pages = {}, tabs = {},
		dropdowns = {}, order = 0, destroyed = false }, Interface)
	local ok, failure = pcall(function()
	self.gui = make("ScreenGui", { Name = "DHPredictionLab", ResetOnSpawn = false,
		IgnoreGuiInset = true, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 30,
	}, Players.LocalPlayer:WaitForChild("PlayerGui"))
	-- Session owns this event so a later run can clean up the complete session.
	self.stopEvent = make("BindableEvent", { Name = "DHPredictionLabStop" }, self.gui)
	self.panel = make("Frame", { Name = "Panel", BackgroundColor3 = COLORS.background,
		BorderSizePixel = 0, Size = UDim2.fromOffset(WIDTH, HEIGHT),
		Position = UDim2.fromOffset(22, 38) }, self.gui)
	corner(self.panel, 12)
	make("UIStroke", { Color = Color3.fromRGB(44, 69, 104), Thickness = 1 }, self.panel)
	self.scale = make("UIScale", {}, self.panel)
	local header = make("Frame", { BackgroundTransparency = 1,
		Size = UDim2.new(1, -28, 0, 54), Position = UDim2.fromOffset(14, 0) }, self.panel)
	local dragHandle = make("Frame", { Name = "DragHandle", BackgroundTransparency = 1,
		Active = true, Size = UDim2.new(1, -115, 1, 0) }, header)
	local title = label(dragHandle, "DH PREDICTION LAB", 17)
	title.Font, title.TextColor3 = Enum.Font.GothamBold, COLORS.accent
	self.minimize = button(header, "−", { Name = "Minimize", TextSize = 20,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -105, 0, 12) })
	local hide = button(header, "↓", { Name = "Hide", TextSize = 18,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -69, 0, 12) })
	local close = button(header, "×", { Name = "Close", TextSize = 20,
		Size = UDim2.fromOffset(32, 29), Position = UDim2.new(1, -32, 0, 12) })
	self.restore = button(self.gui, "SHOW DH LAB", { Name = "RestoreMenu",
		BackgroundColor3 = COLORS.accent, Size = UDim2.fromOffset(142, 34),
		Position = UDim2.new(0, 12, 1, -46), Visible = false })
	self.tabStrip = make("Frame", { BackgroundTransparency = 1,
		Position = UDim2.fromOffset(16, 54), Size = UDim2.new(1, -32, 0, 32) }, self.panel)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal,
		Padding = UDim.new(0, 5), SortOrder = Enum.SortOrder.LayoutOrder }, self.tabStrip)
	self.content = make("Frame", { BackgroundTransparency = 1,
		Position = UDim2.fromOffset(18, 99), Size = UDim2.new(1, -36, 0, HEIGHT - 188) }, self.panel)
	for index, name in ipairs({ "MAIN", "PREDICTION", "WEAPONS", "DIAGNOSTICS", "SETTINGS" }) do
		local tab = button(self.tabStrip, name, { Name = name, TextSize = 10,
			Size = UDim2.new(0.2, -4, 1, 0), LayoutOrder = index })
		local page = make("ScrollingFrame", { Name = name, BackgroundTransparency = 1,
			BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
			AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
			ScrollBarImageColor3 = COLORS.accent, ScrollingDirection = Enum.ScrollingDirection.Y,
			Visible = false }, self.content)
		make("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, page)
		self.pages[name], self.tabs[name] = page, tab
		self:_connect(tab.Activated, function() self:_showPage(name) end)
	end

	local main = self.pages.MAIN
	self:_toggle(main, "Enable", "core.enabled")
	self:_dropdown(main, "AimType", "core.memoryTracking", {
		{ label = "Memory", value = true }, { label = "Velocity", value = false } })
	self:_toggle(main, "Auto Prediction", "core.autoPrediction")
	self:_number(main, "Manual Prediction · active profile (s)", "profile.manualDelaySeconds", 0, 0.6, 3)
	self:_dropdown(main, "Target source", "targetMode", { "Simulated", "OwnCharacters" })
	self:_number(main, "FOV · radius (pixels)", "core.fovPixels", 20, 1000, 0)
	self:_number(main, "Target distance limit (studs)", "core.maxTargetDistanceStuds", 10, 2000, 0)
	self:_toggle(main, "Position Indicators", "core.debugVisualization")
	self:_note(main, "RMB orienta la cámara; F o DISPARAR mide un tiro del laboratorio. Simulated usa objetivos locales; OwnCharacters usa personajes de esta experiencia.")
	self:_section(main, "Live prediction")
	self:_metric(main, "target", "Target")
	self:_metric(main, "delay", "Prediction delay")
	self:_metric(main, "predicted", "Predicted position")
	self:_metric(main, "status", "Runtime status", 42)

	local prediction = self.pages.PREDICTION
	for _, item in ipairs({
		{ "Ping Based Prediction", "pingCompensation" }, { "Velocity Prediction", "core.velocityPrediction" },
		{ "Distance Based Prediction", "core.distancePrediction" }, { "Memory Tracking", "core.memoryTracking" },
		{ "Acceleration Prediction", "core.accelerationPrediction" },
	}) do self:_toggle(prediction, item[1], item[2]) end
	self:_number(prediction, "Prediction Smoothing · τ (s)", "predictionSmoothingSeconds", 0, 1, 3)
	self:_number(prediction, "Ping Smoothing · τ (s)", "core.pingSmoothingSeconds", 0.05, 10, 3)
	self:_number(prediction, "Global latency offset (s)", "core.latencyOffsetSeconds", -0.2, 0.2, 3)
	self:_note(prediction, "Auto usa RTT/2 suavizado y offsets del perfil. Manual usa los segundos del perfil activo. La simulación retrasa observaciones; el suavizado de predicción usa tiempo, no FPS.", 54)
	self:_section(prediction, "Advanced calibration")
	self:_toggle(prediction, "Adaptive Calibration", "adaptiveCalibration")
	self:_metric(prediction, "suggestion", "Measured suggestion", 42)
	self:_button(prediction, "APPLY CALIBRATION SUGGESTION", function()
		local ok, accepted, message = self:_invoke("onApplyCalibration")
		if ok and accepted ~= nil then
			self:setStatus(message or (accepted and "Calibración aplicada." or "Faltan mediciones suficientes."), not accepted)
		end
	end, "ApplyCalibration")
	self:_note(prediction, "La sugerencia se obtiene del error medido para el perfil activo. Los offsets no se ajustan a valores universales por nombre de arma.")

	local weapons = self.pages.WEAPONS
	self:_dropdown(weapons, "Weapon Profile", "activeProfile", { "Revolver", "Default", "Custom" })
	self:_dropdown(weapons, "Physics model", "profile.kind", { "hitscan", "projectile" })
	for _, item in ipairs({
		{ "Manual delay (s)", "manualDelaySeconds", 0, 0.6, 3 },
		{ "Profile latency offset (s)", "latencyOffsetSeconds", -0.2, 0.2, 3 },
		{ "Projectile speed (studs/s)", "speed", 0, 20000, 1 },
		{ "Gravity (studs/s²)", "gravity", 0, 1000, 2 },
		{ "Shot cooldown (s)", "cooldown", 0.01, 10, 3 },
		{ "Spread (radians)", "spreadRadians", 0, math.pi, 4 },
		{ "Projectile radius (studs)", "radius", 0, 20, 2 },
	}) do self:_number(weapons, item[1], "profile." .. item[2], item[3], item[4], item[5]) end
	self:_section(weapons, "Range offsets · seconds")
	for _, range in ipairs({ "close", "medium", "long" }) do
		self:_number(weapons, range, "profile.rangeOffsets." .. range, -0.15, 0.15, 3)
	end
	self:_note(weapons, "Los perfiles conservan ajustes independientes. Revolver, Default y Custom describen supuestos del laboratorio. Hitscan no añade vuelo; projectile usa velocidad y gravedad.", 55)

	local diagnostics = self.pages.DIAGNOSTICS
	for _, item in ipairs({
		{ "rtt", "Current Ping · RTT" }, { "ping", "Estimated one-way / smoothed" },
		{ "delay", "Applied prediction delay" }, { "speed", "Target velocity" },
		{ "distance", "Target distance" }, { "range", "Distance range" },
		{ "current", "Observed position (studs)" }, { "predicted", "Predicted position (studs)" },
		{ "aimpoint", "Aim point (studs)" }, { "flight", "Projectile flight time" },
		{ "weapon", "Active weapon" }, { "error", "Current prediction error" },
		{ "autoRMSE", "Auto RMSE / samples" }, { "manualRMSE", "Manual RMSE / samples" },
		{ "measurementCount", "Measured samples" }, { "hitRate", "Shot hit rate" },
	}) do self:_metric(diagnostics, item[1], item[2]) end
	self:_metric(diagnostics, "status", "Status", 42)
	self:_note(diagnostics, "RMSE compara posiciones predichas con observaciones posteriores del objetivo. Los tiros del laboratorio añaden dispersión; su tasa de aciertos se mide por separado.", 52)
	self:_button(diagnostics, "EXPORT MEASUREMENTS · JSON", function()
		local ok, text = self:_invoke("onExportMeasurements")
		if ok and text ~= nil then self:_showText(text, "Mediciones JSON listas para copiar.") end
	end, "ExportMeasurements")
	self:_button(diagnostics, "CLEAR MEASUREMENTS", function() self:_invoke("onClearMeasurements") end, "ClearMeasurements")

	local settings = self.pages.SETTINGS
	self:_toggle(settings, "Use Simulated Ping", "useSimulatedPing")
	self:_number(settings, "Simulated RTT (ms)", "simulatedRTTMilliseconds", 0, 2000, 1)
	self:_number(settings, "Simulated observation delay (s)", "simulatedObservationDelaySeconds", 0, 0.25, 3)
	self:_number(settings, "Minimum latency (s)", "core.minDelaySeconds", 0, 0.6, 3)
	self:_number(settings, "Maximum latency (s)", "core.maxDelaySeconds", 0, 0.6, 3)
	self:_number(settings, "Updates per second", "core.updateHz", 5, 60, 0)
	self:_button(settings, "SAVE CONFIGURATION · JSON", function()
		local ok, text = self:_invoke("onSave")
		if ok then self:_showText(text, "Configuración JSON lista para copiar y guardar.") end
	end, "SaveConfiguration")
	self:_note(settings, "Copia el JSON para guardarlo. Para cargarlo, pega una configuración en el campo y pulsa LOAD CONFIGURATION. Las mediciones exportadas usan el mismo campo.", 54)
	self.editorRow = self:_row(settings, 190)
	local editorScroll = make("ScrollingFrame", { Name = "JSONScroll", BackgroundColor3 = COLORS.input,
		BorderSizePixel = 0, Size = UDim2.fromScale(1, 1), CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollBarThickness = 4,
		ScrollBarImageColor3 = COLORS.accent, ScrollingDirection = Enum.ScrollingDirection.Y,
	}, self.editorRow)
	corner(editorScroll)
	self.editor = make("TextBox", { Name = "PortableJSON", BackgroundTransparency = 1,
		TextColor3 = COLORS.text, BorderSizePixel = 0, ClearTextOnFocus = false,
		MultiLine = true, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, Font = Enum.Font.Code, TextSize = 11,
		Text = "", PlaceholderText = "Pega aquí la configuración JSON…",
		PlaceholderColor3 = COLORS.muted, Size = UDim2.new(1, -6, 0, 180),
		AutomaticSize = Enum.AutomaticSize.Y }, editorScroll)
	make("UIPadding", { PaddingTop = UDim.new(0, 8), PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8) }, self.editor)
	self:_button(settings, "LOAD CONFIGURATION", function()
		local ok, accepted, message = self:_invoke("onLoad", self.editor.Text)
		if ok then self:setStatus(message or (accepted and "Configuración cargada." or "JSON no válido."), not accepted) end
	end, "LoadConfiguration")
	self:_button(settings, "RESET CONFIGURATION", function() self:_invoke("onReset") end, "ResetConfiguration")
	self:_button(settings, "HIDE MENU", function() self.panel.Visible = false; self.restore.Visible = true end, "HideMenu")
	self:_button(settings, "UNLOAD · CLEAN UP", function() self:_invoke("onUnload") end, "Unload")

	self.status = label(self.panel, "Preparando DH Prediction Lab…", 11)
	self.status.Position, self.status.Size = UDim2.fromOffset(18, HEIGHT - 78), UDim2.new(1, -36, 0, 24)
	self.status.TextColor3, self.status.TextTruncate = COLORS.muted, Enum.TextTruncate.AtEnd
	self.fireButton = button(self.panel, "DISPARAR  ·  F", { Name = "Fire",
		BackgroundColor3 = COLORS.accent, TextSize = 13,
		Size = UDim2.new(1, -36, 0, 36), Position = UDim2.fromOffset(18, HEIGHT - 48) })
	self:_connect(self.fireButton.Activated, function() self:_invoke("onFire") end)
	self:_connect(self.minimize.Activated, function() self:_setCollapsed(not self.collapsed) end)
	self:_connect(hide.Activated, function() self.panel.Visible = false; self.restore.Visible = true end)
	self:_connect(self.restore.Activated, function() self.panel.Visible = true; self.restore.Visible = false; self:_fit() end)
	self:_connect(close.Activated, function()
		if self.callbacks.onUnload then self:_invoke("onUnload") else self:destroy() end
	end)

	local dragInput, dragStart, startPosition
	self:_connect(dragHandle.InputBegan, function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragInput, dragStart, startPosition = input, input.Position, self.panel.Position
		end
	end)
	self:_connect(UserInputService.InputEnded, function(input) if input == dragInput then dragInput = nil end end)
	self:_connect(UserInputService.InputChanged, function(input)
		if dragInput and (input.UserInputType == Enum.UserInputType.MouseMovement or input == dragInput) then
			local delta = input.Position - dragStart
			self.panel.Position = UDim2.fromOffset(startPosition.X.Offset + delta.X, startPosition.Y.Offset + delta.Y)
			self:_fit()
		end
	end)
	self:_connect(workspace:GetPropertyChangedSignal("CurrentCamera"), function() self:_fit() end)
	self:refreshControls()
	self:_showPage("MAIN")
	self:_fit()
	end)
	if not ok then self:destroy(); error("Interfaz: " .. tostring(failure), 2) end
	return self
end
function Interface:isPointerOver()
	if self.destroyed or not self.gui.Enabled then return false end
	local pointer = UserInputService:GetMouseLocation()
	for _, frame in ipairs({ self.panel, self.restore }) do
		if frame.Visible then
			local position, size = frame.AbsolutePosition, frame.AbsoluteSize
			if pointer.X >= position.X and pointer.X <= position.X + size.X
				and pointer.Y >= position.Y and pointer.Y <= position.Y + size.Y then return true end
		end
	end
	return false
end
function Interface:update(live)
	if self.destroyed then return end
	self:_fit()
	if self.pendingEditorScroll then
		local page = self.pages.SETTINGS
		local offset = (self.editorRow.AbsolutePosition.Y - page.AbsolutePosition.Y) / self.scale.Scale + page.CanvasPosition.Y
		page.CanvasPosition = Vector2.new(0, math.max(0, offset))
		self.pendingEditorScroll = false
	end
	for key, value in pairs(live or {}) do
		for _, metric in ipairs(self.metrics[key] or {}) do metric.Text = tostring(value) end
	end
end
function Interface:destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _, connection in ipairs(self.connections) do connection:Disconnect() end
	table.clear(self.connections)
	if self.gui then self.gui:Destroy() end
end
return Interface
end
-- END Interface
-- BEGIN Runtime | sha256 4500086c35c2e5d1c5bde7dd4fa8761e02afdba77490d718ed055a8e0fb9d514
factories["Runtime"] = function(loadModule)
--!nonstrict
-- Read-only audit of the native Roblox client APIs used by this laboratory.
-- This describes available capabilities; it does not certify an external host
-- or an experience, and does not use executor APIs, hooks, or protected remotes.
local Runtime = {}

local function member(object, key)
 if object == nil then return nil end
 local ok, value = pcall(function() return object[key] end)
 return if ok then value else nil
end

local function callable(object, key)
 return type(member(object, key)) == "function"
end

local function call(object, key, ...)
 local method = member(object, key)
 if type(method) ~= "function" then return false, nil end
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

function Runtime.check()
 local report = {
  ready = false, missing = {}, warnings = {}, services = {},
  capabilities = {spherecast = false, networkPing = false, camera = false},
 }
 -- Inspect constructor members without invoking them: the audit creates no
 -- Instances, connections, vectors, casts, JSON payloads, or pending work.
 for _, requirement in {
  {"Instance.new", Instance, "new"}, {"Vector3.new", Vector3, "new"},
  {"Vector2.new", Vector2, "new"}, {"CFrame.lookAt", CFrame, "lookAt"},
  {"UDim.new", UDim, "new"}, {"UDim2.new", UDim2, "new"},
  {"UDim2.fromOffset", UDim2, "fromOffset"}, {"UDim2.fromScale", UDim2, "fromScale"},
  {"Color3.fromRGB", Color3, "fromRGB"}, {"Random.new", Random, "new"},
  {"RaycastParams.new", RaycastParams, "new"},
  {"table.clone", table, "clone"}, {"table.clear", table, "clear"},
  {"math.clamp", math, "clamp"}, {"string.split", string, "split"},
 } do
  requireMethod(report, requirement[2], requirement[3], requirement[1])
 end
 if type(typeof)~="function" then table.insert(report.missing,"typeof de Luau") end
 if Enum == nil or type(Enum) == "boolean" or type(Enum) == "number" or type(Enum) == "string" or type(Enum) == "function" then
  table.insert(report.missing, "Enum de Roblox")
 end

 if not callable(game, "GetService") then
  table.insert(report.missing, "game:GetService (cliente nativo de Roblox)")
 else
  for _, name in {"Players", "RunService", "UserInputService", "GuiService", "HttpService"} do
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
  report.player = member(services.Players, "LocalPlayer")
  if report.player == nil then
   table.insert(report.missing, "Players.LocalPlayer")
   table.insert(report.warnings, "LocalPlayer aún no está disponible; vuelve a iniciar cuando termine de cargar el cliente.")
  elseif requireMethod(report, report.player, "FindFirstChild", "LocalPlayer:FindFirstChild") then
   requireMethod(report, report.player, "WaitForChild", "LocalPlayer:WaitForChild")
   local ok, playerGui = call(report.player, "FindFirstChild", "PlayerGui")
   if ok and playerGui ~= nil then
    report.playerGui = playerGui
    requireMethod(report, playerGui, "FindFirstChild", "PlayerGui:FindFirstChild")
   else
    table.insert(report.missing, "LocalPlayer.PlayerGui")
    table.insert(report.warnings, "PlayerGui aún no está disponible; vuelve a iniciar cuando termine de cargar la interfaz.")
   end
  end
 end
 if services.UserInputService then
  local input = services.UserInputService
  requireMethod(report, input, "GetMouseLocation", "UserInputService:GetMouseLocation")
  requireMethod(report, input, "GetFocusedTextBox", "UserInputService:GetFocusedTextBox")
  for _, name in {"InputBegan", "InputEnded", "WindowFocusReleased"} do
   requireSignal(report, input, name, "UserInputService." .. name .. ".Connect")
  end
 end
 if services.GuiService then requireMethod(report, services.GuiService, "GetGuiInset", "GuiService:GetGuiInset") end
 if services.HttpService then
  requireMethod(report, services.HttpService, "JSONEncode", "HttpService:JSONEncode")
  requireMethod(report, services.HttpService, "JSONDecode", "HttpService:JSONDecode")
 end

 report.world = workspace
 if report.world == nil then table.insert(report.missing, "workspace de Roblox")
 else
  requireMethod(report, report.world, "GetServerTimeNow", "Workspace:GetServerTimeNow")
  requireMethod(report, report.world, "Raycast", "Workspace:Raycast")
  requireMethod(report, report.world, "GetPropertyChangedSignal", "Workspace:GetPropertyChangedSignal")
  report.capabilities.spherecast = callable(report.world, "Spherecast")
  report.capabilities.camera = member(report.world, "CurrentCamera") ~= nil
 end
 if not report.capabilities.spherecast then
  table.insert(report.warnings, "Workspace:Spherecast no está disponible; los proyectiles con radio necesitan esta capacidad.")
 end
 report.capabilities.networkPing = callable(report.player, "GetNetworkPing")
 if not report.capabilities.networkPing then
  table.insert(report.warnings, "GetNetworkPing no está disponible; puedes usar RTT simulado o predicción manual.")
 end
 if not report.capabilities.camera then
  table.insert(report.warnings, "CurrentCamera aún no está disponible; la selección esperará a que aparezca.")
 end
 report.ready = #report.missing == 0
 return report
end

function Runtime.errorMessage(report)
 if type(report) ~= "table" then return "No se pudo comprobar el cliente nativo de Roblox." end
 local missing = {}
 for _, value in report.missing or {} do
  if type(value) == "string" then table.insert(missing, value) end
 end
 if #missing == 0 then
  return if report.ready then "Cliente nativo de Roblox disponible." else "El cliente nativo de Roblox no está listo."
 end
 return "No se puede iniciar el laboratorio. Falta: " .. table.concat(missing, "; ") .. "."
end

function Runtime.reportFailure(message)
 local logger=if type(warn)=="function" then warn elseif type(print)=="function" then print else nil
 if logger then
  local text = if type(message) == "string" then message else "No se pudo iniciar el laboratorio local."
  pcall(logger, "[DH PREDICTION LAB] " .. text)
 end
end

return Runtime
end
-- END Runtime
-- BEGIN Session | sha256 0c9ace6b0ee96b06d3d4565aef4725f73ed8a54fb8e98b8d013e938d2a9d074d
factories["Session"] = function(loadModule)
--!nonstrict
-- Single-client laboratory. All test shots are local measurements, never weapon
-- commands, damage, or protected communications in another experience.
local Configuration = loadModule("Configuration")
local Calibration = loadModule("Calibration")
local Interface = loadModule("Interface")
local Predictor = loadModule("Predictor")
local Settings = loadModule("Settings")
local Diagnostics = loadModule("Diagnostics")
local Geometry = loadModule("Geometry")
local Runtime = loadModule("Runtime")
local Session = {}
Session.__index = Session
local MAX_RANGE = 400
local MAX_PENDING = 96
local MAX_PROJECTILES = 24
local MEASUREMENT_INTERVAL = 0.2

local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vecOK(v) return typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) end
local function copyCore(from, into)
 for k,v in from do into[k]=v end
end
local function connection(self, signal, callback)
 local c=signal:Connect(callback);table.insert(self.connections,c);return c
end
local function now() return workspace:GetServerTimeNow() end
local function positionAt(spec, t)
 local elapsed=t-spec.epoch+spec.phase
 local phase=(elapsed/spec.period)%1
 local x=spec.width*(1-4*math.abs(phase-0.5))
 local vx=(if phase<0.5 then 1 else -1)*4*spec.width/spec.period
 local jump=(elapsed%3.4)-1.8
 local y,vy,state=0,0,"running"
 if jump>=0 and jump<1.2 then
  y=24*jump-20*jump*jump;vy=24-40*jump;state=if vy>0 then "jumping" else "falling"
 end
 return spec.base+Vector3.new(x,y,4*math.sin(elapsed*0.9)),
  Vector3.new(vx,vy,3.6*math.cos(elapsed*0.9)),state
end

function Session:_origin()
 local character=self.player.Character
 local head=character and character:FindFirstChild("Head")
 if head and head:IsA("BasePart") then return head.Position end
 local root=character and character:FindFirstChild("HumanoidRootPart")
 return if root and root:IsA("BasePart") then root.Position+Vector3.new(0,1.5,0) else nil
end
function Session:_part(name, size, color)
 local p=Instance.new("Part")
 p.Parent=self.world
 p.Name=name;p.Anchored=true;p.CanCollide=false;p.CanTouch=false;p.CanQuery=false
 p.Size=size;p.Color=color;p.Material=Enum.Material.Neon;p.CastShadow=false
 return p
end
function Session:_createTargets()
 if #self.specs>0 then return end
 local origin=self:_origin()
 if not origin then return end
 local camera=workspace.CurrentCamera
 local forward=if camera then camera.CFrame.LookVector else Vector3.new(0,0,-1)
 forward=Vector3.new(forward.X,0,forward.Z)
 if forward.Magnitude<0.1 then forward=Vector3.new(0,0,-1) else forward=forward.Unit end
 for i, distance in {28,80,150} do
  local id=({"near","mid","far"})[i]
  local p=self:_part(id,Vector3.new(4,4,4),({Color3.fromRGB(74,177,255),Color3.fromRGB(100,214,235),Color3.fromRGB(165,146,255)})[i])
  p.Shape=Enum.PartType.Ball
  local spec={id=id,part=p,radius=2,base=origin+forward*distance,
   width=10+i*3,period=4+i*0.5,phase=(i-1)*1.1,epoch=now()}
  table.insert(self.specs,spec)
 end
end
function Session:_newPredictors()
 self.predictor=Predictor.new(self.config.core)
 self.autoCore=Settings.new();self.manualCore=Settings.new()
 self.autoPredictor=Predictor.new(self.autoCore);self.manualPredictor=Predictor.new(self.manualCore)
 -- Both alternatives reuse the very same bounded Memory history; only latency
 -- filters differ. No future truth is supplied to any of these predictors.
 self.autoPredictor.tracks=self.predictor.tracks;self.manualPredictor.tracks=self.predictor.tracks
 self.targets={};self.selected=nil;self.solution=nil;self.drawPoint=nil
 self.lastPingSample=nil
end
function Session:_resetTracking()
 self:_newPredictors();table.clear(self.pending);table.clear(self.shots)
 for _, projectile in self.projectiles do projectile.part:Destroy() end
 table.clear(self.projectiles)
end
function Session:_clearMeasurements()
 table.clear(self.pending);self.calibration:clear();self.diagnostics:clear();self.lastError=nil
end
function Session:_replaceConfig(config)
 self.config=config;self:_resetTracking();self.calibration:clear();self.diagnostics:clear()
 self.lastError=nil;self.ui:setConfig(config)
end
function Session:_change(path,value)
 local candidate=Configuration.createSnapshot(self.config)
 local object=candidate
 local keys=string.split(path,".")
 if keys[1]=="profile" then object=candidate.profiles[candidate.activeProfile];table.remove(keys,1) end
 for i=1,#keys-1 do
  if type(object[keys[i]])~="table" then return false,"Campo desconocido" end
  object=object[keys[i]]
 end
 local key=keys[#keys]
 if object[key]==nil then return false,"Campo desconocido" end
 object[key]=value
 local ok,message=Configuration.validate(candidate)
 if not ok then return false,message end
 local reset=path=="targetMode" or path=="core.memoryTracking" or path=="activeProfile"
 if reset then
  self.config=candidate;self:_resetTracking();self.ui:setConfig(candidate)
 else
  -- Mutate the existing root settings object, preserving predictor references.
  local originalCore=self.config.core
  copyCore(candidate.core,originalCore);candidate.core=originalCore;self.config=candidate
  self.ui:setConfig(candidate)
 end
 -- Do not mix training from different latency/physics assumptions. Display and
 -- selection-only controls can retain the same measurement window.
 local retain=path=="core.enabled" or path=="core.debugVisualization" or path=="core.fovPixels"
  or path=="core.maxTargetDistanceStuds" or path=="predictionSmoothingSeconds" or path=="adaptiveCalibration"
 if not retain then self:_clearMeasurements() end
 return true
end
function Session:_ping(t)
 if self.lastPingSample and t-self.lastPingSample<0.2 then return end
 self.lastPingSample=t
 if self.config.useSimulatedPing then self.rtt=self.config.simulatedRTTMilliseconds/1000
 else
  local ok,value=pcall(function() return self.player:GetNetworkPing() end)
  if ok and finite(value) and value>=0 and value<=2 then self.rtt=value
  else self.rtt=nil end
 end
 self.actualOneWay=(self.rtt or 0)/2
 local input=if self.config.pingCompensation then self.actualOneWay else 0
 self.predictor:setPing(input,t);self.autoPredictor:setPing(input,t);self.manualPredictor:setPing(input,t)
end
function Session:_observe(t)
 local present={}
 if self.config.targetMode=="Simulated" then
  self:_createTargets()
  local stamp=t-self.actualOneWay-self.config.simulatedObservationDelaySeconds
  for _, spec in self.specs do
   spec.part.Transparency=0
   local current=positionAt(spec,t);spec.part.Position=current
   local p,v,state=positionAt(spec,stamp)
   local sample={t=stamp,position=p,velocity=v,state=state}
   self.targets[spec.id]={sample=sample,current=current,spec=spec,radius=spec.radius}
   self.predictor:observe(spec.id,sample);present[spec.id]=true
  end
 else
  for _,spec in self.specs do spec.part.Transparency=1 end
  for _,player in self.services.Players:GetPlayers() do
   if player~=self.player then
    local character=player.Character
    local root=character and character:FindFirstChild("HumanoidRootPart")
    local humanoid=character and character:FindFirstChildOfClass("Humanoid")
    if root and root:IsA("BasePart") and humanoid and humanoid.Health>0 and root:IsDescendantOf(workspace) then
     local id="player:"..player.UserId
     -- Timestamp is local capture time, NOT authoritative replication time.
     -- Derive velocity from positions; AssemblyLinearVelocity is NotReplicated.
     local sample={t=t,position=root.Position,state=humanoid:GetState().Name}
     if vecOK(sample.position) then
      self.targets[id]={sample=sample,current=root.Position,model=character,radius=2}
      self.predictor:observe(id,sample);present[id]=true
     end
    end
   end
  end
 end
 for id in self.targets do
  if not present[id] then self.targets[id]=nil;self.predictor:forget(id) end
 end
end
function Session:_params(excludeCharacters)
 local p=RaycastParams.new();p.FilterType=Enum.RaycastFilterType.Exclude
 local exclusions={self.world}
 if self.player.Character then table.insert(exclusions,self.player.Character) end
 if excludeCharacters then
  for _,target in self.targets do if target.model then table.insert(exclusions,target.model) end end
 end
 p.FilterDescendantsInstances=exclusions;p.IgnoreWater=true
 return p
end
function Session:_select(t)
 local origin=self:_origin();local camera=workspace.CurrentCamera
 if not self.config.core.enabled or not camera or not origin then self.selected=nil;self.solution=nil;return end
 if not self.ui:isPointerOver() and not self.services.UserInputService:GetFocusedTextBox() then
  self.selectionMouse=self.services.UserInputService:GetMouseLocation()
 end
 local viewportMouse=self.selectionMouse-self.services.GuiService:GetGuiInset()
 local params=self:_params(true)
 local function valid(id)
  local target=self.targets[id]
  if not target or t-target.sample.t>self.config.core.staleAfterSeconds then return nil end
  local distance=(target.sample.position-origin).Magnitude
  if distance>math.min(MAX_RANGE,self.config.core.maxTargetDistanceStuds) then return nil end
  local point,onScreen=camera:WorldToViewportPoint(target.current)
  if not onScreen or point.Z<=0 then return nil end
  local pixels=(Vector2.new(point.X,point.Y)-viewportMouse).Magnitude
  if pixels>self.config.core.fovPixels then return nil end
  local delta=target.current-camera.CFrame.Position
  local obstacle=workspace:Raycast(camera.CFrame.Position,delta,params)
  if obstacle and obstacle.Distance<delta.Magnitude-0.25 then return nil end
  return pixels
 end
 if not self.selected or not valid(self.selected) then
  self.selected=nil;self.drawPoint=nil
  local best=math.huge
  for id in self.targets do
   local pixels=valid(id)
   if pixels and pixels<best then best=pixels;self.selected=id end
  end
 end
 if self.selected then
  local target=self.targets[self.selected]
  local distance=(target.sample.position-origin).Magnitude
  Configuration.prepareCore(self.config,distance)
  self.profile=Configuration.getProfile(self.config,distance)
  copyCore(self.config.core,self.autoCore);self.autoCore.autoPrediction=true
  copyCore(self.config.core,self.manualCore);self.manualCore.autoPrediction=false
  self.solution=self.predictor:predict(self.selected,origin,t,self.profile)
 else self.solution=nil end
end
function Session:_queueMeasurements(t)
 if not self.selected or not self.solution or self.config.targetMode~="Simulated" or #self.pending>MAX_PENDING-3 then return end
 local target=self.targets[self.selected]
 local origin=self:_origin()
 if not target or not target.spec or not origin then return end
 local mode=if self.config.core.autoPrediction then "auto" else "manual"
 for _,pair in {{self.predictor,mode,true},{self.autoPredictor,"auto",false},{self.manualPredictor,"manual",false}} do
  local result=pair[1]:predict(self.selected,origin,t,self.profile)
  if result then
   -- The reference time comes from the MODEL'S actual transport delay, not
   -- the configured prediction delay; incorrect offsets therefore cause error.
   local due=t+self.actualOneWay+result.flightSeconds
   table.insert(self.pending,{due=due,created=t,spec=target.spec,result=result,
    weapon=self.config.activeProfile,range=result.range,mode=pair[2],primary=pair[3]})
  end
 end
end
function Session:_measure(t)
 for i=#self.pending,1,-1 do
  local m=self.pending[i]
  if m.due<=t then
   local truth,velocity,state=positionAt(m.spec,m.due)
   local residual=truth-m.result.targetPosition
   local record={type="prediction",weapon=m.weapon,range=m.range,mode=m.mode,
    errorStuds=residual.Magnitude,sampleTime=m.result.sampleTime,impactTime=m.due,now=t}
   if m.primary then self.lastError=record.errorStuds;self.diagnostics:recordPrediction(record)
   else
    local v=m.result.velocity
    -- Exclude state transitions/turns from latency training, while retaining
    -- their errors in the RMSE comparison. Otherwise motion error becomes bias.
    local stable=state==m.result.state and v.Magnitude>2 and velocity.Magnitude>2
      and v:Dot(velocity)/(v.Magnitude*velocity.Magnitude)>0.85
    record.residual=residual;record.velocity=if stable then v else v*0
    self.calibration:record(record)
   end
   table.remove(self.pending,i)
  end
 end
end
function Session:_applyCalibration(automatic,t)
 if not self.solution or self.config.targetMode~="Simulated" then return false,"Calibración requiere verdad del blanco simulado" end
 if automatic and not self.config.core.autoPrediction then return false,"Modo manual activo" end
 local range=self.solution.range
 local correction,count=self.calibration:suggest(self.config.activeProfile,range,t)
 if count<20 then return false,"Se requieren 20 mediciones automáticas de movimiento estable" end
 local profile=self.config.profiles[self.config.activeProfile]
 local step=math.clamp(correction,-0.002,0.002) -- at most 2 ms per application
 local previous=profile.rangeOffsets[range]
 profile.rangeOffsets[range]=math.clamp(previous+step,-0.15,0.15)
 self.ui:setConfig(self.config)
 local message=string.format("Corrección gradual: %+.1f ms (%s)",step*1000,range)
 if not automatic then self.ui:setStatus(message) end
 self.lastCalibration=t
 return true,message
end
function Session:_trace(origin,to,t)
 if (to-origin).Magnitude<0.01 then return end
 local p=self:_part("LocalShotTrace",Vector3.new(0.05,0.05,(to-origin).Magnitude),Color3.fromRGB(81,159,255))
 p.CFrame=CFrame.lookAt((origin+to)/2,to)
 table.insert(self.effects,{part=p,due=t+0.12})
end
function Session:fire()
 if self.destroyed or self.paused or not self.config.core.enabled then return end
 local t=now();self:_select(t)
 local origin=self:_origin();local target=self.selected and self.targets[self.selected]
 if not origin or not target or not self.solution then self.ui:setStatus("Selecciona un blanco visible dentro del FOV",true);return end
 local profile=Configuration.getProfile(self.config,self.solution.distanceStuds)
 if profile.kind=="projectile" and profile.radius>0 and not self.compatibility.capabilities.spherecast then
  self.ui:setStatus("Spherecast no disponible: el tiro con radio no puede comprobarse. Usa radio 0 para raycast.",true);return
 end
 if t<self.nextFire then return end
 local prediction=self.predictor:predict(self.selected,origin,t,profile)
 if not prediction or (prediction.position-origin).Magnitude<0.001 then return end
 if #self.shots>=16 or #self.projectiles+#self.shots>=MAX_PROJECTILES then self.ui:setStatus("Límite de tiros locales en vuelo",true);return end
 self.nextFire=t+profile.cooldown
 local direction=(prediction.position-origin).Unit
 if profile.spreadRadians>0 then
  local axis=if math.abs(direction.Y)>0.95 then Vector3.xAxis else Vector3.yAxis
  local right=direction:Cross(axis).Unit;local up=right:Cross(direction).Unit
  local cosine=1-self.random:NextNumber()*(1-math.cos(profile.spreadRadians))
  local sine=math.sqrt(math.max(0,1-cosine*cosine));local angle=self.random:NextNumber(0,2*math.pi)
  direction=(direction*cosine+(right*math.cos(angle)+up*math.sin(angle))*sine).Unit
 end
 table.insert(self.shots,{due=t+self.actualOneWay,origin=origin,direction=direction,
  profile=profile,weapon=self.config.activeProfile,id=self.selected,target=target,mode=self.config.targetMode})
 self.ui:setStatus("Disparo local de laboratorio; sin daño ni evento de arma")
end
function Session:_finishShot(shot,hit,miss,t,reason)
 self.diagnostics:recordShot({type="shot",weapon=shot.weapon,targetId=shot.id,hit=hit,intendedHit=hit,
  accepted=true,missDistanceStuds=if shot.mode=="Simulated" then miss else nil,flightSeconds=t-(shot.started or shot.due),reason=reason,
  spreadRadians=shot.profile.spreadRadians,scope="local laboratory",impactTime=t})
 self.lastShot=if hit then "Impacto local al blanco elegido" else "Fallo local: "..reason
end
function Session:_startShots(t)
 for i=#self.shots,1,-1 do
  local shot=self.shots[i]
  if shot.due<=t then
   if shot.profile.kind=="projectile" then
    shot.started=shot.due;shot.processed=shot.due;shot.closest=math.huge
    shot.part=self:_part("LocalProjectile",Vector3.new(0.35,0.35,0.35),Color3.fromRGB(255,198,92))
    shot.part.Shape=Enum.PartType.Ball;shot.part.Position=shot.origin
    shot.lifetime=math.min(self.config.core.maxFlightSeconds,MAX_RANGE/shot.profile.speed)
    shot.params=self:_params(false)
    table.insert(self.projectiles,shot)
   else
    local endpoint=shot.origin+shot.direction*MAX_RANGE
    local obstacle=workspace:Raycast(shot.origin,endpoint-shot.origin,self:_params(shot.mode=="Simulated"))
    if obstacle then endpoint=obstacle.Position end
    local chosen=nil;local nearest=1.1
    if shot.mode=="Simulated" then
     for _,spec in self.specs do
      local pos=positionAt(spec,shot.due)
      local fraction=Geometry.sphereIntersection(shot.origin-pos,endpoint-pos,spec.radius)
      if fraction and fraction<nearest then nearest=fraction;chosen=spec end
     end
    end
    local position=if shot.target.spec then positionAt(shot.target.spec,shot.due) else shot.target.current
    local _,closest=Geometry.closestOnSegment(position,shot.origin,endpoint)
    local hit=if shot.mode=="Simulated" then chosen and chosen.id==shot.id
      else obstacle and shot.target.model and obstacle.Instance:IsDescendantOf(shot.target.model)
    if chosen then endpoint=shot.origin+(endpoint-shot.origin)*nearest end
    self:_trace(shot.origin,endpoint,t)
    self:_finishShot(shot,hit==true,math.max(0,(position-closest).Magnitude-shot.target.radius),shot.due,
     if hit then "local-hit" elseif obstacle then "obstacle" else "miss")
   end
   table.remove(self.shots,i)
  end
 end
end
local function projectilePosition(shot,t)
 local dt=t-shot.started
 return shot.origin+shot.direction*(shot.profile.speed*dt)+Vector3.new(0,-0.5*shot.profile.gravity*dt*dt,0)
end
function Session:_advanceShots(t)
 for i=#self.projectiles,1,-1 do
  local shot=self.projectiles[i];local finished=false
  local endTime=math.min(t,shot.started+shot.lifetime);local steps=0
  while shot.processed<endTime and steps<64 do
   steps+=1
   local aTime=shot.processed;local bTime=math.min(aTime+1/120,endTime)
   local a=projectilePosition(shot,aTime);local b=projectilePosition(shot,bTime)
   local startPos=if shot.target.spec then positionAt(shot.target.spec,aTime) else shot.target.current
   local endPos=if shot.target.spec then positionAt(shot.target.spec,bTime) else shot.target.current
   local delta=b-a
   local obstacle=if delta.Magnitude>1e-8 then
    (if shot.profile.radius>0 then workspace:Spherecast(a,shot.profile.radius,delta,shot.params)
     else workspace:Raycast(a,delta,shot.params)) else nil
   local fraction,closest=Geometry.closestOnSegment(Vector3.zero,a-startPos,b-endPos)
   local contact,hitTargetId=nil,nil
   if shot.mode=="Simulated" then
    for _,spec in self.specs do
     local pa=positionAt(spec,aTime);local pb=positionAt(spec,bTime)
     local candidate=Geometry.sphereIntersection(a-pa,b-pb,spec.radius+shot.profile.radius)
     if candidate and (not contact or candidate<contact) then contact=candidate;hitTargetId=spec.id end
    end
   end
   local obstacleFraction=if obstacle then obstacle.Distance/delta.Magnitude else 1.1
   local stop=math.min(1,contact or 1.1,obstacleFraction)
   fraction=math.min(fraction,stop)
   closest=(a-startPos):Lerp(b-endPos,fraction)
   shot.closest=math.min(shot.closest,math.max(0,closest.Magnitude-shot.target.radius-shot.profile.radius))
   if obstacle and obstacleFraction<=(contact or 1.1) then
    local hit=shot.mode=="OwnCharacters" and shot.target.model and obstacle.Instance:IsDescendantOf(shot.target.model)
    self:_finishShot(shot,hit==true,shot.closest,aTime+(bTime-aTime)*stop,if hit then "local-hit" else "obstacle")
    finished=true;break
   elseif contact then
    local hit=hitTargetId==shot.id
    self:_finishShot(shot,hit,if hit then 0 else shot.closest,aTime+(bTime-aTime)*contact,if hit then "local-hit" else "other-target")
    finished=true;break
   end
   shot.processed=bTime;shot.part.Position=b
  end
  if not finished and shot.processed>=shot.started+shot.lifetime then
   self:_finishShot(shot,false,shot.closest,shot.processed,"flight-limit");finished=true
  end
  if finished then shot.part:Destroy();table.remove(self.projectiles,i) end
 end
end
function Session:_metrics()
 local result=self.solution;local target=self.selected and self.targets[self.selected]
 local range=if result then result.range else "close"
 local calibration=self.calibration:summary(self.config.activeProfile,range,now())
 local stats=self.diagnostics:summary()
 local live={rtt=if self.rtt then string.format("%.1f ms (%s)",self.rtt*1000,if self.config.useSimulatedPing then "simulado" else "motor") else "No disponible",
  ping=string.format("%.1f / %.1f ms",self.predictor.latency.raw*1000,self.predictor.latency.smoothed*1000),
  delay="—",speed="—",distance="—",range=range,current="—",predicted="—",aimpoint="—",error=if self.lastError then string.format("%.3f studs",self.lastError) else "Sin verdad medida",
  status=if self.config.targetMode=="Simulated" then "SIMULACIÓN LOCAL · referencia conocida" else "OBSERVACIÓN LOCAL · sin verdad autoritativa",
  target=self.selected or "Sin blanco",weapon=self.config.activeProfile,flight="—",
  autoRMSE=if calibration.autoCount>0 then string.format("%.3f studs (%d)",calibration.autoRMSEStuds,calibration.autoCount) else "Sin muestras",
  manualRMSE=if calibration.manualCount>0 then string.format("%.3f studs (%d)",calibration.manualRMSEStuds,calibration.manualCount) else "Sin muestras",
  measurementCount=tostring(stats.predictionCount),hitRate=string.format("%.1f%% (%d tiros locales)",stats.hitRate*100,stats.shots),
  suggestion=string.format("%+.1f ms (%d válidas)",calibration.suggestedOffsetSeconds*1000,calibration.confidenceSamples)}
 if result then
  live.delay=string.format("%.1f ms",result.delaySeconds*1000);live.speed=string.format("%.1f studs/s",result.velocity.Magnitude)
  live.distance=string.format("%.1f studs",result.distanceStuds);live.flight=string.format("%.3f s",result.flightSeconds)
  live.predicted=string.format("%.1f, %.1f, %.1f",result.targetPosition.X,result.targetPosition.Y,result.targetPosition.Z)
  live.aimpoint=string.format("%.1f, %.1f, %.1f",result.position.X,result.position.Y,result.position.Z)
 end
 if target then local p=target.sample.position;live.current=string.format("%.1f, %.1f, %.1f",p.X,p.Y,p.Z) end
 if self.compatibility and #self.compatibility.warnings>0 then live.status ..= " · " .. table.concat(self.compatibility.warnings," ") end
 self.ui:update(live)
end
function Session:step(dt,t)
 if self.destroyed then return end
 self:_ping(t);self:_measure(t);self:_startShots(t);self:_advanceShots(t)
 for i=#self.effects,1,-1 do if self.effects[i].due<=t then self.effects[i].part:Destroy();table.remove(self.effects,i) end end
 self.observeAccumulator+=dt;self.measureAccumulator+=dt;self.uiAccumulator+=dt
 if self.observeAccumulator>=1/self.config.core.updateHz then
  self.observeAccumulator%=1/self.config.core.updateHz;self:_observe(t);self:_select(t)
 end
 if self.measureAccumulator>=MEASUREMENT_INTERVAL then self.measureAccumulator%=MEASUREMENT_INTERVAL;self:_queueMeasurements(t) end
 if self.config.adaptiveCalibration and t-self.lastCalibration>=1 then
  self.lastCalibration=t;self:_applyCalibration(true,t)
 end
 if self.uiAccumulator>=0.1 then self.uiAccumulator%=0.1;self:_metrics() end
 local solution=self.solution;local camera=workspace.CurrentCamera
 if self.selectionRing then
  self.selectionRing.Visible=self.config.core.enabled
  self.selectionRing.Position=UDim2.fromOffset(self.selectionMouse.X,self.selectionMouse.Y)
  self.selectionRing.Size=UDim2.fromOffset(self.config.core.fovPixels*2,self.config.core.fovPixels*2)
 end
 local visible=self.config.core.enabled and self.config.core.debugVisualization and solution~=nil
 self.currentMarker.Transparency=if visible then 0.5 else 1
 self.predictedMarker.Transparency=if visible then 0.2 else 1
 if solution then
  local tau=self.config.predictionSmoothingSeconds
  local alpha=if tau>0 then 1-math.exp(-dt/tau) else 1
  self.drawPoint=if self.drawPoint then self.drawPoint:Lerp(solution.position,alpha) else solution.position
  self.predictedMarker.Position=self.drawPoint
  local target=self.targets[self.selected]
  if target then self.currentMarker.Position=target.current end
  if self.rightMouse and self.config.core.enabled and camera and not self.ui:isPointerOver() and not self.services.UserInputService:GetFocusedTextBox() then
   local desired=CFrame.lookAt(camera.CFrame.Position,self.drawPoint)
   camera.CFrame=camera.CFrame:Lerp(desired,1-math.exp(-dt/math.max(0.01,tau)))
  end
 end
end
function Session:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.rightMouse=false
 for _,c in self.connections do c:Disconnect() end
 table.clear(self.connections);table.clear(self.pending);table.clear(self.shots);table.clear(self.projectiles);table.clear(self.effects)
 if self.predictor then self.predictor:clear() end
 if self.diagnostics then self.diagnostics:clear() end
 if self.calibration then self.calibration:clear() end
 if self.ui then self.ui:destroy() end
 if self.world then self.world:Destroy() end
end
function Session.init(options)
 options=options or {}
 local compatibility=Runtime.check()
 assert(compatibility.ready,Runtime.errorMessage(compatibility))
 local run=compatibility.services.RunService
 local players=compatibility.services.Players;local player=compatibility.player
 local config,message
 if options.configuration then config,message=Configuration.import(options.configuration) else config=Configuration.new() end
 assert(config,message or "Configuración inválida")
 local pg=compatibility.playerGui
 local previous=pg:FindFirstChild("DHPredictionLab")
 local self=setmetatable({config=config,player=player,compatibility=compatibility,connections={},specs={},pending={},shots={},projectiles={},effects={},
  diagnostics=Diagnostics.new(600),calibration=Calibration.new(),destroyed=false,paused=false,rightMouse=false,
  actualOneWay=0,rtt=nil,nextFire=0,lastCalibration=-math.huge,observeAccumulator=0,measureAccumulator=0,uiAccumulator=0,
  selectionMouse=game:GetService("UserInputService"):GetMouseLocation(),random=Random.new(),
  services={Players=players,UserInputService=game:GetService("UserInputService"),GuiService=game:GetService("GuiService"),HttpService=game:GetService("HttpService")}},Session)
 local built,failure=pcall(function()
 self:_newPredictors()
 self.world=Instance.new("Folder");self.world.Name="DHPredictionLabLocal";self.world.Parent=workspace
 self.currentMarker=self:_part("CurrentPosition",Vector3.new(0.5,0.5,0.5),Color3.fromRGB(89,215,214));self.currentMarker.Shape=Enum.PartType.Ball;self.currentMarker.Transparency=1
 self.predictedMarker=self:_part("PredictedPosition",Vector3.new(0.65,0.65,0.65),Color3.fromRGB(73,148,255));self.predictedMarker.Shape=Enum.PartType.Ball;self.predictedMarker.Transparency=1
 self.ui=Interface.new(config,{
  onChange=function(path,value) return self:_change(path,value) end,
  onFire=function() self:fire() end,
  onApplyCalibration=function() return self:_applyCalibration(false,now()) end,
  onSave=function()
   local envelope,msg=Configuration.toEnvelope(self.config)
   if not envelope then return nil,msg end
   return self.services.HttpService:JSONEncode(envelope)
  end,
  onLoad=function(text)
   if #text>65536 then return false,"JSON supera 64 KiB" end
   local ok,decoded=pcall(function() return self.services.HttpService:JSONDecode(text) end)
   if not ok then return false,"JSON inválido" end
   local loaded,msg=Configuration.fromEnvelope(decoded)
   if not loaded then return false,msg end
   self:_replaceConfig(loaded);return true
  end,
  onReset=function() self:_replaceConfig(Configuration.new());self.ui:setStatus("Defaults restaurados") end,
  onUnload=function() self:destroy() end,
  onClearMeasurements=function()
   self:_clearMeasurements()
   self.ui:setStatus("Nueva ventana de medición")
  end,
  onExportMeasurements=function()
   local records={}
   table.insert(records,self.services.HttpService:JSONEncode({configuration=Configuration.toEnvelope(self.config),summary=self.diagnostics:summary(),scope="local laboratory"}))
   for _,record in self.diagnostics.predictions do table.insert(records,self.services.HttpService:JSONEncode(record)) end
   for _,record in self.diagnostics.shots do table.insert(records,self.services.HttpService:JSONEncode(record)) end
   return table.concat(records,"\n")
  end,
 })
 self.selectionRing=Instance.new("Frame");self.selectionRing.Name="SelectionFOV"
 self.selectionRing.BackgroundTransparency=1;self.selectionRing.AnchorPoint=Vector2.new(0.5,0.5)
 self.selectionRing.ZIndex=0;self.selectionRing.Parent=self.ui.gui
 local round=Instance.new("UICorner");round.CornerRadius=UDim.new(1,0);round.Parent=self.selectionRing
 local outline=Instance.new("UIStroke");outline.Color=Color3.fromRGB(69,139,245);outline.Thickness=1
 outline.Transparency=0.55;outline.Parent=self.selectionRing
 local stop=self.ui.gui:FindFirstChild("DHPredictionLabStop")
 if stop then connection(self,stop.Event,function() self:destroy() end) end
 connection(self,self.ui.gui.Destroying,function() self:destroy() end)
 local ownerOK,owner=pcall(function()
  return script and script:IsA("LocalScript") and script.Destroying or nil
 end)
 if ownerOK and owner then connection(self,owner,function() self:destroy() end) end
 connection(self,self.services.UserInputService.InputBegan,function(input,processed)
  if processed or self.services.UserInputService:GetFocusedTextBox() or self.ui:isPointerOver() then return end
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self.rightMouse=true
  elseif input.KeyCode==Enum.KeyCode.F then self:fire() end
 end)
 connection(self,self.services.UserInputService.InputEnded,function(input)
  if input.UserInputType==Enum.UserInputType.MouseButton2 then self.rightMouse=false end
 end)
 connection(self,self.services.UserInputService.WindowFocusReleased,function() self.rightMouse=false end)
 connection(self,run.RenderStepped,function(dt)
  if self.destroyed or self.paused then return end
  local ok,message=pcall(function() self:step(dt,now()) end)
  if not ok then
   self.paused=true;self.rightMouse=false
   local text="Pausado por incompatibilidad: "..tostring(message)..". Revisa el cliente o usa Unload."
   -- Avoid repeating the layout/camera operation that may have failed. A fault
   -- while displaying the error must not escape or restart frame updates.
   pcall(function()
    self.currentMarker.Transparency=1;self.predictedMarker.Transparency=1;self.selectionRing.Visible=false
    self.ui:setStatus(text,true)
    for _,label in self.ui.metrics.status or {} do label.Text=text end
   end)
   Runtime.reportFailure(text)
  end
 end)
 self.ui:setStatus("Laboratorio local listo · F dispara · RMB orienta cámara")
 end)
 if not built then self:destroy();error("Inicialización: "..tostring(failure),2) end
 -- Commit ownership only after a complete constructor; failed builds leave the
 -- existing session usable, and remove their own partial objects/connections.
 if previous then
  local stop=previous:FindFirstChild("DHPredictionLabStop")
  if stop and stop:IsA("BindableEvent") then stop:Fire() end
  previous:Destroy()
 end
 return self
end
return Session
end
-- END Session
local Modules = setmetatable({}, {__index=function(_, name) return loadModule(name) end})
local API = {Modules=Modules, getModule=loadModule}
function API.checkCompatibility() return loadModule("Runtime").check() end
function API.tryInit(options)
 local report = API.checkCompatibility()
 API.compatibility = report
 if not report.ready then return nil, report end
 local ok, session = pcall(function() return loadModule("Session").init(options) end)
 if not ok then
  report.ready = false
  table.insert(report.missing, "Inicializacion: " .. tostring(session))
  return nil, report
 end
 API.session = session
 return session, report
end
function API.init(options)
 local session, report = API.tryInit(options)
 if not session then error(loadModule("Runtime").errorMessage(report), 2) end
 return session
end
-- Pure Luau CLI can import the mathematical modules; Roblox auto-starts once.
if game and not DHPREDICTION_NO_AUTOSTART then
 local session, report = API.tryInit({configuration=INITIAL_CONFIGURATION})
 if not session then loadModule("Runtime").reportFailure(loadModule("Runtime").errorMessage(report)) end
end
return API
