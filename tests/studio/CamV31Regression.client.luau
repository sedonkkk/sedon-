--!nonstrict
-- Native runner prepared for Studio. Direct handler calls and synthetic ESP
-- roster/characters are explicit fixtures, not real user input or real accounts.
-- Prepared only: Linux compilation does not execute this runner in Roblox.
-- Manual visual/input checklist after the automated run:
-- 1. Press real C with a second Studio client in first/third person; check the
--    selected Hit Part, pink DOT, yaw/pitch, and unchanged free mouse behavior.
-- 2. Observe repeated jumps, apex, descent/landing, zigzag and close crossings;
--    record angular/phase diagnostics. These are camera checks, not confirmed hits.
-- 3. Click/drag/minimize on MAIN/MISC, resize the viewport and respawn while dragging.
-- 4. Compare pink ROOT boxes, names and wall occlusion at 350/750/1500 studs with
--    VisibleOnly and explicitly authorized AlwaysOnTop. No real collider is resized.
-- 5. Repeat in a separately owned StreamingEnabled=true place with a real second
--    client walking beyond streaming radius, then returning. The missing-character
--    fixture below verifies safe handling, not actual network streaming.
-- 6. Measure MicroProfiler/FPS with ESP off/on and 5/15/30 actual players. The
--    synthetic roster costs below do not establish multiplayer performance.
local players=game:GetService("Players")
local storage=game:GetService("ReplicatedStorage")
local run=game:GetService("RunService")
local player=players.LocalPlayer
local API=require(assert(storage:WaitForChild("SedwareCamLock",8)))
API.Unload()
local started=os.clock()
while workspace:GetAttribute("SEDWAREMovementProtocolVersion")~=1 and os.clock()-started<8 do task.wait(0.05) end
local tests,checks,failures=0,0,0
local function check(value,message) checks+=1;assert(value,message or "Native V3.1 invariant failed") end
local function near(value,expected,tolerance) check(math.abs(value-expected)<=(tolerance or 1e-5),tostring(value).." ~= "..tostring(expected)) end
local function test(name,body)
 tests+=1
 local ok,issue=xpcall(body,debug.traceback)
 if ok then print("[SEDWARE][NativeV31][PASSED] "..name)
 else failures+=1;warn("[SEDWARE][NativeV31][FAILED] "..name..": "..tostring(issue)) end
end
local session=API.init({Enabled=false,DebugMode=true,MovementMode="Server"})
local function waitUntil(predicate,message)
 local limit=os.clock()+5
 while not predicate() and os.clock()<limit do task.wait(.05) end
 check(predicate(),message or "Native V3.1 timeout")
end
local function character()
 local limit=os.clock()+8
 while os.clock()<limit do
  local model=player.Character
  local humanoid=model and model:FindFirstChildOfClass("Humanoid")
  local root=model and model:FindFirstChild("HumanoidRootPart")
  if root and humanoid and humanoid.Health>0 then return model,humanoid,root end
  task.wait(0.05)
 end
 error("Native character readiness timeout")
end
local function movementState(field,expected)
 waitUntil(function()
  local report=session:GetMovementDiagnostics()
  return report[field].state==expected and session.ui.controls[field].Text==expected
 end,field.." diagnostics and GUI did not reach "..expected)
