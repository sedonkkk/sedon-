-- Actual bundle + actual server source, explicit API doubles; no native physics.
return function(reloadBundle,serverSource)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(v,m) checks+=1;assert(v,m or "V3 assertion failed") end
 local function near(a,b,e) check(math.abs(a-b)<(e or 1e-8),tostring(a).." ~= "..tostring(b)) end
 local function test(name,body)
  tests+=1;local m=Mock.new();local api=reloadBundle(m.env)
  local ok,reason=pcall(body,m,api)
  if not ok then failures+=1;print("FAIL V3 "..name..": "..tostring(reason)) end
  api.Unload()
 end
 test("13.15 and 14.20 convert once with independent axes",function(m,a)
  local v=m.env.Vector3;local s=a.init({Enabled=true,MemoryTracking=false,VerticalControl=false,ReversalDamping=false})
  s.prediction:observe(0,v.zero,"Running");s.prediction:observe(.1,v.new(1,2,3),"Running")
  local p=s.prediction:predict(v.zero,.1);near(p.predictionX,.1205);near(p.predictionY,.08)
  check(s:configure("PredictionX",14.20));p=s.prediction:predict(v.zero,.1)
  near(p.predictionX,14.20*.1205/13.15);near(p.predictionY,.08)
  check(s.config.PredictionX==14.20 and s.ui.controls.PredictionX.Text=="14.20")
  check(s:configure("PredictionY",14.20));near(s.prediction:predict(v.zero,.1).predictionY,14.20*.08/13.15)
  check(not s:configure("ReferenceScale",0));check(not s:configure("MaxScale",13))
  check(s:configure("MaxPredictionX",.1));check(s.prediction:predict(v.zero,.1).calibrationClamped)
  near(s.config.PredictionX,14.20) -- bounded internal horizon does not rewrite user scale
 end)
 test("non-prediction edits preserve automatic policy slew",function(m,a)
  local s=a.init({Enabled=true,AutoPrediction=true});local v=m.env.Vector3
  s.prediction:observe(0,v.zero,"Running");s.prediction:samplePing(.06,0)
  local p=s.prediction:predict(v.zero,0);local base=s.prediction.prediction.policies.active.baseX
  s:configure("ESP",true);s:configure("FlySpeed",80)
  near(s.prediction.prediction.policies.active.baseX,base)
 end)
 test("ESP dependency and rejection counters are explicit",function(m,a)
  local v=m.env.Vector3;m:addPlayer("Visible",v.new(0,0,-60));m:addPlayer("Far",v.new(0,0,-600))
  local s=a.init({ESP=true});m:advance(.6)
  check(s.ui.espStatus.Text:find("Choose",1,true)~=nil and s.esp.stats.active==0)
  s:configure("Hitboxes",true);s:configure("Names",true);m:advance(.6)
  check(s.esp.stats.visible==1 and s.esp.stats.active==2 and s.esp.stats.outOfRange==1)
  local r=s.esp.renderers[m.services.Players:GetPlayers()[2]]
  check(r.box.Adornee:IsA("BasePart") and r.billboard.Adornee.Name=="Head")
  check(r.label.TextSize>=14 and r.billboard.Enabled and r.box.Visible)
  s:configure("ESP",false);m:advance(.6);check(s.esp.stats.active==0)
 end)
 test("unavailable movement is visible and anchored character cannot activate",function(m,a)
  function m.services.RunService:IsStudio() return false end
  local s=a.init();m:advance(.6);check(s.ui.controls.Fly.Text=="UNAVAILABLE")
  check(not s:configure("Fly",true));s:configure("MovementAuthorized",true)
  s.registry.entries[s.player].root.Anchored=true
  check(s:configure("Fly",true));m:advance(.6)
  check(not s.fly.active and s:GetMovementDiagnostics().Fly.reason:find("unanchored",1,true))
  check(s.ui.controls.Fly.Text=="UNAVAILABLE")
 end)
 test("smart persistence pauses temporarily then releases on occlusion",function(m,a)
  local target=m:addPlayer("Target",m.env.Vector3.new(0,0,-50))
  local s=a.init({Enabled=true,SmartSelection=true,TargetGraceSeconds=.2,HitPart="HumanoidRootPart"});check(s:GetLockedTarget()==target)
  local blocker=m.env.Instance.new("Part");blocker.Parent=m.env.workspace
  m:setOccluded(target,true);m:advance(.11);check(s:GetLockedTarget()==target and s.retentionPaused)
  m:setOccluded(target,false);m:advance(.11);check(s:GetLockedTarget()==target and not s.retentionPaused)
  m:setOccluded(target,true);for _=1,5 do m:advance(.11) end;check(s:GetLockedTarget()==nil)
 end)
 test("all angular modes remain level finite and bounded at four FPS",function(m,a)
  local Config=a.Modules.Config;local Controller=a.Modules.CameraController;local V,F=m.env.Vector3,m.env.CFrame
  for _,mode in {"Fixed","Adaptive","Critical"} do for _,fps in {30,60,120,144} do
   local c=Controller.new(assert(Config.new({TrackingMode=mode})))
   local cam={CFrame=F.new(V.zero)};local oldError=math.huge
   for i=1,fps*2 do
    check(c:update(cam,V.new(50,20,-50),1/fps));local d=c:GetDiagnostics()
    check(math.abs(cam.CFrame.RightVector.Y)<1e-6 and cam.CFrame.UpVector.Y>=0)
    check(d.angularError<=oldError+1e-5,mode.." fps="..fps.." i="..i.." error="..d.angularError.." previous="..oldError)
    oldError=d.angularError
   end
   check(oldError<.05);c:reset();check(c.yawVelocity==0 and c.pitchVelocity==0)
  end end
 end)
 test("optional filters reset teleports and reject bad samples",function(m,a)
  for _,filter in {"AlphaBeta","OneEuro"} do
   local s=a.init({Enabled=true,MotionFilter=filter});local v=m.env.Vector3;local e=s.prediction
   for i=0,10 do check(e:observe(i/30,v.new(i*.3,0,-40),"Running")) end
   local prior=e.history:latest();check(not e:observe(.4,v.new(0/0,0,0),"Running"));check(e.history:latest()==prior)
   check(e:observe(.5,v.new(100,10,-40),"Jumping"));near(e.filter.position.X,100)
   check(e.history:latest().position.X==100 and e.history.velocity.Magnitude==0)
   check(e:predict(v.zero,2)==nil);s:destroy()
  end
 end)
 -- Execute the real server component against explicit event/API doubles.
 test("owned server validates commands, applies/restores movement and cleans TTL",function(m,a)
  local env=m.env;local player=m.services.Players.LocalPlayer
  local storage=env.Instance.new("Folder");storage.Name="ReplicatedStorage"
  local getService=env.game.GetService
  function env.game:GetService(name) if name=="ReplicatedStorage" then return storage end;return getService(self,name) end
  m.services.RunService.Heartbeat=m.signal()
  local oldNew=env.Instance.new
  env.Instance.new=function(class)
   local node=oldNew(class)
   if class=="RemoteFunction" then node.InvokeServer=function(self,r) return self.OnServerInvoke(player,r) end end
   if class=="RemoteEvent" then node.OnServerEvent=m.signal();node.FireServer=function(self,...) self.OnServerEvent:Fire(player,...) end end
   return node
  end
  local root=player.Character:FindFirstChild("HumanoidRootPart")
  local owner="auto";root.SetNetworkOwner=function(_,value) owner=value end;root.SetNetworkOwnershipAuto=function() owner="auto" end
  local chunk=assert(loadstring(serverSource));setfenv(chunk,env);chunk()
  local control=storage:FindFirstChild("SEDWAREMovementControl");local input=storage:FindFirstChild("SEDWAREMovementInput")
  local s=a.init({DebugMode=true});check(s.movementBridge.available)
  check(s:configure("Speed",true));m:advance(.04);near(s.registry.entries[player].humanoid.WalkSpeed,24)
  check(s.movementBridge.active);m:advance(.11);check(s.speed.active)
  check(s:configure("Fly",true));m:advance(.04)
  local lv=root:FindFirstChild("SEDWAREServerFlyVelocity");check(lv and lv:IsA("LinearVelocity"));check(owner==nil)
  check(root:FindFirstChild("SEDWAREFlyVelocity")==nil,"client duplicated server constraints")
  m:key("Space");for _=1,20 do m:advance(.05) end
  check(lv.VectorVelocity.Y>1 and s.fly.active)
  input.OnServerEvent:Fire(player,s.movementBridge.token,env.Vector3.new(math.huge,0,0));check(lv.VectorVelocity.Y<66)
  m:key("Space",false,true);s:configure("Fly",false);m:advance(.04)
  check(root:FindFirstChild("SEDWAREServerFlyVelocity")==nil and owner=="auto")
  near(s.registry.entries[player].humanoid.WalkSpeed,24)
  s:configure("Speed",false);m:advance(.04);near(s.registry.entries[player].humanoid.WalkSpeed,16)
  local bad=control.OnServerInvoke(player,{token="bad",fly=true,speed=false,flySpeed=999,walkSpeed=24});check(not bad.ok)
  s:configure("Speed",true);m:advance(.04)
  env.task.wait(1);m.services.RunService.Heartbeat:Fire();near(s.registry.entries[player].humanoid.WalkSpeed,16)
  check(player:GetAttribute("SEDWAREServerSpeedActive")==false)
  m:respawn(player,env.Vector3.new(0,0,0))
  root=player.Character:FindFirstChild("HumanoidRootPart")
  root.SetNetworkOwner=function(_,value) owner=value end;root.SetNetworkOwnershipAuto=function() owner="auto" end
  m:advance(.11);m:advance(.11);near(s.registry.entries[player].humanoid.WalkSpeed,24)
  check(s.speed.active,"server movement preference did not recover on respawn")
  root.GetNetworkOwnershipAuto=function() return false end;root.GetNetworkOwner=function() return player end
  s:configure("Fly",true);m:advance(.11);m:advance(.11)
  check(root:FindFirstChild("SEDWAREServerFlyVelocity")~=nil)
  s:destroy();check(root:FindFirstChild("SEDWAREServerFlyVelocity")==nil)
  check(owner==player and player.Character:FindFirstChildOfClass("Humanoid").PlatformStand==false)
  player:SetAttribute("SEDWAREMovementAuthorized",false);m:advance(.04)
  check(not control.OnServerInvoke(player,{token="x",fly=false,speed=true,flySpeed=65,walkSpeed=24}).ok)
 end)
 print(string.format("SEDWARE V3 bundle/server doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3 regressions failed")
end
