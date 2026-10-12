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
