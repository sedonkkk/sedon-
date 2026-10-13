--!nonstrict
-- Native runner prepared for Studio. Direct handler calls and synthetic ESP
-- roster/characters are explicit fixtures, not real user input or real accounts.
local players=game:GetService("Players")
local storage=game:GetService("ReplicatedStorage")
local run=game:GetService("RunService")
local player=players.LocalPlayer
local API=require(assert(storage:WaitForChild("SedwareCamLock",8)))
API.Unload()
local started=os.clock()
while workspace:GetAttribute("SEDWAREMovementAuthorized")~=true and os.clock()-started<8 do task.wait(0.05) end
local tests,checks,failures=0,0,0
local function check(value,message) checks+=1;assert(value,message or "Native V2 invariant failed") end
local function near(value,expected,tolerance) check(math.abs(value-expected)<=(tolerance or 1e-5),tostring(value).." ~= "..tostring(expected)) end
local function test(name,body)
 tests+=1
 local ok,issue=xpcall(body,debug.traceback)
 if ok then print("[SEDWARE][NativeV2][PASSED] "..name)
 else failures+=1;warn("[SEDWARE][NativeV2][FAILED] "..name..": "..tostring(issue)) end
end
local session=API.init({Enabled=false,DebugMode=true})
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
print("[SEDWARE][NativeV2][RUNNING] Native UI/constraints/adornments; synthetic roster benchmarks are labeled explicitly")
test("MAIN MISC minimize restore values and actual TweenService",function()
 check(session.ui.controls.CamPrediction==nil and session.config.CamPrediction==nil)
 near(session.config.Radius,180);near(session.config.PredictionX,0.1205);near(session.config.PredictionY,0.08)
 check(session.ui.animations.service~=nil)
 session.ui:setTab("MISC");session.ui:setMinimized(true);task.wait(0.25)
 near(session.ui.panel.Size.Y.Offset,56)
 check(not session.ui.pages.MISC.Visible and not session.ui.tabs.Visible)
 session.ui:setMinimized(false);task.wait(0.25)
 check(session.ui.pages.MISC.Visible and session.ui.tab=="MISC")
 near(session.ui.panel.Size.Y.Offset,432)
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
 check(session:configure("Speed",true));near(humanoid.WalkSpeed,24)
 local writes=session.speed.writes
 for _=1,12 do run.RenderStepped:Wait() end
 near(session.speed.writes,writes)
 check(session:configure("Speed",false));near(humanoid.WalkSpeed,original)
end)
test("Fly uses native LinearVelocity and actual physics then restores humanoid",function()
 local model,humanoid,root=character()
 local auto,platform=humanoid.AutoRotate,humanoid.PlatformStand
 check(session:configure("Fly",true))
 session.keybinds.keys[session.config.FlyUpKey]=true
 for _=1,24 do run.RenderStepped:Wait() end
 check(session.fly.active and session.fly.constraint:IsA("LinearVelocity"))
 check(session.fly.constraint.VectorVelocity.Y>1,"native constraint did not request upward movement")
 check(root.AssemblyLinearVelocity.Y>1,"native physics did not produce upward velocity")
 session.keybinds:clear();check(session:configure("Fly",false))
 check(root:FindFirstChild("SEDWAREFlyVelocity")==nil)
 check(humanoid.AutoRotate==auto and humanoid.PlatformStand==platform)
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
local fixtures={}
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
  local humanoid=Instance.new("Humanoid");humanoid.Parent=model;model.Parent=workspace
  local simulated={Name="ESP_SimulatedFixture_"..index,UserId=-index}
  local entry={player=simulated,username=string.lower(simulated.Name),character=model,root=root,head=head,humanoid=humanoid}
  table.insert(registry.list,entry);registry.entries[simulated]=entry
 end
 function registry:lookup(username)
  for _,entry in self.list do if entry.username==string.lower(username) then return entry end end
 end
 return registry
end
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
   print(string.format("[SEDWARE][NativeV2][ESP CPU] simulated=%d meanUpdateMs=%.5f maxMs=%.5f instances=%d",
    count,elapsed/math.max(updates,1)*1000,manager.stats.maxSeconds*1000,manager.stats.created))
   check(manager:applyTarget(registry.list[1].player.Name))
   config.ESPTargetMode="Specific Player";manager:refresh();manager:update(workspace:GetServerTimeNow())
   local total=0;for _ in manager.renderers do total+=1 end;check(total<=1)
   manager:clearTarget();check(next(manager.renderers)==nil)
   config.ESP=false;manager:refresh()
   local offStarted=os.clock()
   for _=1,120 do run.RenderStepped:Wait() end
   local offFPS=120/(os.clock()-offStarted)
   print(string.format("[SEDWARE][NativeV2][FPS SAMPLE] simulated=%d ESP_ON=%.2f ESP_OFF=%.2f; local sample, not a zero-impact promise",count,onFPS,offFPS))
  end,debug.traceback)
  manager:destroy();cleanupFixtures();check(ok,problem)
 end)
end
cleanupFixtures();API.Unload()
check(session.destroyed and session.ui.destroyed and session.registry.destroyed and session.esp.destroyed)
print(string.format("[SEDWARE][NativeV2][SUMMARY] %d tests, %d assertions, %d failures",tests,checks,failures))
if failures>0 then error("Native V2 checks failed; inspect FAILED lines") end
