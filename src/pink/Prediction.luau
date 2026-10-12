--!nonstrict
-- X/Z use PredictionX seconds; Y uses PredictionY seconds. These configurable
-- references are empirical horizons, not universal properties of a weapon.
-- Auto references already contain the requested delay: RTT is NEVER added
-- again. Only the independently known observation age is integrated once.
local Config = if script then require(script.Parent.Config) else require("./Config")
local MotionHistory = if script then require(script.Parent.Parent.shared.MotionHistory) else require("../shared/MotionHistory")
local Latency = if script then require(script.Parent.Parent.shared.Latency) else require("../shared/Latency")
local Ballistics = if script then require(script.Parent.Parent.shared.Ballistics) else require("../shared/Ballistics")
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
