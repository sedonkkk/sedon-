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
