--!nonstrict
-- V2 actual-bundle callback/lifecycle tests. These are explicit doubles, not
-- Roblox physics, server confirmations or native FPS measurements.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message) checks+=1;assert(value,message or "V2 assertion failed") end
 local function near(value,expected,tolerance) check(type(value)=="number" and value==value and math.abs(value-expected)<=(tolerance or 1e-8),tostring(value).." ~= "..tostring(expected)) end
 local function count(map) local total=0;for _ in map do total+=1 end;return total end
 local function test(name,body)
  tests+=1;local mock=Mock.new();local api=reloadBundle(mock.env)
  local ok,problem=pcall(body,mock,api,function(config) return api.init(config) end)
  if not ok then failures+=1;print("FAIL V2 "..name..": "..tostring(problem)) end
  api.Unload()
  if mock:countConnections()~=0 or mock:countRenderBindings()~=0 or mock.tweens.active~=0 then
   failures+=1;print("FAIL V2 cleanup "..name)
  end
 end
 local function edit(ui,field,value) ui.controls[field].Text=tostring(value);ui.controls[field].FocusLost:Fire(true) end
 test("search attempts and repeated C generate zero targetless notices",function(mock,api,init)
  local s=init({Enabled=true,DebugMode=true,WelcomeNotification=false})
  for _=1,100 do mock:key("C") end
  for _=1,600 do mock:advance(1/60) end
  check(s:GetLockedTarget()==nil and not s.destroyed)
  check(not mock:find("No valid target inside Radius"))
  check(s.notifications:notify("No valid target inside Radius",mock:getTime(),2)==false)
  near(#s.notifications.queue,0)
  check(mock:hasLog("[Acquisition][SEARCHING]"))
  near(mock.counters.candidateScans,1) -- initial registry enumeration only
 end)
 test("notification queue deduplicates and cooldown cache stays bounded",function(mock,api,init)
  local s=init({WelcomeNotification=false})
  local n=s.notifications
  check(n:notify("Example notice",mock:getTime(),2))
  for _=1,100 do check(not n:notify("Example notice",mock:getTime(),2)) end
  near(#n.queue,0)
  for index=1,100 do n:notify("Notice "..index,mock:getTime(),2) end
  check(#n.queue<=4 and count(n.recent)<=32)
  mock:advance(10);s:SetEnabled(true);s:SetEnabled(false);s:SetEnabled(true)
  check(n.current.subtitle~="Lock Disabled","stale OFF notice survived ON")
 end)
 test("minimize restore and tabs preserve values and suppress hidden actions",function(mock,api,init)
  local s=init({MovementAuthorized=true});local ui=s.ui
  check(ui.tab=="MAIN" and not ui.minimized)
  edit(ui,"PredictionX",0.21);edit(ui,"PredictionY",0.11)
  ui.tabButtons.MISC.Activated:Fire();check(ui.tab=="MISC" and ui.pages.MISC.Visible and not ui.pages.MAIN.Visible)
  ui.controls.Speed.Activated:Fire();check(s.config.Speed)
  ui.minimizeButton.Activated:Fire();mock:advance(0.23)
  check(ui.minimized and ui.minimizeButton.Text=="+" and not ui.tabs.Visible)
  near(ui.panel.Size.Y.Offset,56)
  ui.controls.Speed.Activated:Fire();check(s.config.Speed,"hidden toggle intercepted activation")
  ui.minimizeButton.Activated:Fire();mock:advance(0.23)
  check(not ui.minimized and ui.tab=="MISC" and ui.pages.MISC.Visible)
  near(ui.panel.Size.Y.Offset,520);near(s.config.PredictionX,0.21);near(s.config.PredictionY,0.11)
  ui.tabButtons.MAIN.Activated:Fire();mock:advance(0.20)
  check(ui.pages.MAIN.Visible and not ui.pages.MISC.Visible)
  check(ui.controls.CamPrediction==nil and s.config.CamPrediction==nil)
 end)
 test("top-layer dropdown opens above rows closes on select outside tabs and minimize",function(mock,api,init)
  local s=init();local ui=s.ui
  ui.controls.HitPart.Activated:Fire();mock:advance(0.16)
  check(ui.dropdown.Visible and ui.dropdown.Parent==ui.popupLayer)
  check(ui.dropdown.ZIndex>ui.controls.PredictionX.ZIndex)
  near(ui.dropdown.Size.Y.Offset,90)
  for _,button in ui.popupButtons do check(button.Visible and button.Active and button.ZIndex>ui.controls.PredictionY.ZIndex) end
  ui.hitPartOptions.Head.Activated:Fire();mock:advance(0.16)
  check(not ui.dropdown.Visible and s.config.HitPart=="Head")
  ui.controls.HitPart.Activated:Fire()
  mock.services.UserInputService.InputBegan:Fire({UserInputType=mock.env.Enum.UserInputType.MouseButton1,
   KeyCode=mock.env.Enum.KeyCode.Unknown,Position=mock.env.Vector3.new(0,0,0)},true)
  mock:advance(0.16);check(not ui.dropdown.Visible)
  ui.controls.HitPart.Activated:Fire();ui:setTab("MISC");check(not ui.dropdown.Visible)
  ui:setTab("MAIN");ui.controls.HitPart.Activated:Fire();ui:setMinimized(true);check(not ui.dropdown.Visible)
 end)
 test("drag state resets on five respawns and minimized header remains draggable",function(mock,api,init)
  local s=init();local ui=s.ui;local player=mock.services.Players.LocalPlayer
  mock:advance(0.30);local baseline=mock:countConnections()
  local function drag()
   local p=ui.header.AbsolutePosition
   local input={UserInputType=mock.env.Enum.UserInputType.MouseButton1,Position=mock.env.Vector3.new(p.X+8,p.Y+8,0)}
   ui.header.InputBegan:Fire(input);check(ui.drag~=nil)
   local old=ui.panel.Position
   mock.services.UserInputService.InputChanged:Fire({UserInputType=mock.env.Enum.UserInputType.MouseMovement,
    Position=mock.env.Vector3.new(p.X+25,p.Y+15,0)})
   check(ui.panel.Position.X.Offset>old.X.Offset)
   return input
  end
  for index=1,5 do
   drag();mock:respawn(player,mock.env.Vector3.new(index,0,0));check(ui.drag==nil)
   mock:advance(0.02);near(mock:countConnections(),baseline)
   local input=drag();mock.services.UserInputService.InputEnded:Fire(input);check(ui.drag==nil)
  end
  ui:setMinimized(true);mock:advance(0.23);local input=drag()
  mock.services.UserInputService.WindowFocusReleased:Fire();check(ui.drag==nil)
  check(ui.gui.Parent==mock.playerGui and not s.destroyed)
 end)
 test("Fly and Speed reject unauthorized writes and work with explicit authorization",function(mock,api,init)
  -- Studio now supplies local test permission; model a published client here
  -- to keep checking rejection without either authorization route.
  function mock.services.RunService:IsStudio() return false end
  local s=init();local hum=mock.services.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
  check(not s:configure("Fly",true));check(not s:configure("Speed",true))
  check(not s.config.Fly and not s.config.Speed);near(hum.WalkSpeed,16)
  check(s:configure("MovementAuthorized",true));check(s:configure("Speed",true));near(hum.WalkSpeed,24)
 end)
 test("Fly uses one constraint follows input updates speed and restores flags",function(mock,api,init)
  local s=init({MovementAuthorized=true});local e=s.registry.entries[s.player];local V=mock.env.Vector3
  check(s:configure("Fly",true));check(s.fly.active)
  check(e.humanoid.PlatformStand and not e.humanoid.AutoRotate)
  near(mock:liveInstances("LinearVelocity"),1);near(mock:liveInstances("Attachment"),1)
  mock:key("W");mock:advance(0.15)
  check(s.fly.constraint.VectorVelocity.Magnitude>40 and s.fly.constraint.VectorVelocity.Magnitude<=65)
  local previous=s.fly.constraint.VectorVelocity.Magnitude
  check(s:configure("FlySpeed",90));mock:advance(0.2)
  check(s.fly.constraint.VectorVelocity.Magnitude>previous)
  mock:key("W",false,true);mock:advance(0.5);check(s.fly.constraint.VectorVelocity.Magnitude<1)
  check(s:configure("Fly",false));check(not s.fly.active)
  near(mock:liveInstances("LinearVelocity"),0);near(mock:liveInstances("Attachment"),0)
  check(not e.humanoid.PlatformStand and e.humanoid.AutoRotate)
 end)
 test("Speed pauses for Fly respects server changes and does not rewrite per frame",function(mock,api,init)
  local s=init({MovementAuthorized=true});local hum=s.registry.entries[s.player].humanoid
  check(s:configure("Speed",true));near(hum.WalkSpeed,24)
  local writes=s.speed.writes
  for _=1,100 do mock:advance(1/60) end;near(s.speed.writes,writes)
  check(s:configure("Fly",true));near(hum.WalkSpeed,16)
  check(s:configure("Fly",false));near(hum.WalkSpeed,24)
  check(s:configure("WalkSpeed",30));near(hum.WalkSpeed,30)
  hum.WalkSpeed=12;for _=1,100 do mock:advance(1/60) end;near(hum.WalkSpeed,12)
  check(not s.speed.active and s.speed.limited,"external WalkSpeed override must deactivate and report the limitation")
  check(s:configure("Speed",false));near(hum.WalkSpeed,12)
 end)
 test("movement cleans old characters and resumes preferences after respawn",function(mock,api,init)
  local s=init({MovementAuthorized=true});local player=s.player
  check(s:configure("Speed",true));check(s:configure("Fly",true))
  local oldRoot=s.fly.root;mock:kill(player)
  check(not s.fly.active and not s.speed.active and oldRoot:FindFirstChild("SEDWAREFlyVelocity")==nil)
  mock:respawn(player,mock.env.Vector3.new(0,0,0));mock:advance(0.04)
  check(s.fly.active and s.fly.root~=oldRoot and s.config.Fly and s.config.Speed)
  check(s:configure("Fly",false));near(player.Character:FindFirstChildOfClass("Humanoid").WalkSpeed,24)
 end)
 test("keybind capture rejects conflicts ignores text and supports cancellation",function(mock,api,init)
  local s=init({MovementAuthorized=true});local ui=s.ui;ui:setTab("MISC")
  ui.controls.FlyKeybind.Activated:Fire();check(ui.controls.FlyKeybind.Text=="Press a key")
  mock:key("G");check(s.keybinds.capturing=="FlyKeybind" and s.config.FlyKeybind==mock.env.Enum.KeyCode.V)
  mock:key("C");check(s.keybinds.capturing=="FlyKeybind")
  mock:key("B");check(s.keybinds.capturing==nil and s.config.FlyKeybind==mock.env.Enum.KeyCode.B)
  check(not s.config.Fly);mock:key("B");check(s.config.Fly)
  ui.controls.SpeedKeybind.Activated:Fire();mock:key("B");check(s.keybinds.capturing=="SpeedKeybind")
  mock:key("Escape");check(s.keybinds.capturing==nil)
  ui.controls.WalkSpeed:CaptureFocus();mock:key("G");check(not s.config.Speed)
  ui.controls.WalkSpeed:ReleaseFocus();mock:key("G",true);check(not s.config.Speed)
  mock:key("G");check(s.config.Speed)
  ui.controls.SpeedKeybind.Activated:Fire();ui:setMinimized(true);check(s.keybinds.capturing==nil)
 end)
 test("ESP master and independent options create only required native indicators",function(mock,api,init)
  local target=mock:addPlayer("ActualUsername",mock.env.Vector3.new(0,0,-50));local root=target.Character:FindFirstChild("HumanoidRootPart")
  local sizeBefore=root.Size;local s=init()
  s:configure("Hitboxes",true);near(mock:liveInstances("SelectionBox"),0)
  s:configure("ESP",true);near(mock:liveInstances("SelectionBox"),1);near(mock:liveInstances("BillboardGui"),0)
  s:configure("Hitboxes",false);s:configure("Names",true)
  near(mock:liveInstances("SelectionBox"),0);near(mock:liveInstances("BillboardGui"),1)
  local renderer=s.esp.renderers[target]
  check(renderer.label.Text==target.Name and renderer.billboard.AlwaysOnTop==false)
  s:configure("Hitboxes",true);near(mock:liveInstances("SelectionBox"),1)
  check(root.Size==sizeBefore,"visual box resized physical collision")
  s:configure("ESP",false);near(mock:liveInstances("SelectionBox"),0);near(mock:liveInstances("BillboardGui"),0)
  check(s.config.Names and s.config.Hitboxes)
 end)
 test("Specific Player uses exact case-insensitive Username and Apply/Clear buttons",function(mock,api,init)
  local first=mock:addPlayer("ActualUsername",mock.env.Vector3.new(0,0,-50));first.DisplayName="Alias"
  local second=mock:addPlayer("OtherUsername",mock.env.Vector3.new(10,0,-50))
  local s=init({ESP=true,Names=true,WelcomeNotification=false});local ui=s.ui;ui:setTab("MISC")
  s:configure("ESPTargetMode","Specific Player");check(ui.rows.ESPUsername.Visible and ui.actionsRow.Visible)
  edit(ui,"ESPUsername","Alias");ui.applyButton.Activated:Fire();near(count(s.esp.renderers),0)
  check(mock:find("Player Username no encontrado")~=nil)
  edit(ui,"ESPUsername","Actual");check(not s:ApplyESPTarget());near(count(s.esp.renderers),0)
  edit(ui,"ESPUsername","aCtUaLuSeRnAmE");ui.applyButton.Activated:Fire();mock:advance(0.11)
  check(s.esp.renderers[first]~=nil and s.esp.renderers[second]==nil)
  ui.clearButton.Activated:Fire();near(count(s.esp.renderers),0)
  check(s.config.ESPUsername=="" and s.config.ESPTargetMode=="Specific Player" and s.config.Names)
  s:configure("ESPTargetMode","All");mock:advance(0.11);near(count(s.esp.renderers),2)
  check(not ui.rows.ESPUsername.Visible and not ui.actionsRow.Visible)
 end)
 test("specific ESP reuses visuals after target respawn and frees them on leave",function(mock,api,init)
  local target=mock:addPlayer("PersistUser",mock.env.Vector3.new(0,0,-50))
  local s=init({ESP=true,Names=true,Hitboxes=true,ESPTargetMode="Specific Player",ESPUsername="PersistUser"})
  mock:advance(0.11);local renderer=s.esp.renderers[target];check(renderer~=nil)
  local box,name=renderer.box,renderer.billboard
  mock:respawn(target,mock.env.Vector3.new(20,0,-50));mock:advance(0.11)
  check(renderer.box==box and renderer.billboard==name and box.Adornee==target.Character:FindFirstChild("HumanoidRootPart"))
  mock:removePlayer(target);near(count(s.esp.renderers),0)
  near(mock:liveInstances("SelectionBox"),0);near(mock:liveInstances("BillboardGui"),0)
 end)
 test("ESP culls distance screen depth and occlusion without forcing wall visibility",function(mock,api,init)
  local target=mock:addPlayer("CullUser",mock.env.Vector3.new(0,0,-50))
  local s=init({ESP=true,Names=true,Hitboxes=true});mock:advance(0.30)
  local renderer=s.esp.renderers[target];check(renderer and renderer.box.Visible)
  mock:setOccluded(target,true);mock:advance(0.11);check(not renderer.box.Visible and not renderer.billboard.Enabled)
  mock:setOccluded(target,false);mock:move(target,mock.env.Vector3.new(0,0,-900));mock:advance(0.11);check(not renderer.box.Visible)
  mock:move(target,mock.env.Vector3.new(0,0,100));mock:advance(0.11);check(not renderer.box.Visible)
  mock:move(target,mock.env.Vector3.new(0,0,-50));mock:advance(0.11);check(renderer.box.Visible)
 end)
 test("ESP cadence pooling and toggle churn have bounded objects and connections",function(mock,api,init)
  for index=1,15 do mock:addPlayer("PoolUser"..index,mock.env.Vector3.new(index,0,-50)) end
  local s=init({ESP=true,Names=true,Hitboxes=true});mock:advance(0.30)
  local initialCreated=s.esp.stats.created;local initialUpdates=s.esp.stats.updates;local baseline=mock:countConnections()
  mock:resetCounters()
  for _=1,144*2 do mock:advance(1/144) end
  near(s.esp.stats.created,initialCreated);check(s.esp.stats.updates-initialUpdates<=21)
  near(mock.counters.candidateScans,0);near(mock:countConnections(),baseline)
  for _=1,20 do s:configure("ESP",false);s:configure("ESP",true) end
  mock:advance(0.30)
  near(mock:liveInstances("SelectionBox"),15);near(mock:liveInstances("BillboardGui"),15)
  near(mock:countConnections(),baseline)
 end)
 test("logo resource is prepared fallback is explicit and loaded original is reused",function(mock,api,init)
  local s=init();local logo=s.ui.logo
  check(logo:FindFirstChild("TemporaryFallback").Visible)
  check(logo:FindFirstChild("OriginalLogoImage").Image=="" and not logo:GetAttribute("OriginalLogoAvailable"))
  -- Fixture ID tests validation/assignment only; it is not a published asset.
  check(s:configure("LogoAssetId","rbxassetid://123456789"))
  local image=logo:FindFirstChild("OriginalLogoImage");image.IsLoaded=true
  check(image.Visible and not logo:FindFirstChild("TemporaryFallback").Visible)
  check(s.notifications.logo:FindFirstChild("OriginalLogoImage").Image==image.Image)
  s.ui:setMinimized(true);check(s.ui.logo==logo)
  check(not s:configure("LogoAssetId","https://unknown.example/logo.png"))
 end)
 test("internal FOV has no extra control and uses the current acquisition reference",function(mock,api,init)
  local s=init();check(s.ui.fov==nil and s.ui.controls.ShowFOV==nil)
  check(s:configure("ShowFOV",true));mock:setPointer(700,400);mock:advance(0.04)
  near(s.ui.fov.Size.X.Offset,360);near(s.ui.fov.Position.X.Offset,700)
  s:configure("ShowFOV",false);mock:advance(0.04);check(s.ui.fov==nil)
 end)
 test("missing optional movement and ESP APIs report errors without disabling Cam GUI",function(mock,api,init)
  local target=mock:addPlayer("CompatibilityUser",mock.env.Vector3.new(0,0,-50))
  local s=init({MovementAuthorized=true,Enabled=true,Hitboxes=true,WelcomeNotification=false})
  local original=mock.env.Instance.new
  mock.env.Instance.new=function(class)
   if class=="LinearVelocity" or class=="SelectionBox" then error("controlled optional API unsupported") end
   return original(class)
  end
  local fly,reason=s:configure("Fly",true);check(not fly and reason:find("unsupported",1,true))
  local esp,espReason=s:configure("ESP",true);check(not esp and espReason:find("unsupported",1,true))
  check(not s.config.ESP and s.ui.controls.ESP.Text=="OFF" and not s.destroyed)
  mock.env.Instance.new=original
  mock:advance(0.04);check(s:GetLockedTarget()==target and s:GetPredictedPosition()~=nil)
  check(s:configure("ESP",true));check(s.esp.renderers[target]~=nil)
 end)
 test("viewport changes reposition the popup and preserve responsive panel bounds",function(mock,api,init)
  local s=init();local ui=s.ui
  ui.controls.HitPart.Activated:Fire();mock:advance(0.16)
  mock.camera.ViewportSize=mock.env.Vector2.new(500,420);mock:advance(0.04)
  check(ui.dropdown.Visible and ui.popupField=="HitPart")
  local p,size=ui.dropdown.Position,ui.dropdown.Size
  check(p.X.Offset>=0 and p.Y.Offset>=0)
  check(p.X.Offset+size.X.Offset<=500 and p.Y.Offset+size.Y.Offset<=420)
  check(ui.scale.Scale<=1 and ui.scale.Scale>0)
  check(ui.panel.Position.X.Offset+420*ui.scale.Scale<=500)
 end)
 test("movement bindings reject reserved keys and logo rejects forged asset URLs",function(mock,api,init)
  function mock.services.RunService:IsStudio() return false end
  local s=init()
  for _,input in {{"FlyKeybind","W"},{"FlyKeybind","C"},{"SpeedKeybind","V"},{"FlyUpKey","A"},
   {"SpeedKeybind","Unknown"},{"ESPTargetMode","ThroughWalls"},{"ESPOcclusionMode","AlwaysOnTop"}} do
   check(s:configure(input[1],input[2])==false)
  end
  check(s:configure("LogoAssetId","rbxassetid://0")==false)
  check(s:configure("CamPrediction",13.8)==false)
 end)
 print(string.format("SEDWARE V2 bundle doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V2 functional regressions failed")
end
