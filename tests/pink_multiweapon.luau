--!nonstrict
-- Module regressions with explicit vector, position and collision doubles.
-- No test here runs native Roblox physics or verifies Da Hood integration.
local Profiles=require("../src/pink_weapon/WeaponProfiles")
local Spread=require("../src/pink_weapon/Spread")
local Tracker=require("../src/pink_weapon/ProjectileTracker")
local Server=require("../src/pink_weapon/ServerController")
local V=require("./Vector")
local tests,checks=0,0
local function check(value,message) checks+=1;assert(value,message or "assertion failed") end
local function near(a,b) check(math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
local function test(name,body) tests+=1;local ok,problem=pcall(body);assert(ok,name..": "..tostring(problem)) end
test("six distinct explicit profiles do not pretend to describe Da Hood",function()
 local p=Profiles.defaults();local count=0
 for id,item in p do count+=1;check(item.Id==id and table.isfrozen(item)) end
 near(count,6);check(p.Shotgun.Pellets==8 and p.Shotgun.SpreadDegrees>0)
 check(p.Projectile.Kind=="Projectile" and p.Projectile.Speed>0 and p.Projectile.Gravity>0)
 check(p.Automatic.Automatic and not p.Rifle.Automatic);check(p.Pistol.Damage~=p.Rifle.Damage)
 check(p.Shotgun.Range~=p.Rifle.Range and p.Pistol.Cooldown~=p.Revolver.Cooldown)
end)
test("unknown fields and physically conflicting definitions are rejected",function()
 for _,profile in {{Kind="Beam"},{Speed=5},{Gravity=2},{Kind="Projectile",Speed=0},
  {Kind="Projectile",Speed=160,Pellets=2},{Pellets=1.5},{Pellets=33},{SpreadDegrees=0/0},
  {Automatic=1},{Damage=math.huge},{Lifetime=6},{Unknown=true},{PredictionXOffset=0.21}} do
  check(not pcall(Profiles.normalize,"Custom",profile))
 end
 for _,id in {"","1Bad","Bad-ID",string.rep("X",41)} do check(not pcall(Profiles.normalize,id,{})) end
end)
test("custom profiles produce validated prediction fields without mutating defaults",function()
 local p=Profiles.normalize("Launcher",{Name="Own launcher",Kind="Projectile",Speed=220,Gravity=20,Damage=40,PredictionXOffset=0.02})
 local prediction=Profiles.prediction(p)
 near(prediction.Speed,220);near(prediction.Gravity,20);near(prediction.PredictionXOffset,0.02)
 check(Profiles.defaults().Projectile.Speed==160)
end)
test("zero spread follows exact axis even for many pellets",function()
 local axis=V.new(1,2,-3)
 local directions=Spread.directions(axis,8,0)
 for _,direction in directions do near(direction.Magnitude,1);near((direction-axis/axis.Magnitude).Magnitude,0) end
end)
test("sampled spread stays inside requested cone for horizontal and vertical axes",function()
 for _,axis in {V.new(0,0,-1),V.new(0,1,0),V.new(0,-1,0),V.new(3,2,1)} do
  local index=0
  local directions=Spread.directions(axis,32,3,function() index+=1;return (index%17)/16 end,V.new)
  for _,direction in directions do near(direction.Magnitude,1);check(direction:Dot(axis/axis.Magnitude)>=math.cos(math.rad(3))-1e-8) end
 end
end)
test("invalid spread cannot send nonfinite directions into a collision query",function()
 for _,args in {{0,3},{33,3},{1.5,3},{1,-1},{1,0/0},{1,21}} do
  check(not pcall(Spread.directions,V.new(0,0,-1),args[1],args[2],function() return 0.5 end,V.new))
 end
 check(not pcall(Spread.directions,V.new(0,0,0),1,0))
 check(not pcall(Spread.directions,V.new(0,0,-1),1,3,function() return math.huge end,V.new))
end)
local function fixture(options)
 options=options or {}
 local state={now=10,pos=V.new(0,0,0),rays={},complete=0,dispose=0,hit=options.hit}
 local tracker=Tracker.new({origin=state.pos,range=options.range or 20,lifetime=options.lifetime or 1,
  clock=function() return state.now end,getPosition=function() return state.pos end,
  raycast=function(origin,delta) table.insert(state.rays,{origin=origin,delta=delta});if state.throw then error("native query unavailable") end;return state.hit end,
  dispose=function() state.dispose+=1 end,
  onComplete=function(hit,reason,position,distance) state.complete+=1;state.result={hit=hit,reason=reason,position=position,distance=distance} end})
 return tracker,state
end
test("projectile sweep reads independent observed positions instead of predicted targets",function()
 local tracker,s=fixture()
 s.pos=V.new(1,-0.2,-3);s.now+=0.1;tracker:step()
 s.pos=V.new(2,-0.8,-6);s.now+=0.1;tracker:step()
 check(#s.rays==2 and s.complete==0 and not tracker.done)
 near(s.rays[2].origin.Y,-0.2);near(s.rays[2].delta.Y,-0.6)
 near(s.rays[2].delta.Z,-3)
 tracker:cancel();near(s.complete,0);near(s.dispose,1)
end)
test("only a returned scene query result confirms contact, exactly once",function()
 local hit={Instance="ActualSceneSurface"}
 local tracker,s=fixture({hit=hit})
 s.pos=V.new(0,0,-3);s.now+=0.1;tracker:step();tracker:step();tracker:cancel()
 check(s.result.hit==hit and s.result.reason=="impact");near(s.complete,1);near(s.dispose,1)
end)
test("range clamps the final segment and records a measured miss",function()
 local tracker,s=fixture({range=5})
 s.pos=V.new(0,0,-50);s.now+=0.1;tracker:step()
 near(s.rays[1].delta.Magnitude,5);near(s.result.distance,5)
 check(s.result.hit==nil and s.result.reason=="range-expired");near(s.result.position.Z,-5)
end)
test("a frozen projectile expires without fabricating target contact",function()
 local tracker,s=fixture()
 s.now+=1.01;tracker:step()
 check(s.result.reason=="lifetime-expired" and s.result.hit==nil);near(#s.rays,0)
end)
test("loss, clock failure and collision API failure are errors rather than confirmed misses",function()
 for _,kind in {"lost","clock","ray"} do
  local tracker,s=fixture()
  if kind=="lost" then s.pos=nil elseif kind=="clock" then s.now=0/0 else s.pos=V.new(0,0,-3);s.throw=true end
  tracker:step();check(tracker.done and s.result.hit==nil)
  check(s.result.reason~="lifetime-expired" and s.result.reason~="range-expired")
 end
end)
test("cancel releases resources and emits no success or collision result",function()
 local tracker,s=fixture()
 tracker:cancel();tracker:cancel();tracker:step()
 near(s.dispose,1);near(s.complete,0);check(tracker.options==nil)
end)
test("projectile callback and cleanup failures retain useful errors",function()
 local tracker=Tracker.new({origin=V.new(),range=1,lifetime=1,clock=function() return 1 end,
  getPosition=function() return V.new(0,0,-2) end,raycast=function() return {} end,
  dispose=function() error("dispose detail") end,onComplete=function() error("completion detail") end})
 local ok,problem=pcall(function() tracker:step(1.1) end)
 check(not ok and string.find(problem,"dispose detail",1,true)~=nil and tracker.done)
end)
test("registered physical weapons require a real launch and completion interface",function()
 check(not pcall(Server.new,{profiles=Profiles.defaults(),clock=function() return 1 end,
  getEquippedWeapon=function() end,getTarget=function() end,raycast=function() end,
  describeHit=function() end,applyDamage=function() end}))
end)
print(string.format("SEDWARE multiweapon modules: %d tests, %d assertions, 0 failures (explicit doubles)",tests,checks))
