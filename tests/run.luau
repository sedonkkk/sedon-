--!nonstrict
-- Run from any directory: luau /workspace/sedon-/tests/run.luau
-- Pure numerical tests. They do not simulate replication, Roblox raycasts,
-- character animation, server authority, or third-party weapon properties.
local V=require("./Vector")
local Settings=require("../src/shared/Settings")
local Latency=require("../src/shared/Latency")
local MotionHistory=require("../src/shared/MotionHistory")
local Ballistics=require("../src/shared/Ballistics")
local Geometry=require("../src/shared/Geometry")
local Predictor=require("../src/shared/Predictor")
local Weapons=require("../src/shared/Weapons")
local Diagnostics=require("../src/shared/Diagnostics")
local zero=V.new(0,0,0)
local tests,failures,checks=0,0,0
local function check(condition,message)
 checks+=1
 assert(condition,message or "assertion failed")
end
local function near(actual,expected,tolerance,message)
 check(type(actual)=="number" and actual==actual and math.abs(actual-expected)<=(tolerance or 1e-8),
  (message or "numeric mismatch")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function vectorNear(actual,expected,tolerance,message)
 check(actual~=nil and (actual-expected).Magnitude<=(tolerance or 1e-7),
  (message or "vector mismatch")..": expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name,body)
 tests+=1
 local ok,err=pcall(body)
 if not ok then failures+=1;print("FAIL "..name..": "..tostring(err)) end
end
local function sample(t,position,velocity,state)
 return {t=t,position=position,velocity=velocity,state=state or "Walking"}
end
local function track(settings,position,velocity,t,ping)
 local p=Predictor.new(settings)
 check(p:setPing(ping or 0.03,t or 0))
 check(p:observe("target",sample(t or 0,position,velocity)))
 return p
end

test("default settings validate and calibration copies are independent",function()
 local a,b=Settings.new(),Settings.new()
 check(Settings.validate(a))
 a.pingCalibration[1].offsetSeconds=0.1
 near(b.pingCalibration[1].offsetSeconds,0)
 a.weaponOffsets.RevolverLab=0.02
 near(b.weaponOffsets.RevolverLab,0)
 check(Weapons.get("RevolverLab").kind=="hitscan")
 check(Weapons.get("ProjectileLab").kind=="projectile")
 check(Weapons.get("unrecognized")==nil)
end)
test("settings reject nonfinite numbers and inconsistent ranges",function()
 for _,bad in {0/0,math.huge,-math.huge,-1} do
  local s=Settings.new();s.manualDelaySeconds=bad;check(not Settings.validate(s))
 end
 local s=Settings.new();s.minDelaySeconds=0.3;s.maxDelaySeconds=0.2;check(not Settings.validate(s))
 s=Settings.new();s.historyCapacity=2.5;check(not Settings.validate(s))
 s=Settings.new();s.velocityPrediction="true";check(not Settings.validate(s))
 s=Settings.new();s.pingCalibration[2].pingSeconds=s.pingCalibration[1].pingSeconds;check(not Settings.validate(s))
 s=Settings.new();s.pingCalibration[1].offsetSeconds=0/0;check(not Settings.validate(s))
 s=Settings.new();s.weaponOffsets.ProjectileLab=0/0;check(not Settings.validate(s))
 s=Settings.new();s.weaponOffsets.RevolverLab=math.huge;check(not Settings.validate(s))
end)
test("ping samples reject nonfinite values and nonmonotonic timestamps",function()
 local l=Latency.new(Settings.new())
 check(l:sample(0.03,1))
 for _,bad in {0/0,math.huge,-math.huge,-0.01,1.01} do check(not l:sample(bad,2)) end
 check(not l:sample(0.05,0/0))
 check(not l:sample(0.05,math.huge))
 check(not l:sample(0.05,1));check(not l:sample(0.05,0.9))
 near(l.raw,0.03);near(l.lastTime,1)
end)
test("ping EMA uses elapsed time independently of sample frequency",function()
 local s=Settings.new();s.pingSmoothingSeconds=0.8
 local fast,slow=Latency.new(s),Latency.new(s)
 check(fast:sample(0.004,0));check(slow:sample(0.004,0))
 for i=1,100 do check(fast:sample(0.09,i/100)) end
 for i=1,10 do check(slow:sample(0.09,i/10)) end
 local expected=0.09+(0.004-0.09)*math.exp(-1/0.8)
 near(fast.smoothed,expected,1e-12);near(slow.smoothed,expected,1e-12)
end)
test("calibration interpolates one-way seconds and saturates endpoints",function()
 local s=Settings.new()
 s.pingCalibration={{pingSeconds=0.004,offsetSeconds=-0.001},{pingSeconds=0.09,offsetSeconds=0.02}}
 local l=Latency.new(s)
 near(l:calibrationOffset(0),-0.001)
 near(l:calibrationOffset(0.047),0.0095)
 near(l:calibrationOffset(1),0.02)
 check(l:sample(0.047,0))
 near(l:estimate(0,0.003),0.0595)
end)
test("latency delay is clamped and slew is bounded in seconds per second",function()
 local s=Settings.new();s.pingSmoothingSeconds=0.05;s.latencySlewSecondsPerSecond=0.12
 local l=Latency.new(s);check(l:sample(0.01,0));near(l:estimate(0,0),0.01)
 check(l:sample(0.3,1));near(l:estimate(1,0),0.13)
 local previous=l.delay
 local nextDelay=l:estimate(1.01,0)
 check(math.abs(nextDelay-previous)<=0.12*0.01+1e-12)
 near(l:estimate(1.01,0),nextDelay)
 local high=Latency.new(s);check(high:sample(0.9,0));near(high:estimate(0,0),s.maxDelaySeconds)
 local low=Latency.new(s);check(low:sample(0.004,0));near(low:estimate(0,-0.2),s.minDelaySeconds)
end)
test("manual delay stays fixed despite changing ping",function()
 local s=Settings.new();s.autoPrediction=false;s.manualDelaySeconds=0.123
 local l=Latency.new(s)
 check(l:sample(0.004,0));near(l:estimate(0,0),0.123)
 check(l:sample(0.09,1));near(l:estimate(1,0),0.123)
end)
test("history rejects malformed or nonfinite data and preserves last valid sample",function()
 local h=MotionHistory.new(Settings.new())
 check(h:observe(sample(0,zero,V.new(10,0,0))))
 check(not h:observe(sample(0/0,zero,zero)))
 check(not h:observe(sample(1,V.new(0/0,0,0),zero)))
 check(not h:observe(sample(1,V.new(0,math.huge,0),zero)))
 check(not h:observe(sample(1,zero,V.new(0,0,-math.huge))))
 check(not h:observe({t=1,position={},state="Walking"}))
 check(not h:observe(sample(1,7,zero)))
 check(not h:observe(sample(1,zero,8)))
 near(h:latest().t,0)
end)
test("history ignores duplicate and out-of-order observations",function()
 local h=MotionHistory.new(Settings.new())
 check(h:observe(sample(1,V.new(10,0,0),V.new(10,0,0))))
 check(not h:observe(sample(1,V.new(100,0,0),V.new(10,0,0))))
 check(not h:observe(sample(0.9,V.new(0,0,0),V.new(10,0,0))))
 near(h.rejected,2);near(#h.samples,1);vectorNear(h:latest().position,V.new(10,0,0))
end)
test("history capacity and time window stay bounded",function()
 local s=Settings.new();s.historyCapacity=5;s.historyWindowSeconds=0.1
 local h=MotionHistory.new(s)
 for i=0,120 do
  check(h:observe(sample(i/60,V.new(i/6,0,0),V.new(10,0,0))))
  check(#h.samples<=5)
  check(#h.samples<=2 or h:latest().t-h.samples[1].t<=0.1+1e-12)
 end
 vectorNear(h.velocity,V.new(10,0,0));vectorNear(h.acceleration,zero)
end)
test("state changes and reversals rebase velocity and clear acceleration",function()
 local h=MotionHistory.new(Settings.new())
 check(h:observe(sample(0,zero,V.new(10,0,0))))
 check(h:observe(sample(0.1,V.new(1,0,0),V.new(10,0,0),"Jumping")))
 near(h.resets,2);near(#h.samples,1);vectorNear(h.acceleration,zero)
 check(h:observe(sample(0.2,zero,V.new(-10,0,0),"Jumping")))
 near(h.resets,3);near(#h.samples,1);vectorNear(h.velocity,V.new(-10,0,0));vectorNear(h.acceleration,zero)
end)
test("horizontal jump reversal resets memory even when vertical motion dominates",function()
 local h=MotionHistory.new(Settings.new())
 check(h:observe(sample(0,zero,V.new(10,30,0),"Jumping")))
 check(h:observe(sample(0.1,V.new(1.1,3,0),V.new(12,30,0),"Jumping")))
 near(h.resets,1);check(h.acceleration.Magnitude>0)
 local reversed=V.new(-12,30,0)
 local threeDimensionalDot=h.velocity:Dot(reversed)/(h.velocity.Magnitude*reversed.Magnitude)
 check(threeDimensionalDot>0,"vertical motion should hide reversal from a 3D dot test")
 check(h:observe(sample(0.2,V.new(-0.1,6,0),reversed,"Jumping")))
 near(h.resets,2);near(#h.samples,1);vectorNear(h.velocity,reversed);vectorNear(h.acceleration,zero)
end)
test("teleports and long observation gaps rebase rather than extrapolate",function()
 local h=MotionHistory.new(Settings.new())
 check(h:observe(sample(0,zero,V.new(10,0,0))))
 check(h:observe(sample(0.1,V.new(1000,0,0),V.new(5,0,0))))
 near(h.resets,2);vectorNear(h.velocity,V.new(5,0,0));vectorNear(h.acceleration,zero)
 check(h:observe(sample(1,V.new(1001,0,0),zero)))
 near(h.resets,3);vectorNear(h.velocity,zero)
end)
test("unreasonable speeds are rejected and acceleration is capped",function()
 local s=Settings.new();local h=MotionHistory.new(s)
 check(h:observe(sample(0,zero,V.new(1,0,0))))
 check(not h:observe(sample(0.01,V.new(1.3,0,0),nil)))
 check(not h:observe(sample(0.01,V.new(0.01,0,0),V.new(121,0,0))))
 check(h:observe(sample(0.01,V.new(0.15,0,0),V.new(25,0,0))))
 check(h.acceleration.Magnitude>0 and h.acceleration.Magnitude<=s.maxAccelerationStuds)
 check(h.velocity.Magnitude<=s.maxObservedSpeedStuds)
end)
test("position-only history estimates motion and disabled memory rebases every sample",function()
 local s=Settings.new();local h=MotionHistory.new(s)
 check(h:observe(sample(0,zero,nil)))
 for i=1,20 do check(h:observe(sample(i/30,V.new(i/3,0,0),nil))) end
 near(h.velocity.X,10,0.001)
 s.memoryTracking=false
 check(h:observe(sample(21/30,V.new(7,0,0),nil)))
 near(#h.samples,1);vectorNear(h.velocity,V.new(10,0,0));vectorNear(h.acceleration,zero)
end)
test("stationary projectile flight and moving interception solve speed equation",function()
 near(Ballistics.intercept(zero,V.new(0,0,90),zero,180,2),0.5)
 local v=V.new(16,0,0);local position=V.new(0,0,100)
 local t=Ballistics.intercept(zero,position,v,180,2)
 near(t,100/math.sqrt(180^2-16^2),1e-10)
 near((position+v*t).Magnitude,180*t,1e-8)
 near(Ballistics.intercept(zero,V.new(0,0,100),V.new(0,0,-180),180,2),100/360)
 near(Ballistics.intercept(zero,zero,zero,180,2),0)
end)
test("projectile solver declines unreachable or invalid flight",function()
 check(Ballistics.intercept(zero,V.new(0,0,100),V.new(0,0,181),180,2)==nil)
 check(Ballistics.intercept(zero,V.new(0,0,1000),zero,180,2)==nil)
 for _,bad in {0,-1,0/0,math.huge} do
  check(Ballistics.intercept(zero,V.new(0,0,100),zero,bad,2)==nil)
 end
end)
test("gravity uses supplied up vector and satisfies flight residual",function()
 local profile={kind="projectile",speed=180,gravity=40,upVector=V.new(0,1,0)}
 local r=Ballistics.solve(zero,V.new(0,0,90),V.new(10,0,0),zero,profile,2,true,0.18)
 check(r~=nil)
 near((r.aimpoint-zero).Magnitude,profile.speed*r.flightSeconds,0.05)
 vectorNear(r.position,V.new(10*r.flightSeconds,0,90),1e-6)
 near(r.aimpoint.Y-r.position.Y,0.5*40*r.flightSeconds^2,1e-8)
 check(r.aimpoint.Y>0 and r.flightSeconds>0.5)
end)
test("finite sphere sweep returns first contact with finite fraction",function()
 local from,to=V.new(-5,0,0),V.new(5,0,0)
 local contact=Geometry.sphereIntersection(from,to,1)
 near(contact,0.4)
 check(contact>=0 and contact<=1)
 vectorNear(from+(to-from)*contact,V.new(-1,0,0))
 near((from+(to-from)*contact).Magnitude,1)
end)
test("sphere sweep handles tangency, starting inside and degenerate segments",function()
 near(Geometry.sphereIntersection(V.new(-5,1,0),V.new(5,1,0),1),0.5)
 check(Geometry.sphereIntersection(V.new(-5,1.01,0),V.new(5,1.01,0),1)==nil)
 near(Geometry.sphereIntersection(V.new(0.5,0,0),V.new(5,0,0),1),0)
 near(Geometry.sphereIntersection(V.new(1,0,0),V.new(5,0,0),1),0)
 check(Geometry.sphereIntersection(V.new(2,0,0),V.new(2,0,0),1)==nil)
 near(Geometry.sphereIntersection(zero,zero,1),0)
end)
test("sphere sweep does not hit behind its start or beyond its finite endpoint",function()
 check(Geometry.sphereIntersection(V.new(5,0,0),V.new(10,0,0),1)==nil)
 check(Geometry.sphereIntersection(V.new(5,0,0),V.new(2,0,0),1)==nil)
 near(Geometry.sphereIntersection(V.new(5,0,0),V.new(1,0,0),1),1)
end)
test("relative sweep catches moving projectile and fast target between endpoints",function()
 local projectileStart,projectileEnd=V.new(-10,0,0),V.new(10,0,0)
 local targetStart,targetEnd=V.new(0,-10,0),V.new(0,10,0)
 local relativeStart,relativeEnd=projectileStart-targetStart,projectileEnd-targetEnd
 local radius=1+0.2
 check(relativeStart.Magnitude>radius and relativeEnd.Magnitude>radius)
 local contact=Geometry.sphereIntersection(relativeStart,relativeEnd,radius)
 near(contact,0.5-radius/math.sqrt(800),1e-10)
 local projectileContact=projectileStart+(projectileEnd-projectileStart)*contact
 local targetContact=targetStart+(targetEnd-targetStart)*contact
 near((projectileContact-targetContact).Magnitude,radius,1e-8)
 local nearMissStart,nearMissEnd=V.new(0,-10,3),V.new(0,10,3)
 check(Geometry.sphereIntersection(projectileStart-nearMissStart,projectileEnd-nearMissEnd,radius)==nil)
 local parallelStart,parallelEnd=V.new(-10,2,0),V.new(10,2,0)
 check(Geometry.sphereIntersection(projectileStart-parallelStart,projectileEnd-parallelEnd,radius)==nil)
end)
test("closest segment point clamps endpoints and handles zero-length segment",function()
 local from,to=zero,V.new(4,0,0)
 local fraction,point=Geometry.closestOnSegment(V.new(2,3,0),from,to)
 near(fraction,0.5);vectorNear(point,V.new(2,0,0))
 fraction,point=Geometry.closestOnSegment(V.new(-3,1,0),from,to)
 near(fraction,0);vectorNear(point,from)
 fraction,point=Geometry.closestOnSegment(V.new(8,1,0),from,to)
 near(fraction,1);vectorNear(point,to)
 local same=V.new(1,2,3)
 fraction,point=Geometry.closestOnSegment(V.new(7,8,9),same,same)
 near(fraction,0);vectorNear(point,same)
end)
test("hitscan adds latency and age exactly without distance-only lead",function()
 local s=Settings.new();local v=V.new(10,0,0)
 local p=track(s,V.new(0,0,50),v,1,0.03)
 local r=p:predict("target",zero,1.12,Weapons.get("RevolverLab"))
 near(r.predictionHorizonSeconds,0.15)
 near(r.flightSeconds,0);vectorNear(r.position,V.new(1.5,0,50))
 local far=track(s,V.new(0,0,250),v,1,0.03):predict("target",zero,1.12,Weapons.get("RevolverLab"))
 near(far.position.X,r.position.X);near(far.flightSeconds,0)
 s.distancePrediction=false
 local noDistance=p:predict("target",zero,1.12,Weapons.get("RevolverLab"))
 vectorNear(noDistance.position,r.position)
end)
test("projectile horizon includes latency, observation age and flight",function()
 local s=Settings.new();local initial=V.new(0,0,80);local v=V.new(10,0,0)
 local p=track(s,initial,v,1,0.03)
 local r=p:predict("target",zero,1.1,Weapons.get("ProjectileLab"))
 check(r~=nil)
 near(r.predictionHorizonSeconds,0.13+r.flightSeconds)
 vectorNear(r.targetPosition,initial+v*r.predictionHorizonSeconds,1e-6)
 near(r.position.Magnitude,180*r.flightSeconds,0.05)
end)
test("per-weapon latency offsets affect the initial delay independently",function()
 local s=Settings.new();s.weaponOffsets.RevolverLab=0.02;s.weaponOffsets.ProjectileLab=0.01
 local revolver=track(s,V.new(0,0,90),V.new(10,0,0),1,0.03)
 local projectile=track(s,V.new(0,0,90),V.new(10,0,0),1,0.03)
 local a=revolver:predict("target",zero,1,Weapons.get("RevolverLab"))
 local b=projectile:predict("target",zero,1,Weapons.get("ProjectileLab"))
 near(a.delaySeconds,0.05);near(b.delaySeconds,0.04)
 near(a.position.X,0.5);near(b.targetPosition.X,10*(0.04+b.flightSeconds),1e-6)
end)
test("disabled velocity and distance controls have distinct effects",function()
 local s=Settings.new();s.velocityPrediction=false
 local p=track(s,V.new(0,0,90),V.new(10,0,0),1,0.08)
 local r=p:predict("target",zero,1.1,Weapons.get("ProjectileLab"))
 vectorNear(r.position,V.new(0,0,90));vectorNear(r.velocity,zero);near(r.flightSeconds,0.5)
 s.velocityPrediction=true;s.distancePrediction=false
 r=p:predict("target",zero,1.1,Weapons.get("ProjectileLab"))
 near(r.position.X,1.8,1e-8)
 check(r.flightSeconds>0);near(r.predictionHorizonSeconds,0.18+r.flightSeconds)
end)
test("bounded acceleration horizon accelerates then coasts at terminal velocity",function()
 local s=Settings.new();s.maxAccelerationHorizonSeconds=0.1
 local p=track(s,V.new(0,0,50),V.new(10,0,0),1,0.09)
 p.tracks.target.acceleration=V.new(20,0,0)
 local r=p:predict("target",zero,1.2,Weapons.get("RevolverLab"))
 near(r.position.X,3.38,1e-8)
 s.accelerationPrediction=false
 r=p:predict("target",zero,1.2,Weapons.get("RevolverLab"))
 near(r.position.X,10*0.29,1e-8)
end)
test("bounded acceleration agrees with numerical integration before and after cap",function()
 local s=Settings.new();s.maxAccelerationHorizonSeconds=0.1
 -- Integrate the velocity over tiny intervals, splitting at the acceleration
 -- cutoff. This independent reference never uses the predictor's displacement
 -- expression; afterward the accumulated terminal velocity stays constant.
 local function integratedDisplacement(horizon)
  local elapsed=0;local displacement=0;local velocity=10
  while elapsed<horizon-1e-12 do
   local step=math.min(0.0001,horizon-elapsed)
   if elapsed<0.1-1e-12 then
    step=math.min(step,0.1-elapsed)
    local nextVelocity=velocity+20*step
    displacement+=(velocity+nextVelocity)*0.5*step
    velocity=nextVelocity
   else
    displacement+=velocity*step
   end
   elapsed+=step
  end
  return displacement
 end
 for _,horizon in {0.05,0.1,0.29,0.5} do
  local p=track(s,V.new(0,0,50),V.new(10,0,0),1,0.03)
  p.tracks.target.acceleration=V.new(20,0,0)
  local r=p:predict("target",zero,1+horizon-0.03,Weapons.get("RevolverLab"))
  near(r.predictionHorizonSeconds,horizon,1e-10)
  near(r.position.X,integratedDisplacement(horizon),1e-8)
 end
 local p=track(s,V.new(0,0,50),V.new(10,0,0),1,0.03)
 p.tracks.target.acceleration=V.new(20,0,0)
 local projectile=p:predict("target",zero,1.26,Weapons.get("ProjectileLab"))
 check(projectile~=nil)
 near(projectile.targetPosition.X,integratedDisplacement(0.29+projectile.flightSeconds),1e-8)
end)
test("stale, future and missing targets return no prediction; lifecycle clears tracks",function()
 local p=track(Settings.new(),V.new(0,0,20),zero,1,0.03)
 check(p:predict("missing",zero,1,Weapons.get("RevolverLab"))==nil)
 check(p:predict("target",zero,1,nil)==nil)
 check(p:predict("target",zero,1.61,Weapons.get("RevolverLab"))==nil)
 check(p:predict("target",zero,0.94,Weapons.get("RevolverLab"))==nil)
 check(p:predict("target",zero,0.99,Weapons.get("RevolverLab"))~=nil)
 p:forget("target");check(next(p.tracks)==nil)
 check(p:observe("one",sample(1,zero,zero)));check(p:observe("two",sample(1,zero,zero)))
 p:clear();check(next(p.tracks)==nil)
end)
test("prediction gravity remains portable and range labels are measured",function()
 local profile={kind="projectile",speed=180,gravity=40,upVector=V.new(0,1,0),latencyOffsetSeconds=0}
 local p=track(Settings.new(),V.new(0,0,90),zero,1,0.03)
 local r=p:predict("target",zero,1,profile)
 check(r~=nil and r.position.Y>r.targetPosition.Y)
 check(r.range=="medium");near(r.distanceStuds,90)
 local close=track(Settings.new(),V.new(0,0,20),zero):predict("target",zero,0,Weapons.get("RevolverLab"))
 local far=track(Settings.new(),V.new(0,0,200),zero):predict("target",zero,0,Weapons.get("RevolverLab"))
 check(close.range=="close" and far.range=="long")
end)
test("diagnostic shot rate and prediction RMSE use separate denominators",function()
 local d=Diagnostics.new(10)
 check(d:recordPrediction({errorStuds=3}));check(d:recordPrediction({errorStuds=4}))
 for i=1,4 do check(d:recordShot({hit=i==1,weapon="RevolverLab",missDistanceStuds=if i==1 then 0 else 2})) end
 local a=d:summary()
 near(a.shots,4);near(a.hits,1);near(a.hitRate,0.25);near(a.predictionCount,2)
 near(a.predictionRMSEStuds,math.sqrt(12.5));near(a.missDistanceMeanStuds,1.5)
 near(a.byWeapon.RevolverLab.hitRate,0.25)
 check(d:recordShot({hit=true,weapon="ProjectileLab"}))
 local b=d:summary();near(b.predictionRMSEStuds,a.predictionRMSEStuds);near(b.hitRate,2/5)
 near(b.missDistanceMeanStuds,a.missDistanceMeanStuds)
end)
test("diagnostic capacity evicts old records and rejects invalid errors",function()
 local d=Diagnostics.new(3)
 for _,err in {100,1,2,3} do check(d:recordPrediction({errorStuds=err})) end
 for _,bad in {-1,0/0,math.huge} do check(not d:recordPrediction({errorStuds=bad})) end
 check(not d:recordShot({hit="yes"}))
 for i=1,4 do check(d:recordShot({hit=i==1,weapon="RevolverLab"})) end
 local a=d:summary();near(a.predictionCount,3);near(a.predictionRMSEStuds,math.sqrt(14/3))
 near(a.shots,3);near(a.hits,0);near(a.hitRate,0)
 d:clear();a=d:summary();near(a.shots,0);near(a.predictionCount,0);check(a.predictionRMSEStuds==nil)
end)
test("rejected shots do not enter denominators and wrong target hits count as misses",function()
 local d=Diagnostics.new(10)
 check(not d:recordShot({accepted=false,hit=true,intendedHit=true,weapon="RevolverLab",missDistanceStuds=100}))
 check(d:recordShot({accepted=true,hit=true,intendedHit=false,weapon="RevolverLab",missDistanceStuds=2}))
 check(d:recordShot({accepted=true,hit=true,intendedHit=true,weapon="RevolverLab",missDistanceStuds=0}))
 check(d:recordShot({hit=true,weapon="ProjectileLab"}))
 local a=d:summary()
 near(a.shots,3);near(a.hits,2);near(a.hitRate,2/3)
 near(a.byWeapon.RevolverLab.shots,2);near(a.byWeapon.RevolverLab.hitRate,0.5)
 near(a.missDistanceMeanStuds,1)
end)
test("weapon prediction metrics stay independent of shot counts and other profiles",function()
 local d=Diagnostics.new(10)
 check(d:recordPrediction({errorStuds=3,weapon="RevolverLab"}))
 check(d:recordPrediction({errorStuds=4,weapon="RevolverLab"}))
 check(d:recordPrediction({errorStuds=12,weapon="ProjectileLab"}))
 check(d:recordShot({hit=true,weapon="RevolverLab"}))
 check(d:recordShot({hit=false,weapon="RevolverLab"}))
 local a=d:summary()
 near(a.byWeapon.RevolverLab.predictionCount,2)
 near(a.byWeapon.RevolverLab.predictionRMSEStuds,math.sqrt(12.5))
 near(a.byWeapon.RevolverLab.hitRate,0.5)
 near(a.byWeapon.ProjectileLab.predictionCount,1)
 near(a.byWeapon.ProjectileLab.predictionRMSEStuds,12)
 near(a.byWeapon.ProjectileLab.shots,0);near(a.byWeapon.ProjectileLab.hitRate,0)
 near(a.predictionRMSEStuds,math.sqrt(169/3))
 check(d:recordShot({hit=true,weapon="ProjectileLab"}))
 local b=d:summary()
 near(b.byWeapon.ProjectileLab.predictionRMSEStuds,a.byWeapon.ProjectileLab.predictionRMSEStuds)
 near(b.byWeapon.ProjectileLab.hitRate,1)
end)

-- Deterministic scenario benchmark: delayed, timestamped observations of an
-- alternating walk/jump/reversal path. This checks bounded numerical behavior
-- and compares to raw observed position; it does not promise live hit rates.
local function trajectory(t)
 local segment=math.floor(t/0.8)
 local localT=t-segment*0.8
 local direction=if segment%2==0 then 1 else -1
 local x=if direction==1 then 16*localT else 12.8-16*localT
 local jumping=segment%3==1
 local y=if jumping then 4*math.sin(math.pi*localT/0.8) else 0
 local vy=if jumping then 4*math.pi/0.8*math.cos(math.pi*localT/0.8) else 0
 return V.new(x,y,90),V.new(16*direction,vy,0),if jumping then "Jumping" else "Walking"
end
test("jitter and motion reversal benchmark stays bounded over 8 to 180 ms RTT",function()
 local totalPredSq,totalRawSq,totalCount=0,0,0
 for _,pingMilliseconds in {4,8,16,30,75,90} do
  local basePing=pingMilliseconds/1000
  local s=Settings.new();local p=Predictor.new(s)
  local predSq,rawSq,count,maxError=0,0,0,0
  for i=1,240 do
   local now=0.2+i/30
   local ping=math.max(0.001,basePing+0.004*math.sin(i*0.73)+0.002*math.cos(i*0.19))
   check(p:setPing(ping,now))
   local observedAt=now-ping
   local position,velocity,state=trajectory(observedAt)
   check(p:observe("target",sample(observedAt,position,velocity,state)))
   local r=p:predict("target",zero,now,Weapons.get("RevolverLab"))
   check(r~=nil)
   local truth=trajectory(now+ping)
   local error=(r.targetPosition-truth).Magnitude
   local rawError=(position-truth).Magnitude
   check(error==error and error<20,"nonfinite or unbounded scenario error")
   predSq+=error*error;rawSq+=rawError*rawError;count+=1;maxError=math.max(maxError,error)
  end
  local predictedRMSE=math.sqrt(predSq/count)
  local observedRMSE=math.sqrt(rawSq/count)
  print(string.format("BENCH one-way=%dms RTT=%dms n=%d predictionRMSE=%.4f rawObservationRMSE=%.4f maxError=%.4f studs",
   pingMilliseconds,2*pingMilliseconds,count,predictedRMSE,observedRMSE,maxError))
  totalPredSq+=predSq;totalRawSq+=rawSq;totalCount+=count
 end
 check(totalCount==1440)
 check(totalPredSq<totalRawSq,"prediction should improve aggregate error on this modeled path")
 print(string.format("BENCH aggregate n=%d predictionRMSE=%.4f rawObservationRMSE=%.4f studs",
  totalCount,math.sqrt(totalPredSq/totalCount),math.sqrt(totalRawSq/totalCount)))
end)

print(string.format("TEST SUMMARY: %d tests, %d assertions, %d failures",tests,checks,failures))
assert(tests>0 and checks>0,"test runner must execute assertions")
assert(failures==0,tostring(failures).." tests failed")
