--!nonstrict
-- Reads positions of a REAL server-owned physical Part in native wiring.
-- Sweeps each observed segment through Workspace:Raycast; no analytic target
-- proximity or predicted positions manufacture a collision.
local ProjectileTracker={}
ProjectileTracker.__index=ProjectileTracker
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v)
 local ok,x,y,z=pcall(function() return v.X,v.Y,v.Z end)
 return ok and finite(x) and finite(y) and finite(z)
end
function ProjectileTracker.new(options)
 for _,name in {"clock","getPosition","raycast","onComplete","dispose"} do assert(type(options[name])=="function",name.." callback required") end
 assert(vector(options.origin) and finite(options.range) and options.range>0 and finite(options.lifetime) and options.lifetime>0,"Invalid projectile limits")
 local started=options.clock()
 assert(finite(started),"Invalid projectile clock")
 return setmetatable({options=options,last=options.origin,started=started,traveled=0,done=false},ProjectileTracker)
end
function ProjectileTracker:_finish(result,reason,position)
 if self.done then return end
 self.done=true
 local options=self.options
 -- Remove the physical resource before a callback can re-enter this tracker.
 local disposed,disposeError=pcall(options.dispose)
 local completed,completionError=pcall(options.onComplete,result,reason,position,self.traveled)
 self.options=nil
 if not disposed then error("Projectile cleanup failed: "..tostring(disposeError)) end
 if not completed then error("Projectile completion failed: "..tostring(completionError)) end
end
function ProjectileTracker:step(now)
 if self.done then return end
 local options=self.options
 now=now or options.clock()
 if not finite(now) or now<self.started then self:_finish(nil,"invalid-clock",self.last);return end
 local ok,current=pcall(options.getPosition)
 if not ok or not vector(current) then self:_finish(nil,"projectile-lost",self.last);return end
 local delta=current-self.last
 local length=delta.Magnitude
 if not finite(length) then self:_finish(nil,"invalid-projectile-position",self.last);return end
 if length>0 then
  local distance=math.min(length,math.max(0,options.range-self.traveled))
  local direction=delta/length*distance
  local hitOK,hit=pcall(options.raycast,self.last,direction)
  if not hitOK then self:_finish(nil,"raycast-error: "..tostring(hit),self.last);return end
  self.traveled+=distance
  local endPosition=self.last+direction
  if hit then self:_finish(hit,"impact",endPosition);return end
  self.last=endPosition
  if self.traveled>=options.range then self:_finish(nil,"range-expired",self.last);return end
 end
 if now-self.started>=options.lifetime then self:_finish(nil,"lifetime-expired",self.last) end
end
function ProjectileTracker:cancel()
 if self.done then return end
 self.done=true
 local options=self.options;self.options=nil
 options.dispose()
end
return ProjectileTracker