end
print("[SEDWARE][NativeV31][RUNNING] Prepared native UI/physics/adornments runner; synthetic input and rosters are labeled")
test("MAIN MISC minimize restore values and actual TweenService",function()
 check(session.ui.controls.CamPrediction==nil and session.config.CamPrediction==nil)
 check(session.ui.title.Text=="SEDWARE V3.1" and session.ui.version.Text=="v3.1")
 near(session.ui.panel.Size.X.Offset,420);near(session.ui.panel.Size.Y.Offset,520)
 near(session.config.Radius,180);near(session.config.PredictionX,13.15);near(session.config.PredictionY,13.15)
 check(session.ui.animations.service~=nil)
 session.ui:setTab("MISC");session.ui:setMinimized(true);task.wait(0.25)
 near(session.ui.panel.Size.Y.Offset,56)
 check(not session.ui.pages.MISC.Visible and not session.ui.tabs.Visible)
 session.ui:setMinimized(false);task.wait(0.25)
 check(session.ui.pages.MISC.Visible and session.ui.tab=="MISC")
 near(session.ui.panel.Size.Y.Offset,520)
 session.ui:setTab("MAIN")
end)
test("popup is outside rows and clipping with all three options",function()
 session.ui:_openDropdown("HitPart");task.wait(0.18)
 check(session.ui.dropdown.Visible and session.ui.dropdown.Parent==session.ui.popupLayer)
 check(session.ui.dropdown.ZIndex>session.ui.controls.PredictionX.ZIndex)
 for _,button in session.ui.popupButtons do check(button.Visible and button.Active) end
 session.ui:closeDropdown();task.wait(0.18);check(not session.ui.dropdown.Visible)
end)
test("targetless notification pipeline suppresses search outcomes",function()
 for _=1,100 do check(not session.notifications:notify("No valid target inside Radius",workspace:GetServerTimeNow(),2)) end
 check(#session.notifications.queue<=4)
end)
test("key capture conflict validation via real native Enum values",function()
 session.keybinds:capture("FlyKeybind")
 session.keybinds:_began({KeyCode=Enum.KeyCode.G},false)
 check(session.keybinds.capturing=="FlyKeybind")
 session.keybinds:_began({KeyCode=Enum.KeyCode.B},false)
 check(session.config.FlyKeybind==Enum.KeyCode.B and session.keybinds.capturing==nil)
 session:configure("FlyKeybind",Enum.KeyCode.V)
end)
test("Speed property restoration and no per-frame rewrites",function()
 local model,humanoid=character();local original=humanoid.WalkSpeed
 check(session:configure("Speed",true));waitUntil(function() return session.movementBridge.active and humanoid.WalkSpeed==24 end,"Server did not confirm/apply Speed")
 movementState("Speed","SERVER AUTHORIZED")
 local writes=session.speed.writes
 local root=model:FindFirstChild("HumanoidRootPart");local before=root.Position
 local name="SEDWARE_NATIVE_SPEED_PROBE"
 run:BindToRenderStep(name,Enum.RenderPriority.Last.Value+1,function() humanoid:Move(Vector3.xAxis,false) end)
 local ok,issue=xpcall(function()
  task.wait(.8)
  check((root.Position-before).Magnitude>5,"Speed property changed but native character did not move")
  waitUntil(function() return (player:GetAttribute("SEDWAREMeasuredHorizontalSpeed") or 0)>1 end,"Server did not observe physical walking")
 end,debug.traceback)
 run:UnbindFromRenderStep(name);humanoid:Move(Vector3.zero,false);check(ok,issue)
 near(session.speed.writes,writes)
 check(session:configure("Speed",false));waitUntil(function() return humanoid.WalkSpeed==original end,"Server did not restore speed")
 movementState("Speed","OFF")
end)
test("Fly uses native LinearVelocity and actual physics then restores humanoid",function()
 local model,humanoid,root=character()
 local auto,platform=humanoid.AutoRotate,humanoid.PlatformStand
 check(session:configure("Fly",true))
 session.keybinds.keys[session.config.FlyUpKey]=true
 for _=1,24 do run.RenderStepped:Wait() end
 waitUntil(function() return session.fly.active and root:FindFirstChild("SEDWAREServerFlyVelocity")~=nil end,"Server Fly unavailable")
 local constraint=root:FindFirstChild("SEDWAREServerFlyVelocity")
 waitUntil(function() return constraint.VectorVelocity.Y>1 end,"server did not apply upward movement")
 check(constraint:IsA("LinearVelocity"))
 waitUntil(function() return root.AssemblyLinearVelocity.Y>1 end,"native physics did not produce upward velocity")
 waitUntil(function() return (player:GetAttribute("SEDWAREMeasuredVerticalSpeed") or 0)>1 end,"Server did not observe actual upward motion")
 movementState("Fly","SERVER AUTHORIZED")
 session.keybinds:clear();check(session:configure("Fly",false))
 waitUntil(function() return root:FindFirstChild("SEDWAREServerFlyVelocity")==nil end,"Server Fly did not clean up")
 check(humanoid.AutoRotate==auto and humanoid.PlatformStand==platform)
 movementState("Fly","OFF")
end)
test("three real server respawns preserve GUI and clear interrupted drag",function()
 local gui=session.gui;local reset=assert(storage:WaitForChild("SEDWAREV2TestRespawn",8))
 for _=1,3 do
  local old=character()
  local p=session.ui.header.AbsolutePosition
  session.ui:_startDrag({UserInputType=Enum.UserInputType.MouseButton1,Position=Vector3.new(p.X+8,p.Y+8,0)})
  check(session.ui.drag~=nil)
  reset:FireServer() -- owned test remote, validated by CamV2Grant.server
  local deadline=os.clock()+8
  while player.Character==old and os.clock()<deadline do task.wait(0.05) end
  check(player.Character~=old,"owned server respawn timed out")
  character();check(session.gui==gui and session.ui.drag==nil and not session.destroyed)
  session.ui:setTab("MISC");session.ui:setTab("MAIN")
  task.wait(1.05)
 end
end)
test("explicit Local route is separate from the own server route",function()
 check(session:configure("Fly",false));check(session:configure("Speed",false))
 waitUntil(function()
  return player:GetAttribute("SEDWAREServerFlyActive")~=true and player:GetAttribute("SEDWAREServerSpeedActive")~=true
 end,"Own server did not disable movement before route change")
 check(session:configure("MovementMode","Local"))
 check(session:configure("LocalMovementAllowed",true))
 local report=session:GetMovementDiagnostics()
 check(report.mode=="Local" and report.permitted,"Local permission/route did not apply")
 check(run:IsStudio(),"This prepared runner must run in an owned Studio test")
 movementState("Fly","OFF");movementState("Speed","OFF")
end)
test("local Speed moves natively and GUI reports physical confirmation",function()
 local _,humanoid,root=character();local original=humanoid.WalkSpeed
 waitUntil(function() return humanoid.FloorMaterial~=Enum.Material.Air end,"Character did not land before Speed probe")
 local before=root.Position
 check(session:configure("WalkSpeed",24));check(session:configure("Speed",true))
 waitUntil(function() return session.speed.active and humanoid.WalkSpeed==24 end,"Local Speed property not applied")
 local writes=session.speed.writes
 local name="SEDWARE_NATIVE_LOCAL_SPEED_PROBE"
 run:BindToRenderStep(name,Enum.RenderPriority.Last.Value+1,function() humanoid:Move(Vector3.xAxis,false) end)
 local ok,issue=xpcall(function()
  task.wait(.8)
  check((root.Position-before).Magnitude>5,"Local Speed property changed without actual displacement")
  waitUntil(function() return session:GetMovementDiagnostics().Speed.effective end,"Physical local walking was not observed")
  movementState("Speed","LOCAL ACTIVE")
  near(session.speed.writes,writes)
 end,debug.traceback)
 run:UnbindFromRenderStep(name);humanoid:Move(Vector3.zero,false)
 check(session:configure("Speed",false));waitUntil(function() return humanoid.WalkSpeed==original end)
 movementState("Speed","OFF");check(ok,issue)
end)
test("local Speed does not overwrite an external WalkSpeed change",function()
 local _,humanoid=character();local original=humanoid.WalkSpeed
 check(session:configure("Speed",true));waitUntil(function() return humanoid.WalkSpeed==24 end)
 local writes=session.speed.writes
 humanoid.WalkSpeed=7 -- deliberate local override fixture; no claim about server replication
 for _=1,60 do run.RenderStepped:Wait() end
 near(humanoid.WalkSpeed,7);near(session.speed.writes,writes)
 check(not session:GetMovementDiagnostics().Speed.effective)
 movementState("Speed","SERVER LIMITED")
 check(session:configure("Speed",false));near(humanoid.WalkSpeed,7)
 humanoid.WalkSpeed=original -- restore the runner's own deliberate override
 movementState("Speed","OFF")
end)
test("local Fly uses native LinearVelocity and real upward displacement",function()
 local _,humanoid,root=character()
 local auto,platform=humanoid.AutoRotate,humanoid.PlatformStand
 local before=root.Position
 check(session:configure("Fly",true))
 session.keybinds.keys[session.config.FlyUpKey]=true -- handler/input fixture, not a physical keypress
 local ok,issue=xpcall(function()
  waitUntil(function() return root:FindFirstChild("SEDWAREFlyVelocity")~=nil end,"Local constraint missing")
  local constraint=root:FindFirstChild("SEDWAREFlyVelocity")
  check(constraint:IsA("LinearVelocity") and constraint.Attachment0~=nil)
  check(root:FindFirstChild("SEDWAREServerFlyVelocity")==nil,"Server and local constraints overlap")
  waitUntil(function() return constraint.VectorVelocity.Y>1 and root.AssemblyLinearVelocity.Y>1 end,"Local physics did not rise")
  waitUntil(function() return root.Position.Y-before.Y>2 end,"Local Fly did not produce actual upward displacement")
  check(session:GetMovementDiagnostics().Fly.effective)
  movementState("Fly","LOCAL ACTIVE")
 end,debug.traceback)
 session.keybinds:clear();check(session:configure("Fly",false))
 waitUntil(function() return root:FindFirstChild("SEDWAREFlyVelocity")==nil and root:FindFirstChild("SEDWAREFlyAttachment")==nil end)
 check(humanoid.AutoRotate==auto and humanoid.PlatformStand==platform)
 movementState("Fly","OFF");check(ok,issue)
end)
test("local movement respawn cleans constraints and reapplies preference",function()
 local gui=session.gui;local _,oldHumanoid,oldRoot=character()
 check(session:configure("Fly",true))
 waitUntil(function() return oldRoot:FindFirstChild("SEDWAREFlyVelocity")~=nil end)
 local old=player.Character;local reset=assert(storage:WaitForChild("SEDWAREV2TestRespawn",8))
 reset:FireServer() -- only this repository's owned server test remote
 local deadline=os.clock()+8
 while player.Character==old and os.clock()<deadline do task.wait(.05) end
 check(player.Character~=old,"Local movement respawn timed out")
 local _,newHumanoid,newRoot=character()
 waitUntil(function() return newRoot:FindFirstChild("SEDWAREFlyVelocity")~=nil end,"Local Fly preference did not reapply")
 check(oldRoot:FindFirstChild("SEDWAREFlyVelocity")==nil and oldRoot:FindFirstChild("SEDWAREFlyAttachment")==nil)
 check(oldHumanoid~=newHumanoid and session.gui==gui and session.config.Fly)
 check(next(session.keybinds.keys)==nil,"Respawn retained movement input")
 check(session:configure("Fly",false));waitUntil(function() return newRoot:FindFirstChild("SEDWAREFlyVelocity")==nil end)
 check(session:configure("Speed",true));waitUntil(function() return newHumanoid.WalkSpeed==24 end)
 local secondOld=player.Character;task.wait(1.05);reset:FireServer()
 deadline=os.clock()+8
 while player.Character==secondOld and os.clock()<deadline do task.wait(.05) end
 check(player.Character~=secondOld,"Local Speed respawn timed out")
 local _,lastHumanoid=character()
 waitUntil(function() return session.speed.active and lastHumanoid.WalkSpeed==24 end,"Local Speed preference did not reapply")
 check(session.gui==gui and session.config.Speed and not session.destroyed)
 check(session:configure("Speed",false));movementState("Speed","OFF")
end)
local fixtures={}
-- Freeze only the owned test camera during the ESP fixtures. This prevents the
-- default camera moving with our local physics probes from changing the benchmark.
local espCamera=assert(workspace.CurrentCamera)
local previousCamera={frame=espCamera.CFrame,kind=espCamera.CameraType,subject=espCamera.CameraSubject}
local _,_,probeRoot=character()
espCamera.CameraType=Enum.CameraType.Scriptable
local viewOrigin=probeRoot.Position+Vector3.new(0,10,0)
espCamera.CFrame=CFrame.lookAt(viewOrigin,viewOrigin+Vector3.new(0,0,-1))
local function cleanupFixtures()
 for _,model in fixtures do model:Destroy() end;table.clear(fixtures)
end
local function roster(count)
 local registry={list={},entries={}}
 local camera=assert(workspace.CurrentCamera)
 for index=1,count do
  local model=Instance.new("Model");model.Name="ESP_SimulatedFixture_"..index;table.insert(fixtures,model)
  local root=Instance.new("Part");root.Name="HumanoidRootPart";root.Size=Vector3.new(2,2,1);root.Anchored=true
  root.CanCollide=false;root.CFrame=camera.CFrame*CFrame.new((index-(count+1)/2)*2,0,-70);root.Parent=model
  local head=Instance.new("Part");head.Name="Head";head.Size=Vector3.one;head.Anchored=true;head.CanCollide=false
  head.CFrame=root.CFrame*CFrame.new(0,2,0);head.Parent=model
  local humanoid=Instance.new("Humanoid");humanoid.RequiresNeck=false;humanoid.BreakJointsOnDeath=false;humanoid.Parent=model;model.Parent=workspace
  local simulated={Name="ESP_SimulatedFixture_"..index,UserId=-index}
  local entry={player=simulated,username=string.lower(simulated.Name),character=model,root=root,head=head,humanoid=humanoid}
  table.insert(registry.list,entry);registry.entries[simulated]=entry
 end
 function registry:lookup(username)
  for _,entry in self.list do if entry.username==string.lower(username) then return entry end end
 end
 return registry
end
test("native ESP range gates 350, 750 and 1500 studs",function()
 cleanupFixtures();local registry=roster(1);local entry=registry.list[1]
 local config=assert(API.Modules.Config.new({ESP=true,Names=true,Hitboxes=true,ESPLowPerformanceMode=false}))
 local manager=API.Modules.ESPManager.new(config,session.report,registry)
 local originalSize=entry.root.Size
 local ok,issue=xpcall(function()
  for _,row in {{350,300,true},{350,700,false},{750,700,true},{750,1450,false},{1500,1450,true}} do
   config.ESPMaxDistance=row[1]
   entry.root.CFrame=espCamera.CFrame*CFrame.new(0,0,-row[2]);entry.head.CFrame=entry.root.CFrame*CFrame.new(0,2,0)
   manager:refresh();manager:update(workspace:GetServerTimeNow())
   check((manager.stats.visible==1)==row[3],"Wrong ESP range decision at "..row[1].."/"..row[2])
   if row[3] then
    local renderer=assert(manager.renderers[entry.player])
    check(renderer.box:IsA("SelectionBox") and renderer.box.Adornee==entry.root)
    check(renderer.billboard.Enabled and not renderer.billboard.AlwaysOnTop)
    near(renderer.billboard.MaxDistance,row[1])
   else check(manager.stats.outOfRange==1) end
   check(entry.root.Size==originalSize,"ESP resized a real collider")
  end
 end,debug.traceback)
 manager:destroy();cleanupFixtures();check(ok,issue)
end)
test("native VisibleOnly ray filtering and authorized AlwaysOnTop nodes",function()
 cleanupFixtures();local registry=roster(1);local entry=registry.list[1]
 local wall=Instance.new("Part");wall.Name="SEDWARE_OWNED_OCCLUSION_FIXTURE"
 wall.Anchored=true;wall.Size=Vector3.new(30,30,2);wall.CFrame=espCamera.CFrame*CFrame.new(0,0,-35)
 wall.Parent=workspace;table.insert(fixtures,wall)
 local config=assert(API.Modules.Config.new({ESP=true,Names=true,Hitboxes=true,ESPAuthorized=true,ESPLowPerformanceMode=false}))
 local manager=API.Modules.ESPManager.new(config,session.report,registry)
 local originalSize=entry.root.Size
 local ok,issue=xpcall(function()
  manager:update(workspace:GetServerTimeNow())
  check(manager.stats.occluded==1 and manager.stats.visible==0 and manager.stats.raycasts==1)
  check(manager.params.FilterType==Enum.RaycastFilterType.Exclude)
  check(table.find(manager.params.FilterDescendantsInstances,player.Character)~=nil,"Local character must be excluded from LOS ray")
  check(manager.renderers[entry.player]==nil,"Occluded first candidate unexpectedly created indicators")
  manager:destroy()
  config.ESPOcclusionMode="AlwaysOnTop"
  manager=API.Modules.ESPManager.new(config,session.report,registry)
  manager:update(workspace:GetServerTimeNow())
  check(manager.stats.visible==1 and manager.stats.raycasts==0,"Authorized AlwaysOnTop unexpectedly applied LOS culling")
  local renderer=assert(manager.renderers[entry.player])
  check(renderer.highlight:IsA("Highlight") and renderer.highlight.Enabled)
  check(renderer.highlight.DepthMode==Enum.HighlightDepthMode.AlwaysOnTop and renderer.highlight.Adornee==entry.character)
  check(renderer.screenBox:IsA("Frame") and renderer.screenBox.Visible and renderer.screenBox.Parent==manager.layer)
  check(manager.layer:IsA("ScreenGui") and manager.layer.Parent==session.report.playerGui)
  check(renderer.screenBox.Size.X.Offset>0 and renderer.screenBox.Size.Y.Offset>0)
  check(renderer.billboard.Enabled and renderer.billboard.AlwaysOnTop)
  local box,highlight,billboard=renderer.screenBox,renderer.highlight,renderer.billboard
  local created=manager.stats.created
  for _=1,20 do manager:refresh();manager:update(workspace:GetServerTimeNow()) end
  check(renderer.screenBox==box and renderer.highlight==highlight and renderer.billboard==billboard,"AlwaysOnTop nodes were not pooled")
  near(manager.stats.created,created);check(entry.root.Size==originalSize)
  config.ESP=false;manager:refresh()
  check(next(manager.renderers)==nil and manager.layer==nil)
  check(box.Parent==nil and highlight.Parent==nil and billboard.Parent==nil,"ESP disable leaked native instances")
 end,debug.traceback)
 manager:destroy();cleanupFixtures();check(ok,issue)
end)
test("streaming-style missing character safely hides and recovers native ESP",function()
 cleanupFixtures();local registry=roster(1);local entry=registry.list[1]
 local config=assert(API.Modules.Config.new({ESP=true,Names=true,Hitboxes=true}))
 local manager=API.Modules.ESPManager.new(config,session.report,registry)
 local ok,issue=xpcall(function()
  manager:update(workspace:GetServerTimeNow());local renderer=assert(manager.renderers[entry.player])
  local model,root,head,humanoid=entry.character,entry.root,entry.head,entry.humanoid
  entry.character=nil;entry.root=nil;entry.head=nil;entry.humanoid=nil
  manager:changed("CharacterRemoving",entry);manager:update(workspace:GetServerTimeNow())
  check(manager.stats.notReady==1 and manager.stats.visible==0)
  check(not renderer.box.Visible and renderer.box.Adornee==nil and not renderer.billboard.Enabled)
  local created=manager.stats.created
  entry.character=model;entry.root=root;entry.head=head;entry.humanoid=humanoid
  manager:changed("CharacterAdded",entry);manager:update(workspace:GetServerTimeNow())
  check(manager.renderers[entry.player]==renderer and manager.stats.visible==1)
  near(manager.stats.created,created);check(renderer.box.Adornee==root)
 end,debug.traceback)
 manager:destroy();cleanupFixtures();check(ok,issue)
end)
for _,count in {5,15,30} do
 test("native ESP cost with "..count.." simulated character fixtures",function()
  cleanupFixtures()
  local registry=roster(count)
  local config=assert(API.getModule("Config").new({ESP=true,Names=true,Hitboxes=true,ESPLowPerformanceMode=false}))
  local manager=API.getModule("ESPManager").new(config,session.report,registry)
  local ok,problem=xpcall(function()
   manager:update(workspace:GetServerTimeNow())
   local created=manager.stats.created
   local elapsed,updates=0,0
   local onStarted=os.clock()
   for frame=1,120 do
    run.RenderStepped:Wait()
    local before=manager.stats.updates;manager:update(workspace:GetServerTimeNow())
    if manager.stats.updates~=before then elapsed+=manager.stats.lastSeconds;updates+=1 end
   end
   check(manager.stats.created==created,"native ESP created indicators every frame")
   local onFPS=120/(os.clock()-onStarted)
   print(string.format("[SEDWARE][NativeV31][ESP CPU] simulated=%d meanUpdateMs=%.5f maxMs=%.5f instances=%d",
    count,elapsed/math.max(updates,1)*1000,manager.stats.maxSeconds*1000,manager.stats.created))
   check(manager:applyTarget(registry.list[1].player.Name))
   config.ESPTargetMode="Specific Player";manager:refresh();manager:update(workspace:GetServerTimeNow())
   local total=0;for _ in manager.renderers do total+=1 end;check(total<=1)
   manager:clearTarget();check(next(manager.renderers)==nil)
   config.ESP=false;manager:refresh()
   local offStarted=os.clock()
   for _=1,120 do run.RenderStepped:Wait() end
   local offFPS=120/(os.clock()-offStarted)
   print(string.format("[SEDWARE][NativeV31][FPS SAMPLE] simulated=%d ESP_ON=%.2f ESP_OFF=%.2f; local sample, not a zero-impact promise",count,onFPS,offFPS))
  end,debug.traceback)
  manager:destroy();cleanupFixtures();check(ok,problem)
 end)
end
cleanupFixtures()
espCamera.CameraType=previousCamera.kind;espCamera.CameraSubject=previousCamera.subject;espCamera.CFrame=previousCamera.frame
test("calibrated scale and independent horizons",function()
 check(session:configure("PredictionX",14.20));check(session:configure("PredictionY",13.15))
 local c=API.Modules.Config.toPredictionConfig(session.config)
 near(c.PredictionX,14.20*.1205/13.15);near(c.PredictionY,.08)
end)
test("native Vector3 vertical phase fixture bounds rising apex falling landing",function()
 local config=assert(API.Modules.Config.new({VerticalControl=true}))
 local vertical=API.Modules.VerticalControl.new(config)
 local expected={"Apex","Rising","Apex","Falling","Landing","Grounded"}
 local rows={{0,0,"Jumping"},{.05,1.5,"Jumping"},{.10,1.51,"Freefall"},{.15,.51,"Freefall"},{.20,0,"Landed"},{.35,0,"Running"}}
 for index,row in rows do
  local position=Vector3.new(index*.1,row[2],-12)
  vertical:observe(row[1],position,row[3]);check(vertical.phase==expected[index],"Synthetic phase mismatch")
  local out={predictionX=.1205,predictionY=.08,ageSeconds=.02,velocity=Vector3.new(2,100,0),
   currentPosition=position,position=position,rawPosition=position,targetPosition=position,rawTargetPosition=position}
  vertical:apply(out,row[1]);check(out.movementPhase==expected[index])
  if expected[index]~="Grounded" then
   check(math.abs(out.position.Y-position.Y)<=config.MaxVerticalLead+1e-5,"Vertical lead bound exceeded")
   check(out.verticalHorizonUsed<=.08)
  end
  if expected[index]=="Landing" then near(out.position.Y,position.Y);near(out.verticalVelocityUsed,0) end
 end
 vertical:reset();check(vertical.time==nil and vertical.phase=="Grounded")
end)
test("own humanoid real jump supplies rising falling landing observations",function()
 local _,humanoid,root=character()
 waitUntil(function() return humanoid.FloorMaterial~=Enum.Material.Air end,"Own character did not land before jump")
 check(humanoid:GetStateEnabled(Enum.HumanoidStateType.Jumping),"Owned test place disabled jumping")
 local vertical=API.Modules.VerticalControl.new(session.config)
 local startY=root.Position.Y;local phases={};local peak=0;local began=false;local landed=false
 vertical:observe(os.clock(),root.Position,tostring(humanoid:GetState()))
 humanoid.Jump=true
 local deadline=os.clock()+4
 while os.clock()<deadline do
  run.RenderStepped:Wait()
  local now=os.clock();vertical:observe(now,root.Position,tostring(humanoid:GetState()))
  phases[vertical.phase]=true;peak=math.max(peak,root.Position.Y-startY)
  began=began or peak>1
  if began and humanoid.FloorMaterial~=Enum.Material.Air and root.AssemblyLinearVelocity.Y<=1 then landed=true;break end
 end
 humanoid.Jump=false
 check(began and peak>2,"Native humanoid did not physically jump")
 check(phases.Rising and phases.Falling,"Actual jump did not supply rising/falling observations")
 check(landed and (phases.Landing or vertical.phase=="Grounded"),"Actual jump did not return to the ground")
 print(string.format("[SEDWARE][NativeV31][JUMP PHYSICS] peakStuds=%.4f apexSample=%s; own humanoid only, no impact claim",peak,tostring(phases.Apex==true)))
end)
test("native CFrame angular safety traces at 30 60 120 144 scheduled Hz",function()
 -- These are deterministic scheduled dt traces using native Camera/CFrame,
 -- not measurements of the renderer's FPS or a real networked target.
 for _,fps in {30,60,120,144} do
  local config=assert(API.Modules.Config.new({Smoothness=.405,AngularSafety=true}))
  local controller=API.Modules.CameraController.new(config)
  local camera=Instance.new("Camera");camera.CFrame=CFrame.new(Vector3.new(8000,10,8000))
  local origin=camera.CFrame.Position
  local ok,issue=xpcall(function()
   for frame=1,fps*2 do
    local t=frame/fps;local y=4*math.sin(t*math.pi)
    local target=origin+Vector3.new(1.5*math.sin(t*16),y,-5)
    local accepted,reason=controller:update(camera,target,1/fps,{movementPhase="Falling",distanceStuds=5,reversalScale=.5})
    check(accepted,reason)
    local diagnostic=controller:GetDiagnostics()
    check(math.abs(diagnostic.pitchRate)<=config.PitchMaxSpeed+.01,"Pitch exceeded safety speed")
    check(math.abs(diagnostic.roll)<.01 and math.abs(camera.CFrame.RightVector.Y)<1e-5,"Native safety trace introduced roll")
    check(camera.CFrame.UpVector.Y>=-1e-6 and camera.CFrame.Position==origin,"Native safety trace moved/inverted camera")
   end
  end,debug.traceback)
  controller:destroy();camera:Destroy();check(ok,issue)
 end
end)
test("Calibration Lab native CFrame math; synthetic trajectories",function()
 debug.profilebegin("SEDWARE Calibration Lab")
 local ok,result=pcall(function()
  return API.Modules.CalibrationLab.run({Vector=Vector3,Frame=CFrame},function(row)
   print(string.format("[SEDWARE][LAB][SYNTHETIC] %s FPS=%d ping=%d %s/%s/%s angularMean=%.5f predictionError=%.5f",
    row.scenario,row.fps,row.pingMs,row.mode,row.filter,row.policy,row.meanAngular,row.meanPredictedError))
   check(row.maxRoll<.01,"Native CFrame roll regression")
  end,{fps={30,60,120,144},ping={0,120},filters={"Memory"},duration=2})
 end)
 debug.profileend();check(ok,result)
end)
API.Unload()
check(session.destroyed and session.ui.destroyed and session.registry.destroyed and session.esp.destroyed)
print(string.format("[SEDWARE][NativeV31][SUMMARY] %d tests, %d assertions, %d failures",tests,checks,failures))
if failures>0 then error("Native V3.1 checks failed; inspect FAILED lines") end
