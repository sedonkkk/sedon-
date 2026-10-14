--!nonstrict
-- Actual V3.2 embedded modules / owned server source with explicit API doubles.
-- Values assigned below are fixtures, not native physics or Da Hood verification.
return function(reloadBundle,serverSource)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message) checks+=1;assert(value,message or ("V3.2 movement assertion at line "..tostring(debug.info(2,"l")))) end
 local function near(value,expected,epsilon) check(math.abs(value-expected)<=(epsilon or 1e-8),tostring(value).." ~= "..tostring(expected)) end
 local function test(name,body)
  tests+=1;local m=Mock.new();local api=reloadBundle(m.env)
  local ok,reason=pcall(body,m,api)
  if not ok then failures+=1;print("FAIL V3.2 movement "..name..": "..tostring(reason)) end
  api.Unload()
  if m.serverScript then m.serverScript:Destroy() end
  check(m:countConnections()==0,"signals leaked: "..name)
  check(m:countRenderBindings()==0,"render binding leaked: "..name)
  check(m.tweens.active==0,"tween leaked: "..name)
 end
 local function localSession(m,a,options)
  local config={MovementMode="Local",LocalMovementAllowed=true,WelcomeNotification=false}
  for key,value in options or {} do config[key]=value end
  return a.init(config)
 end
 local function replacementHumanoid(m,entry,speed)
  local old=entry.humanoid
  local replacement=m.env.Instance.new("Humanoid");replacement.Name="Humanoid";replacement.WalkSpeed=speed or 19
  replacement.AutoRotate=true;replacement.PlatformStand=false;replacement.Health=100;replacement.Parent=entry.character
  old.Parent=nil
  return old,replacement
 end
 -- Property-storage double only: native WalkSpeed is documented as float.
 -- This rounds assigned numbers to IEEE float32; it does not simulate physics.
 local function floatWalkSpeed(h)
  local base=getmetatable(h);local meta=table.clone(base)
  local state={writes=0,reject=false};local bytes=buffer.create(4)
  meta.__newindex=function(object,key,value)
   if key=="WalkSpeed" then
    state.writes+=1
    if state.reject then value=16 end
    buffer.writef32(bytes,0,value);value=buffer.readf32(bytes,0)
   end
   return base.__newindex(object,key,value)
  end
  setmetatable(h,meta)
  return state
 end
 local function server(m,source)
  local env=m.env;local player=m.services.Players.LocalPlayer
  local storage=env.Instance.new("Folder");storage.Name="ReplicatedStorage"
  local oldService=env.game.GetService
  function env.game:GetService(name) if name=="ReplicatedStorage" then return storage end;return oldService(self,name) end
  m.services.RunService.Heartbeat=m.signal()
  local oldNew=env.Instance.new
  env.Instance.new=function(class)
   local node=oldNew(class)
   if class=="RemoteFunction" then node.InvokeServer=function(self,r) return self.OnServerInvoke(player,r) end end
   if class=="RemoteEvent" then node.OnServerEvent=m.signal();node.FireServer=function(self,...) self.OnServerEvent:Fire(player,...) end end
   return node
  end
  local root=player.Character:FindFirstChild("HumanoidRootPart")
  root.SetNetworkOwner=function() end;root.SetNetworkOwnershipAuto=function() end
  m.serverScript=env.Instance.new("Script");local previousScript=env.script;env.script=m.serverScript
  local chunk=assert(loadstring(source,"OwnedMovementServerV32.double"));setfenv(chunk,env);chunk();env.script=previousScript
  return storage
 end
 local function bridgeFixture(m,a)
  local env=m.env;local player=m.services.Players.LocalPlayer
  local storage=env.Instance.new("Folder");storage.Name="ReplicatedStorage"
  local oldService=env.game.GetService
  function env.game:GetService(name) if name=="ReplicatedStorage" then return storage end;return oldService(self,name) end
  m.world:SetAttribute("SEDWAREMovementProtocolVersion",1);player:SetAttribute("SEDWAREMovementAuthorized",true)
  local calls={control=0,input=0}
  local function remotes(label)
   local control=env.Instance.new("RemoteFunction");control.Name="SEDWAREMovementControl";control.Parent=storage
   local input=env.Instance.new("RemoteEvent");input.Name="SEDWAREMovementInput";input.Parent=storage
   control.InvokeServer=function(_,request)
    calls.control+=1
    player:SetAttribute("SEDWAREMovementToken",request.token)
    player:SetAttribute("SEDWAREServerFlyActive",request.fly);player:SetAttribute("SEDWAREServerSpeedActive",request.speed and not request.fly)
    return {ok=true,reason=label.." API confirmation; no native physics"}
   end
   input.FireServer=function() calls.input+=1 end
   return control,input
  end
  local control,input=remotes("first")
  local config=assert(a.Modules.Config.new({MovementMode="Server",Speed=true}))
  local report={world=m.world,player=player}
  local bridge=a.Modules.MovementBridge.new(config,report)
  local character=player.Character;local entry={character=character,humanoid=character:FindFirstChildOfClass("Humanoid"),root=character:FindFirstChild("HumanoidRootPart")}
  return bridge,entry,storage,control,input,calls,remotes
 end
 test("requested speed ranges accept every V3.2 example and reject non-finite/out-of-range",function(m,a)
  for _,speed in {16,24,35,50,75,100,140} do check(a.Modules.Config.new({WalkSpeed=speed})~=nil) end
  for _,speed in {25,50,65,100,150} do check(a.Modules.Config.new({FlySpeed=speed})~=nil) end
  for _,speed in {0,141,math.huge,0/0} do check(a.Modules.Config.new({WalkSpeed=speed})==nil) end
  check(a.Modules.Config.new({FlyOrientationResponsiveness=4})==nil)
 end)
 test("local Speed uses configured values and restores actual original 19",function(m,a)
  local s=localSession(m,a);local h=s.registry.entries[s.player].humanoid;h.WalkSpeed=19
  check(s:configure("Speed",true))
  for _,value in {16,24,35,50,75,100,140} do check(s:configure("WalkSpeed",value));near(h.WalkSpeed,value) end
  local writes=s.speed.writes;for _=1,120 do m:advance(1/60) end;near(s.speed.writes,writes)
  check(s:configure("Speed",false));near(h.WalkSpeed,19);check(h.Name=="Humanoid")
 end)
 test("local Speed external corrections remain untouched through 120 frames and off",function(m,a)
  local s=localSession(m,a);local h=s.registry.entries[s.player].humanoid
  check(s:configure("Speed",true));local writes=s.speed.writes;h.WalkSpeed=7
  for _=1,120 do m:advance(1/60) end
  check(s.speed.limited and not s.speed.active);near(h.WalkSpeed,7);near(s.speed.writes,writes)
  check(s:configure("Speed",false));near(h.WalkSpeed,7)
 end)
 test("local decimal Speed accepts float32 readback without repeated writes or restoring external corrections",function(m,a)
  local s=localSession(m,a,{WalkSpeed=34.2});local h=s.registry.entries[s.player].humanoid
  local storage=floatWalkSpeed(h);h.WalkSpeed=19.3;local original=h.WalkSpeed
  check(s:configure("Speed",true));check(h.WalkSpeed~=34.2,"fixture must reproduce native float storage precision")
  for _,requested in {16.1,34.2,139.9} do
   check(s:configure("WalkSpeed",requested));near(h.WalkSpeed,requested,1e-4)
   check(s.speed.active and not s.speed.limited and s.speed.applied==h.WalkSpeed and s.speed.configured==requested)
   local writes=storage.writes
   for _=1,120 do m:advance(1/60) end
   check(storage.writes==writes and s.speed.active and not s.speed.limited,"float noise rewrote or falsely limited Speed")
  end
  check(s:configure("Speed",false));near(h.WalkSpeed,original)
  check(s:configure("WalkSpeed",24));check(s:configure("Speed",true));h.WalkSpeed=7
  local writes=storage.writes;for _=1,120 do m:advance(1/60) end
  check(s.speed.limited and not s.speed.active and storage.writes==writes);near(h.WalkSpeed,7)
  check(s:configure("Speed",false));near(h.WalkSpeed,7)
  check(s:configure("WalkSpeed",34.2));storage.reject=true;check(s:configure("Speed",true))
  check(s.speed.limited and not s.speed.active and s.speed.applied==nil);near(h.WalkSpeed,16)
  writes=storage.writes;for _=1,120 do m:advance(1/60) end
  check(storage.writes==writes);check(s:configure("Speed",false));near(h.WalkSpeed,16);check(storage.writes==writes)
 end)
 test("local Speed replaces Humanoid and restores each original without name changes",function(m,a)
  local s=localSession(m,a);local entry=s.registry.entries[s.player];entry.humanoid.WalkSpeed=19
  check(s:configure("Speed",true));local old,new=replacementHumanoid(m,entry,22);m:advance(.05)
  check(s.speed.humanoid==new);near(old.WalkSpeed,19);near(new.WalkSpeed,24)
  check(s:configure("Speed",false));near(new.WalkSpeed,22);check(new.Name=="Humanoid" and old.Name=="Humanoid")
 end)
 test("local Fly restarts safely on same-root Humanoid replacement",function(m,a)
  local s=localSession(m,a);local entry=s.registry.entries[s.player];local root=entry.root
  check(s:configure("Fly",true));local prior=s.fly.constraint;local old,new=replacementHumanoid(m,entry)
  m:advance(.05);check(s.fly.root==root and s.fly.humanoid==new and s.fly.active)
  check(prior._destroyed and s.fly.constraint~=prior);check(new.PlatformStand and not new.AutoRotate)
  check(not old.PlatformStand and old.AutoRotate)
  near(m:liveInstances("LinearVelocity"),1);near(m:liveInstances("Attachment"),1)
  check(s:configure("Fly",false));check(not new.PlatformStand and new.AutoRotate)
  near(m:liveInstances("LinearVelocity"),0);near(m:liveInstances("Attachment"),0)
 end)
 test("externally removed Fly constraint resumes with one owned controller",function(m,a)
  local s=localSession(m,a);check(s:configure("Fly",true));local prior=s.fly.constraint;prior:Destroy();m:advance(.05)
  check(s.fly.active and s.fly.constraint~=prior and s.fly.constraint.Parent==s.fly.root)
  near(m:liveInstances("LinearVelocity"),1);near(m:liveInstances("Attachment"),1)
 end)
 test("Fly orientation is upright finite configurable and shares its sole attachment",function(m,a)
  local s=localSession(m,a);check(s:configure("Fly",true));local attachment=s.fly.attachment;local linear=s.fly.constraint
  local orient=s.fly.orientation;check(orient and orient:IsA("AlignOrientation"))
  check(orient.Mode==m.env.Enum.OrientationAlignmentMode.OneAttachment and orient.Attachment0==attachment)
  check(orient.AlignType==m.env.Enum.AlignType.AllAxes)
  near(orient.MaxTorque,100000);near(orient.MaxAngularVelocity,6);near(orient.Responsiveness,15)
  check(not orient.RigidityEnabled and not orient.ReactionTorqueEnabled)
  m.camera.CFrame=m.env.CFrame.lookAt(m.env.Vector3.zero,m.env.Vector3.new(1,2,-1),m.env.Vector3.yAxis);m:advance(.05)
  local flat=orient.CFrame.LookVector;near(flat.Y,0);near(flat.Magnitude,1);near(orient.CFrame.RightVector.Y,0)
  m.camera.CFrame=m.env.CFrame.lookAt(m.env.Vector3.zero,m.env.Vector3.yAxis,m.env.Vector3.zAxis);m:advance(.05)
  near((orient.CFrame.LookVector-flat).Magnitude,0)
  check(s:configure("FlyMaxTorque",200000));check(s:configure("FlyMaxAngularVelocity",4));check(s:configure("FlyOrientationResponsiveness",12));m:advance(.05)
  near(orient.MaxTorque,200000);near(orient.MaxAngularVelocity,4);near(orient.Responsiveness,12)
  check(s:configure("FlyOrientation",false));m:advance(.05);check(s.fly.orientation==nil and orient._destroyed)
  check(s.fly.attachment==attachment and s.fly.constraint==linear)
  check(s:configure("FlyOrientation",true));m:advance(.05);check(s.fly.orientation and s.fly.orientation~=orient)
  near(m:liveInstances("AlignOrientation"),1);near(m:liveInstances("Attachment"),1)
  check(s:configure("Fly",false));near(m:liveInstances("AlignOrientation"),0);near(m:liveInstances("Attachment"),0)
 end)
 test("Fly live speed updates drive requested vector and smooth release stops",function(m,a)
  local s=localSession(m,a,{FlySmoothing=0});check(s:configure("Fly",true));m:key("W")
  for _,speed in {25,50,65,100,150} do
   check(s:configure("FlySpeed",speed));m:advance(1/60);near(s.fly.constraint.VectorVelocity.Magnitude,speed)
  end
  m:key("W",false,true);check(s:configure("FlySmoothing",.1));m:advance(.05)
  check(s.fly.velocity.Magnitude>0 and s.fly.velocity.Magnitude<150)
  for _=1,120 do m:advance(1/60) end;check(s.fly.velocity.Magnitude<.001)
  check(s:configure("Fly",false));near(m:liveInstances("LinearVelocity"),0)
 end)
 test("Fly suspends and restores Speed before normal walking resumes",function(m,a)
  local s=localSession(m,a);local h=s.registry.entries[s.player].humanoid;h.WalkSpeed=19
  check(s:configure("WalkSpeed",140));check(s:configure("Speed",true));near(h.WalkSpeed,140)
  check(s:configure("Fly",true));near(h.WalkSpeed,19);check(not s.speed.active)
  check(s:configure("Fly",false));near(h.WalkSpeed,140)
  check(s:configure("Speed",false));near(h.WalkSpeed,19)
 end)
 test("bridge removal clears cached confirmations and replacement resends same request",function(m,a)
  local b,e,_,control,input,calls,remotes=bridgeFixture(m,a)
  b:sync(e);b:step(.1);check(b.active and b.serverSpeed);near(calls.control,1)
  control.Parent=nil;input.Parent=nil;b:step(.11)
  check(not b.available and not b.active and not b.serverFly and not b.serverSpeed and b.wanted==nil)
  remotes("replacement");b:step(.7);check(b.available);b:sync(e);b:step(.81)
  near(calls.control,2);check(b.active and b.serverSpeed and b.reason:find("replacement",1,true))
  b:destroy()
 end)
 test("bridge protocol removal clears flags while old remotes still exist",function(m,a)
  local b,e=bridgeFixture(m,a);b:sync(e);b:step(.1);check(b.serverSpeed)
  m.world:SetAttribute("SEDWAREMovementProtocolVersion",nil);b:step(.11)
  check(not b.available and not b.active and not b.serverSpeed)
  m.world:SetAttribute("SEDWAREMovementProtocolVersion",1);b:step(.7);b:sync(e);b:step(.81);check(b.active and b.serverSpeed)
  b:destroy()
 end)
 test("bridge input exceptions are retained without throwing through render",function(m,a)
  local b,e,_,_,input=bridgeFixture(m,a);b:sync(e)
  input.FireServer=function() error("deliberate owned input failure") end
  check(pcall(function() b:step(.1) end));check(not b.active and not b.serverSpeed)
  check(b.state=="SERVER_REJECTED" and b.reason:find("deliberate owned input failure",1,true))
  b:destroy()
 end)
 test("bridge ignores late response from replaced component",function(m,a)
  local b,e,_,control,input,calls,remotes=bridgeFixture(m,a)
  control.InvokeServer=function()
   control.Parent=nil;input.Parent=nil;remotes("new generation")
   b:refresh();b:sync(e)
   return {ok=false,reason="obsolete response"}
  end
  b:sync(e);b:step(.1)
  near(calls.control,1);check(b.active and b.serverSpeed)
  check(b.reason:find("new generation",1,true) and not b.reason:find("obsolete",1,true));b:destroy()
 end)
 test("bridge retries a changed authorization or anchored-ready context only",function(m,a)
  local b,e,_,control,_,calls=bridgeFixture(m,a)
  local original=control.InvokeServer
  control.InvokeServer=function(self,request)
   if m.services.Players.LocalPlayer:GetAttribute("SEDWAREMovementAuthorized")~=true or e.root.Anchored then calls.control+=1;return {ok=false,reason="Owned fixture unavailable"} end
   return original(self,request)
  end
  m.services.Players.LocalPlayer:SetAttribute("SEDWAREMovementAuthorized",false);b:sync(e);check(not b.active)
  b:sync(e);near(calls.control,1)
  m.services.Players.LocalPlayer:SetAttribute("SEDWAREMovementAuthorized",true);b:sync(e);check(b.active);near(calls.control,2)
  e.root.Anchored=true;b:sync(e);check(not b.active);near(calls.control,3)
  e.root.Anchored=false;b:sync(e);check(b.active);near(calls.control,4);b:destroy()
 end)
 test("owned server accepts 140 and rejects 141 then restores original speed",function(m,a)
  server(m,serverSource);local s=a.init({MovementMode="Server",WalkSpeed=140,WelcomeNotification=false})
  local h=s.registry.entries[s.player].humanoid;h.WalkSpeed=19
  check(s:configure("Speed",true));m:advance(.11);check(s.movementBridge.active);near(h.WalkSpeed,140)
  check(s.player:GetAttribute("SEDWAREServerSpeedActive")==true);near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),140)
  local control=s.movementBridge.control
  local result=control.OnServerInvoke(s.player,{token="invalid-range",fly=false,speed=true,flySpeed=65,walkSpeed=141,maxForce=100000})
  check(not result.ok);near(h.WalkSpeed,140)
  check(s:configure("Speed",false));m:advance(.11);near(h.WalkSpeed,19);near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),0)
 end)
 test("owned server records external override without rewriting or false active flag",function(m,a)
  server(m,serverSource);local s=a.init({MovementMode="Server",WelcomeNotification=false});local h=s.registry.entries[s.player].humanoid
  check(s:configure("Speed",true));m:advance(.11);near(h.WalkSpeed,24);h.WalkSpeed=7
  for _=1,40 do m:advance(.05);m.services.RunService.Heartbeat:Fire() end
  near(h.WalkSpeed,7);check(s.player:GetAttribute("SEDWAREServerSpeedActive")==false)
  near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),0)
  check(s.player:GetAttribute("SEDWAREServerSpeedReason"):find("changed externally",1,true));check(s.speed.limited and not s.speed.active)
  check(s:configure("Speed",false));m:advance(.11);near(h.WalkSpeed,7)
  check(s.player:GetAttribute("SEDWAREServerSpeedReason")=="")
 end)
 test("owned server decimal Speed captures float32 readback and preserves real corrections",function(m,a)
  server(m,serverSource);local s=a.init({MovementMode="Server",WalkSpeed=34.2,WelcomeNotification=false})
  local h=s.registry.entries[s.player].humanoid;local storage=floatWalkSpeed(h);h.WalkSpeed=19.3;local original=h.WalkSpeed
  check(s:configure("Speed",true));m:advance(.11);check(h.WalkSpeed~=34.2,"fixture must round assigned WalkSpeed")
  for _,requested in {16.1,34.2,139.9} do
   check(s:configure("WalkSpeed",requested));m:advance(.11);m:advance(.11)
   near(h.WalkSpeed,requested,1e-4);near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),h.WalkSpeed)
   check(s.player:GetAttribute("SEDWAREServerSpeedActive")==true and s.speed.active and not s.speed.limited,
    "decimal speed state: "..tostring(requested).." "..tostring(s.player:GetAttribute("SEDWAREServerSpeedActive")).." "..tostring(s.speed.active).." "..tostring(s.speed.reason).." "..tostring(s.movementBridge.reason))
   local writes=storage.writes
   for _=1,120 do m:advance(1/60);m.services.RunService.Heartbeat:Fire() end
   check(storage.writes==writes and s.speed.active and not s.speed.limited,"server fought float32 noise")
  end
  check(s:configure("Speed",false));m:advance(.11);near(h.WalkSpeed,original)
  check(s:configure("WalkSpeed",24));check(s:configure("Speed",true));m:advance(.11);h.WalkSpeed=7
  local writes=storage.writes
  for _=1,120 do m:advance(1/60);m.services.RunService.Heartbeat:Fire() end
  check(storage.writes==writes and s.speed.limited and not s.speed.active);near(h.WalkSpeed,7)
  check(s.player:GetAttribute("SEDWAREServerSpeedActive")==false);near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),0)
  check(s:configure("Speed",false));m:advance(.11);near(h.WalkSpeed,7)
  check(s:configure("WalkSpeed",34.2));storage.reject=true;check(s:configure("Speed",true));m:advance(.11);m:advance(.11)
  check(s.speed.limited and not s.speed.active);near(h.WalkSpeed,16)
  check(s.player:GetAttribute("SEDWAREServerSpeedActive")==false);near(s.player:GetAttribute("SEDWAREAppliedWalkSpeed"),0)
  check(s.player:GetAttribute("SEDWAREServerSpeedReason"):find("requested value not accepted",1,true))
  writes=storage.writes
  for _=1,120 do m:advance(1/60);m.services.RunService.Heartbeat:Fire() end
  check(storage.writes==writes);check(s:configure("Speed",false));m:advance(.11);near(h.WalkSpeed,16);check(storage.writes==writes)
 end)
 test("owned v1 requests retain safe orientation defaults and velocity-only yaw while idle",function(m,a)
  local storage=server(m,serverSource);local p=m.services.Players.LocalPlayer
  local control=storage:FindFirstChild("SEDWAREMovementControl");local input=storage:FindFirstChild("SEDWAREMovementInput")
  -- Exact pre-V3.2 request shape: orientation fields are deliberately absent.
  local request={token="legacy-v1-fields",fly=true,speed=false,flySpeed=65,walkSpeed=24,maxForce=100000}
  check(control.OnServerInvoke(p,request).ok)
  local root=p.Character:FindFirstChild("HumanoidRootPart");local orient=root:FindFirstChild("SEDWAREServerFlyOrientation")
  check(orient and orient.Mode==m.env.Enum.OrientationAlignmentMode.OneAttachment)
  check(orient.Attachment0==root:FindFirstChild("SEDWAREServerFlyAttachment"))
  near(orient.MaxTorque,100000);near(orient.MaxAngularVelocity,6);near(orient.Responsiveness,15)
  m.env.task.wait(.05);input.OnServerEvent:Fire(p,request.token,m.env.Vector3.new(20,0,0));near((orient.CFrame.LookVector-m.env.Vector3.xAxis).Magnitude,0)
  m.env.task.wait(.05);input.OnServerEvent:Fire(p,request.token,m.env.Vector3.zero);near((orient.CFrame.LookVector-m.env.Vector3.xAxis).Magnitude,0)
  m.env.task.wait(.05);input.OnServerEvent:Fire(p,request.token,m.env.Vector3.new(0,20,0));near((orient.CFrame.LookVector-m.env.Vector3.xAxis).Magnitude,0)
  request.fly=false;check(control.OnServerInvoke(p,request).ok);near(m:liveInstances("AlignOrientation"),0)
 end)
 test("owned server honors orientation false and validates every optional bound",function(m,a)
  local storage=server(m,serverSource);local p=m.services.Players.LocalPlayer;local control=storage:FindFirstChild("SEDWAREMovementControl")
  local request={token="orientation-config",fly=true,speed=false,flySpeed=65,walkSpeed=24,maxForce=100000,
   flyOrientation=false,maxTorque=200000,maxAngularVelocity=4,orientationResponsiveness=12}
  check(control.OnServerInvoke(p,request).ok);near(m:liveInstances("AlignOrientation"),0)
  for _,invalid in {{"flyOrientation","true"},{"maxTorque",math.huge},{"maxTorque",999},{"maxAngularVelocity",0},{"maxAngularVelocity",21},{"orientationResponsiveness",0},{"orientationResponsiveness",4},{"orientationResponsiveness",101}} do
   local bad=table.clone(request);bad[invalid[1]]=invalid[2];check(not control.OnServerInvoke(p,bad).ok)
  end
  m.env.task.wait(.05);request.flyOrientation=true;check(control.OnServerInvoke(p,request).ok)
  local orient=p.Character:FindFirstChild("HumanoidRootPart"):FindFirstChild("SEDWAREServerFlyOrientation")
  near(orient.MaxTorque,200000);near(orient.MaxAngularVelocity,4);near(orient.Responsiveness,12)
 end)
 test("decreasing live server FlySpeed cannot send smoothing velocity above its new limit",function(m,a)
  server(m,serverSource);local s=a.init({MovementMode="Server",FlySpeed=150,FlySmoothing=.1,WelcomeNotification=false})
  check(s:configure("Fly",true));m:key("W")
  for _=1,75 do m:advance(.02);m.services.RunService.Heartbeat:Fire() end
  check(s.fly.active and s.fly.velocity.Magnitude>149)
  check(s:configure("FlySpeed",25));m:advance(.02)
  check(s.fly.velocity.Magnitude<=25+1e-8,"old smoothed velocity exceeds new own-server limit")
  for _=1,75 do m:advance(.02);m.services.RunService.Heartbeat:Fire() end
  check(s.movementBridge.active and s.player:GetAttribute("SEDWAREServerFlyActive")==true,"speed edit expired the valid controller through rejected inputs")
  local linear=s.registry.entries[s.player].root:FindFirstChild("SEDWAREServerFlyVelocity")
  check(linear~=nil and linear.VectorVelocity.Magnitude<=25+1e-8)
 end)
 test("owned server releases anchored character and restarts when unanchored",function(m,a)
  server(m,serverSource);local s=a.init({MovementMode="Server",WelcomeNotification=false});local e=s.registry.entries[s.player]
  check(s:configure("Speed",true));m:advance(.11);near(e.humanoid.WalkSpeed,24)
  e.root.Anchored=true;m.services.RunService.Heartbeat:Fire();near(e.humanoid.WalkSpeed,16)
  m:advance(.11);check(not s.movementBridge.active)
  e.root.Anchored=false;m:advance(.11);m:advance(.11)
  check(s.movementBridge.active and s.speed.active);near(e.humanoid.WalkSpeed,24)
 end)
 print(string.format("SEDWARE V3.2 movement bundle/owned-server doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3.2 movement regressions failed")
end
