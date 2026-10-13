--!nonstrict
-- Optional experiments. Default Memory bypasses this stage: no stacked filter.
local MotionFilter={};MotionFilter.__index=MotionFilter
function MotionFilter.new(config) return setmetatable({config=config},MotionFilter) end
function MotionFilter:reset() self.position=nil;self.time=nil;self.velocity=nil;self.raw=nil;self.derivative=nil end
function MotionFilter:observe(t,p,state)
 local c=self.config;local dt=self.time and t-self.time
 if c.MotionFilter=="Memory" then return p end
 if not dt or dt<=0 or dt>c.StaleAfter or state~=self.state
  or (p-self.raw).Magnitude>c.MaxObservedSpeed*dt+c.TeleportSlack
  or (self.velocity and ((p-self.raw):Dot(self.velocity)<0 or ((p.X-self.raw.X)*self.velocity.X+(p.Z-self.raw.Z)*self.velocity.Z<0))) then
  self.position=p;self.velocity=p*0;self.derivative=p*0
 else
  local rawVelocity=(p-self.raw)/dt
  if c.MotionFilter=="AlphaBeta" then
   local estimate=self.position+self.velocity*dt;local residual=p-estimate
   self.position=estimate+residual*c.AlphaBetaAlpha
   self.velocity+=residual*(c.AlphaBetaBeta/dt)
  else
   local da=1-math.exp(-2*math.pi*dt)
   self.derivative+=(rawVelocity-self.derivative)*da
   local cutoff=c.FilterMinCutoff+c.FilterBeta*self.derivative.Magnitude
   local a=1-math.exp(-2*math.pi*cutoff*dt)
   self.position+=(p-self.position)*a;self.velocity=rawVelocity
  end
 end
 self.raw=p;self.time=t;self.state=state
 return self.position
end
return MotionFilter
