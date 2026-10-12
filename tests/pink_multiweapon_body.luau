--!nonstrict
-- Actual SEDWARE bundle + WeaponManager + both controllers + physical tracker.
-- Tool events, transport, moving projectile positions and sphere/plane queries
-- are EXPLICIT DOUBLES; no native Studio/Da Hood result is asserted.
local Mock=require("./PinkMock")
local Profiles=require("../src/pink_weapon/WeaponProfiles")
local Manager=require("../src/pink_weapon/WeaponManager")
local Server=require("../src/pink_weapon/ServerController")
local Tracker=require("../src/pink_weapon/ProjectileTracker")
local Verification=require("../src/pink_weapon/NativeVerification")
return function(reloadBundle)
 local tests,checks,fixtures=0,0,{}
 local function check(value,message) checks+=1;assert(value,message or "assertion failed") end
 local function near(a,b) check(type(a)=="number" and math.abs(a-b)<1e-7,tostring(a).." != "..tostring(b)) end
 local function signal()
  local s={listeners={}}
  function s:Connect(callback)
   local connection={Connected=true}
   self.listeners[connection]=callback
   function connection:Disconnect() self.Connected=false;s.listeners[self]=nil end
   return connection
  end
  function s:Fire(...) for connection,callback in table.clone(self.listeners) do if connection.Connected then callback(...) end end end
  return s
 end
 local function rig(options)
  options=options or {}
  local mock=Mock.new();local V=mock.env.Vector3
  local api=reloadBundle(mock.env)
  api.init({PredictionSmoothing=options.smoothing or 0,VisibilityCheck=false})
  mock:setTime(80);mock:setPointer(640,360)
  local target=mock:addPlayer("MultiweaponTarget",V.new(0,0,-20))
  local shooter=mock.services.Players.LocalPlayer
  local targetPart=target.Character:FindFirstChild("HumanoidRootPart")
  local targetHumanoid=target.Character:FindFirstChildOfClass("Humanoid")
  targetHumanoid.Health=1000
  local state={equipped=nil,queue={},statuses={},rays={},projectiles={},damageCalls=0,
   origin=V.new(3,2,0),cameraAim=V.new(100,0,-50),wall=false,miss=false,forceField=false}
  local profiles=Profiles.defaults()
  for id,profile in options.extra or {} do profiles[id]=Profiles.normalize(id,profile) end
  local tools={}
  for id in profiles do
   local tool={Id=id,Parent={},Destroyed=false}
   for _,name in {"Equipped","Unequipped","Activated","Deactivated","AncestryChanged","Destroying"} do tool[name]=signal() end
   function tool:IsA(class) return class=="Tool" end
   function tool:Activate() self.Activated:Fire() end
   function tool:Deactivate() self.Deactivated:Fire() end
   function tool:Destroy() self.Destroying:Fire();self.Parent=nil;self.Destroyed=true end
   tools[id]=tool
  end
  local function clock() return mock.world:GetServerTimeNow() end
  local function cast(origin,direction)
   table.insert(state.rays,{origin=origin,direction=direction})
   if state.miss then return nil end
   local length=direction.Magnitude
   if length<1e-9 then return nil end
   local unit=direction/length
   if state.wall and unit.Z<0 then
    local distance=(-8-origin.Z)/unit.Z
    if distance>0 and distance<=length then return {name="Wall",position=origin+unit*distance} end
   end
   local center=targetPart.Position
   local offset=origin-center
   local b,c=offset:Dot(unit),offset:Dot(offset)-1.7^2
   local discriminant=b*b-c
   if discriminant<0 then return nil end
   local distance=-b-math.sqrt(discriminant)
   if distance<0 or distance>length then return nil end
   return {name="TargetRoot",position=origin+unit*distance,character=target.Character,humanoid=targetHumanoid}
  end
  local server=Server.new({profiles=profiles,settings=options.serverSettings,clock=clock,
   random=function() return 0.5 end,makeVector=V.new,
   getEquippedWeapon=function(player)
    if player~=shooter or not state.equipped then return nil end
    return {tool=tools[state.equipped],profileId=state.equipped,origin=state.origin,
     character=shooter.Character,humanoid=shooter.Character:FindFirstChildOfClass("Humanoid")}
   end,
   getTarget=function(id,partName,character)
    if id~=target.UserId or character~=target.Character or partName~=targetPart.Name then return nil end
    return {player=target,character=character,part=targetPart,humanoid=targetHumanoid,position=targetPart.Position}
   end,
   raycast=cast,describeHit=function(hit) return hit end,
   applyDamage=function(humanoid,damage)
    state.damageCalls+=1;local before=humanoid.Health
    if not state.forceField then humanoid.Health=math.max(0,before-damage) end
    return {before=before,after=humanoid.Health}
   end,
   onResult=function(_,result) result.engine="CallbackDouble";table.insert(state.queue,result) end,
   launchProjectile=function(origin,velocity,profile,ignoreCharacter,complete)
    check(ignoreCharacter==shooter.Character)
    local physical={origin=origin,velocity=velocity,profile=profile,started=clock(),position=origin,disposed=false}
    local tracker
    tracker=Tracker.new({origin=origin,range=profile.Range,lifetime=profile.Lifetime,clock=clock,
     getPosition=function() return if physical.disposed then nil else physical.position end,
     raycast=cast,onComplete=complete,dispose=function() physical.disposed=true end})
    physical.tracker=tracker;table.insert(state.projectiles,physical)
    if state.launchError then tracker:cancel();error("physical launch callback failure") end
    return function() tracker:cancel() end
   end})
  local manager=Manager.new({api=api,profiles=profiles,clock=clock,sessionId="multiweapon-double",
   getOrigin=function(tool) return if tool and tool.Parent==shooter.Character then state.origin else nil end,
   isEquipped=function(tool) return tool~=nil and tool.Parent==shooter.Character and state.equipped==tool.Id end,
   getCameraAim=function() return state.cameraAim end,
   send=function(request)
    state.lastRequest=request
    local result=server:process(shooter,request);result.engine="CallbackDouble";table.insert(state.queue,result)
   end,
   onStatus=function(kind,details)
    if kind=="Pending" then state.lastRequest=details.request end
    table.insert(state.statuses,{kind=kind,details=details})
    if state.verification then state.verification:record(kind,details) end
   end})
  for id,tool in tools do manager:track(tool,id) end
  local f={mock=mock,V=V,api=api,manager=manager,server=server,state=state,tools=tools,
   target=target,targetPart=targetPart,targetHumanoid=targetHumanoid,shooter=shooter,profiles=profiles,clock=clock}
  function f:pressC() mock.services.UserInputService.InputBegan:Fire(mock:input("Keyboard",0,0,"C"),false) end
  function f:equip(id)
   if state.equipped then local prior=tools[state.equipped];prior.Parent={};prior.Unequipped:Fire();prior.AncestryChanged:Fire() end
   state.equipped=id;local tool=tools[id];tool.Parent=shooter.Character;tool.Equipped:Fire()
   check(manager.active and manager.active.profile.Id==id)
  end
  function f:deliver()
   local results=state.queue;state.queue={}
   for _,result in results do
    local accepted,problem=manager:receive(result)
    check(accepted~=nil,"controller refused expected result: "..tostring(problem))
   end
  end
  function f:advance(seconds)
   local remaining=seconds
   while remaining>1e-8 do
    local dt=math.min(remaining,1/60);remaining-=dt
    mock:advance(dt)
    for _,p in state.projectiles do
     if not p.disposed then
      local t=clock()-p.started
      -- Independent physics DOUBLE, deliberately not a prediction equation.
      p.position=p.origin+p.velocity*t+V.new(0,-p.profile.Gravity*t*t/2,0)
      p.tracker:step(clock())
     end
    end
    manager:step(clock());f:deliver()
   end
  end
  function f:fire(id)
   if id then self:equip(id) end
   tools[state.equipped]:Activate();tools[state.equipped]:Deactivate()
   local status=state.statuses[#state.statuses]
   check(state.lastRequest~=nil,"Tool activation did not send: "..tostring(status and status.details.reason).." weapon="..state.equipped)
   return state.lastRequest
  end
  function f:close()
   if state.verification then state.verification:destroy() end
   manager:destroy();server:destroy();api.Unload()
   for _,tool in tools do for _,name in {"Equipped","Unequipped","Activated","Deactivated","AncestryChanged","Destroying"} do check(next(tool[name].listeners)==nil) end end
   check(mock:countConnections()==0)
  end
  table.insert(fixtures,f)
  f:pressC();check(api.GetLockedTarget()==target)
  mock:resetCounters() -- Exclude camera/pointer writes used to construct the double.
  return f
 end
 local function test(name,body)
  tests+=1
  local ok,problem=pcall(body)
  for _,f in fixtures do f:close() end;table.clear(fixtures)
  assert(ok,name..": "..tostring(problem))
 end
 test("all six equipped Tools retain actual C lock, DOT, Memory and free camera",function()
  local f=rig();local history=f.api.session.prediction.history
  for _,id in {"Revolver","Pistol","Shotgun","Rifle","Automatic","Projectile"} do
   f:equip(id);f:advance(0.02)
   check(f.api.GetLockedTarget()==f.target and f.api.session.overlay.dot.Visible)
   check(f.api.session.prediction.history==history)
   check(f.api.session.config.MemoryTracking and f.api.session.config.AutoPrediction==false)
   near(f.api.session.config.PredictionX,0.1205);near(f.api.session.config.PredictionY,0.08)
  end
  near(f.mock.counters.cameraWrites,0);near(f.mock.counters.mouseWrites,0)
  near(f.mock.counters.candidateScans,0)
 end)
 test("every compatible controller receives the exact public predicted point",function()
  local f=rig()
  for _,id in {"Revolver","Pistol","Shotgun","Rifle","Automatic","Projectile"} do
   f:equip(id);f:advance(1)
   local delivered
   f.manager:registerController(id,function(request,context)
    delivered=context
    local response=f.server:process(f.shooter,request);table.insert(f.state.queue,response)
   end)
   local request=f:fire();check(request.weaponId==id and request.mode=="Locked")
   check(delivered.profile.Id==id and delivered.targetCharacter==f.target.Character)
   near((request.aimpoint-f.api.GetPredictedPosition(f.state.origin)).Magnitude,0)
   near((request.aimpoint-delivered.aimpoint).Magnitude,0)
   check((request.aimpoint-f.state.cameraAim).Magnitude>1)
   f:advance(0.6)
  end
 end)
 test("server uses per-weapon damage/range and eight independent shotgun queries",function()
  local f=rig();f:fire("Shotgun");f:deliver()
  local result=f.manager.client.lastResult
  check(result.accepted and result.hit and result.selectedTargetHit)
  near(result.pelletCount,8);near(result.pelletHits,8);near(result.damageApplied,48)
  near(#f.state.rays,8)
  for _,ray in f.state.rays do near(ray.direction.Magnitude,180) end
  f:advance(1);f:fire("Rifle");f:deliver();near(f.manager.client.lastResult.damageApplied,30)
  near(f.state.rays[#f.state.rays].direction.Magnitude,600)
 end)
 test("server-owned spread can hit a wall without granting any target damage",function()
  local f=rig();f.state.wall=true;f:fire("Shotgun");f:deliver()
  local result=f.manager.client.lastResult
  check(result.hit and not result.selectedTargetHit);near(result.damageApplied,0);near(f.state.damageCalls,0)
 end)
 test("holding Automatic repeats at its cadence and release stops it",function()
  local f=rig();f:equip("Automatic");f.tools.Automatic:Activate();f:advance(0.28)
  local count=f.manager:summary().sent;check(count>=2 and count<=3)
  f.tools.Automatic:Deactivate();f:advance(0.5);near(f.manager:summary().sent,count)
  check(f.manager:summary().selectedTargetHits>=2)
 end)
 test("changing from Automatic stops repetition without clearing the target",function()
  local f=rig();f:equip("Automatic");f.tools.Automatic:Activate();f:advance(0.15)
  f:equip("Pistol");local count=f.manager:summary().sent;f:advance(0.6)
  near(f.manager:summary().sent,count);check(f.api.GetLockedTarget()==f.target and not f.manager.held)
 end)
 test("all weapon types return to crosshair fire after C unlock",function()
  local f=rig();f:pressC();check(f.api.GetLockedTarget()==nil)
  for _,id in {"Revolver","Pistol","Shotgun","Rifle","Automatic","Projectile"} do
   f:equip(id);f:advance(1)
   local request=f:fire()
   check(request.mode=="Normal" and request.targetUserId==nil and request.ticketId==nil)
   near((request.aimpoint-f.state.cameraAim).Magnitude,0)
   f:advance(0.5)
  end
 end)
 test("projectile launch is pending and cannot claim an immediate hit",function()
  local f=rig();f:fire("Projectile")
  near(f.manager:summary().confirmed,0);near(f.state.damageCalls,0);near(f.server.jobCount,1)
  f:deliver();near(f.manager:summary().confirmed,0);near(f.manager:summary().pending,1)
  check(f.state.statuses[#f.state.statuses].kind=="InFlight")
  f:advance(0.4)
  local result=f.manager.client.lastResult
  check(result.accepted and result.hit and result.selectedTargetHit and result.physicsKind=="Projectile")
  near(result.damageApplied,35);near(f.server.jobCount,0)
  check(result.measurement~=nil)
 end)
 test("render prediction consistently uses muzzle origin with output smoothing",function()
  local f=rig({smoothing=0.08});f:equip("Projectile");f:advance(0.1)
  near((f.api.session.lastPredictionOrigin-f.state.origin).Magnitude,0)
  local before=f.api.GetPredictedPosition(f.state.origin)
  local request=f:fire()
  near((before-request.aimpoint).Magnitude,0)
  f:advance(0.4);check(f.manager.client.lastResult.selectedTargetHit)
 end)
 test("flight result remains attributable to Projectile after equipping another weapon",function()
  local f=rig();local request=f:fire("Projectile");f:deliver();f:equip("Revolver")
  f:advance(0.4)
  local result=f.manager.client.lastResult
  check(result.request.shotId==request.shotId and result.weaponId=="Projectile")
  check(result.hit and result.measurement~=nil and f.api.GetLockedTarget()==f.target)
  check(f.api.session.prediction.weaponProfileLabel=="Revolver")
 end)
 test("accepted projectile expiration remains a real miss with no manufactured contact",function()
  local f=rig();f.state.miss=true;f:fire("Projectile");f:deliver();f:advance(3.1)
  local result=f.manager.client.lastResult
  check(result.accepted and not result.hit and not result.selectedTargetHit)
  near(result.damageApplied,0);near(f.state.damageCalls,0);near(f.server.jobCount,0)
 end)
 test("lost physical resource is a rejection, not an accepted impact",function()
  local f=rig();f:fire("Projectile");f:deliver()
  f.state.projectiles[1].disposed=true
  f.state.projectiles[1].tracker:step(f.clock())
  f:deliver();local result=f.manager.client.lastResult
  check(not result.accepted and not result.hit and string.find(result.reason,"projectile-lost",1,true)~=nil)
 end)
 test("launch exceptions leave no pending physical job or confirmed success",function()
  local f=rig();f.state.launchError=true;f:fire("Projectile");f:deliver()
  check(not f.manager.client.lastResult.accepted and f.manager.client.lastResult.reason=="server-error")
  near(f.server.jobCount,0);near(f.state.damageCalls,0);near(f.manager:summary().confirmed,0)
  check(f.state.projectiles[1].disposed)
 end)
 test("a launch notice cannot smuggle a confirmed hit or consume the shot",function()
  local f=rig();f:fire("Projectile")
  local notice=table.clone(f.state.queue[1]);notice.hit=true
  local result,problem=f.manager:receive(notice)
  check(result==nil and problem=="invalid-launch-confirmation")
  near(f.manager:summary().confirmed,0);near(f.manager:summary().pending,1)
  f:deliver();f:advance(0.4);check(f.manager.client.lastResult.selectedTargetHit)
 end)
 test("profile spoofing cannot make an equipped Pistol use Rifle damage",function()
  local f=rig();local request=f:fire("Pistol")
  local fake=table.clone(request);fake.weaponId="Rifle";fake.shotId+=1
  f:advance(0.3)
  local response=f.server:process(f.shooter,fake)
  check(not response.accepted and response.reason=="weapon-profile-mismatch")
 end)
 test("switching weapons cannot bypass either shared fire cooldown",function()
  local f=rig();f:fire("Shotgun");f:deliver();f:equip("Automatic")
  local request,problem=f.manager:fire();check(request==nil and problem=="client-cooldown")
  local prior=f.state.lastRequest
  local fake=table.clone(prior);fake.weaponId="Automatic";fake.shotId+=1
  local response=f.server:process(f.shooter,fake)
  check(not response.accepted and response.reason=="cooldown")
 end)
 test("custom registered weapon reuses the existing lock and prediction session",function()
  local f=rig({extra={Laser={Name="Own Custom",Damage=17,Range=200}}})
  local selection=f.api.session.locked
  f:fire("Laser");f:deliver()
  near(f.manager.client.lastResult.damageApplied,17);check(f.api.session.locked==selection)
  check(not pcall(function() f.manager:register("Laser",{}) end))
  local ok,reason=f.manager:equip(f.tools.Laser,"Missing")
  check(not ok and reason=="unsupported-weapon")
 end)
 test("profile validation preserves the working weapon and Memory on error",function()
  local f=rig();f:equip("Revolver")
  local history=f.api.session.prediction.history
  local changed,reason=f.api.SetWeaponProfile("Custom",{Kind="Projectile",Speed=-1})
  check(not changed and reason~=nil and f.api.session.prediction.history==history)
  check(f.manager.active.profile.Id=="Revolver" and f.api.GetLockedTarget()==f.target)
 end)
 test("a reference from another weapon cannot consume the pending shot",function()
  local f=rig();f:fire("Revolver")
  local response=table.clone(f.state.queue[1]);response.weaponId="Pistol"
  local result,reason=f.manager:receive(response)
  check(result==nil and reason=="weapon-mismatch");near(f.manager:summary().pending,1)
  f:deliver();near(f.manager:summary().confirmed,1)
 end)
 test("projectile capacities and cleanup bound native resource callbacks",function()
  local f=rig({serverSettings={MaxProjectiles=1,MaxProjectilesPerPlayer=1}})
  f.state.miss=true;f:fire("Projectile");f:deliver();f:advance(0.75)
  f:fire();f:deliver()
  check(not f.manager.client.lastResult.accepted and f.manager.client.lastResult.reason=="projectile-capacity")
  f.server:removePlayer(f.shooter);near(f.server.jobCount,0);check(f.state.projectiles[1].disposed)
 end)
 test("repeated tracking and manager unload create no duplicate Tool connections",function()
  local f=rig();f:equip("Automatic")
  for _=1,40 do f.manager:track(f.tools.Automatic,"Automatic") end
  local count=0;for _ in f.tools.Automatic.Activated.listeners do count+=1 end;near(count,1)
  f.tools.Automatic:Activate();f:deliver()
  f.manager:destroy();check(not f.manager.held and f.manager:summary().pending==0)
  check(f.api.session.config.WeaponProfile=="Revolver" and f.api.session.predictionOriginProvider==nil)
  check(f.api.GetLockedTarget()==f.target)
 end)
 test("native verifier rejects a missing C selection and never calls a mathematical run native",function()
  local f=rig();local published,ended
  local verifier=Verification.new({api=f.api,manager=f.manager,clock=f.clock,wait=function(dt) f:advance(dt) end,
   getTool=function(id) return f.tools[id] end,getCameraAim=function() return f.state.cameraAim end,
   getHumanoid=function() return {EquipTool=function(_,tool) f:equip(tool.Id) end} end,
   beginRun=function() return {ok=true,runId="explicit-double"} end,endRun=function(id) ended=id end,
   runtimeName="CallbackDoubles",publish=function(report) published=report end})
  f.state.verification=verifier
  local report,reason=verifier:run();check(report==nil and string.find(reason,"Press C",1,true)~=nil)
  verifier:noteC();report=verifier:run()
  check(report==published and report.runtime=="CallbackDoubles" and not report.passed)
  near(#report.weapons,6);check(ended=="explicit-double")
  for _,entry in report.weapons do check(entry.shots>=1 and not entry.allNative) end
  check(f.api.GetLockedTarget()==nil)
 end)
 print(string.format("SEDWARE multiweapon bundle: %d tests, %d assertions, 0 failures (Tool/physics/transport doubles)",tests,checks))
end
