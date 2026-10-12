--!nonstrict
local Latency=if script then require(script.Parent.Latency) else require("./Latency")
local MotionHistory=if script then require(script.Parent.MotionHistory) else require("./MotionHistory")
local Ballistics=if script then require(script.Parent.Ballistics) else require("./Ballistics")
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
