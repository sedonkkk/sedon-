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
