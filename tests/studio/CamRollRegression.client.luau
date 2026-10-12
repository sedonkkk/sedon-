--!nonstrict
-- Run this LocalScript ONLY in the separate SedwareCamRollTest Studio place.
-- Uses native CFrame/Camera and one real post-camera RenderStepped test.
-- Scheduled 30/60/120/144 deltaTimes are numerical inputs, not forced engine FPS.
local storage=game:GetService("ReplicatedStorage")
local run=game:GetService("RunService")
local world=game:GetService("Workspace")
local module=assert(storage:WaitForChild("SedwareCamLock",8),"Native roll test: missing bundled ModuleScript")
local API=require(module)
API.Unload()
local Controller=API.getModule("CameraController")
local tests,checks,failures=0,0,0
local owned={}
local function own(clean) table.insert(owned,clean) end
local function check(value,message) checks+=1;assert(value,message or "Native camera invariant failed") end
local function finite(value) return value==value and math.abs(value)<math.huge end
local function near(value,expected,tolerance,message) check(finite(value) and math.abs(value-expected)<=tolerance,message) end
local function test(name,body)
 tests+=1
 local ok,problem=xpcall(body,debug.traceback)
 if ok then print("[SEDWARE][NativeRoll][PASSED] "..name)
 else failures+=1;warn("[SEDWARE][NativeRoll][FAILED] "..name..": "..tostring(problem)) end
end
local function level(frame,position)
 for _,axis in {frame.RightVector,frame.UpVector,frame.LookVector} do
  check(finite(axis.X) and finite(axis.Y) and finite(axis.Z),"Nonfinite native camera axis")
  near(axis.Magnitude,1,1e-5,"Native axis is not unit length")
 end
 near(frame.RightVector.Y,0,1e-5,"Native horizon tilted")
 check(frame.UpVector.Y>=-1e-6,"Native camera inverted")
 near(frame.LookVector:Dot(frame.UpVector),0,1e-5,"Native look/up not orthogonal")
 near((frame.Position-position).Magnitude,0,1e-5,"Controller moved the camera")
end
local function nativeCamera()
 local camera=Instance.new("Camera")
 own(function() camera:Destroy() end)
 return camera
end
local paths={
 {"Walking left",function(t) return Vector3.new(-100*t,0,-100) end},
 {"Walking right",function(t) return Vector3.new(100*t,0,-100) end},
 {"Jumping",function(t) return Vector3.new(30*t,60*math.sin(math.pi*t),-100) end},
 {"Falling",function(t) return Vector3.new(-30*t,60-130*t,-100) end},
 {"Six elevated circles",function(t) local a=12*math.pi*t;return Vector3.new(100*math.sin(a),40,-100*math.cos(a)) end},
 {"Passing behind",function(t) local a=2*math.pi*t;return Vector3.new(100*math.sin(a),30*math.sin(2*a),-100*math.cos(a)) end},
 {"Directly above and near pole",function(t) return Vector3.new(1e-7*math.sin(t*100),100,1e-7*math.cos(t*100)) end},
 {"Directly below and near pole",function(t) return Vector3.new(1e-7*math.sin(t*100),-100,1e-7*math.cos(t*100)) end},
 {"Repeated 180-degree heading changes",function(t) return Vector3.new(0,0,if math.floor(t*10)%2==0 then -100 else 100) end},
}
print("[SEDWARE][NativeRoll][RUNNING] Native Roblox tests; scheduled deltaTime comparisons do not force runtime FPS")
for _,path in paths do
 test(path[1],function()
  for _,hz in {30,60,120,144} do
   local camera,controller=nativeCamera(),Controller.new({Smoothness=0.405})
   local position=Vector3.new(8000,15,-5000)
   for frame=0,1000 do
    -- Deliberately inject roll like an external/default camera controller.
    camera.CFrame=CFrame.new(position)*CFrame.Angles(0,0,0.7)
    local updated,reason=controller:update(camera,position+path[2](frame/1000),1/hz)
    check(updated,reason);level(camera.CFrame,position)
   end
   controller:destroy()
  end
 end)
 task.wait()
end
test("Repeated activation resets and native GUI controls",function()
 local session=API.init({Enabled=false})
 local camera,controller=nativeCamera(),Controller.new({Smoothness=0.405})
 for cycle=1,24 do
  check(session:SetEnabled(true));check(session:SetEnabled(false))
  check(session:GetLockedTarget()==nil and session.controller.lastFrame==nil)
  local position=Vector3.new(cycle,5,-cycle)
  camera.CFrame=CFrame.new(position)*CFrame.Angles(0,0,-1.2)
  check(controller:update(camera,position+Vector3.new(40,20,-100),1/60))
  level(camera.CFrame,position)
  controller:reset();check(controller.lastFrame==nil and controller.yaw==nil and controller.pitch==nil)
 end
 API.Unload();controller:destroy()
 check(session.destroyed and session.ui.destroyed and session.notifications.destroyed)
end)
test("First/third person translations and real post-camera RenderStepped",function()
 local isolated,controller=nativeCamera(),Controller.new({Smoothness=0.405})
 for index=1,80 do
  local position=if index%2==0 then Vector3.new(2,5,0.5) else Vector3.new(2,8,20)
  isolated.CFrame=CFrame.new(position)
  local subject,kind,focus=isolated.CameraSubject,isolated.CameraType,isolated.Focus
  check(controller:update(isolated,Vector3.new(50,20,-100),1/60));level(isolated.CFrame,position)
  check(isolated.CameraSubject==subject and isolated.CameraType==kind and isolated.Focus==focus)
 end
 controller:reset()
 local binding="SEDWARE_NATIVE_ROLL_REGRESSION"
 local frames,issue=0,nil
 local unbound=false
 local function unbind() if not unbound then unbound=true;run:UnbindFromRenderStep(binding) end end
 own(unbind)
 run:BindToRenderStep(binding,Enum.RenderPriority.Camera.Value+1,function(dt)
  if issue or frames>=24 then return end
  local updated,errorMessage=xpcall(function()
   local current=assert(world.CurrentCamera,"Native CurrentCamera missing")
   local position=current.CFrame.Position
   local subject,kind,focus=current.CameraSubject,current.CameraType,current.Focus
   local ok,reason=controller:update(current,position+Vector3.new(40,10,-80),dt)
   check(ok,reason);level(current.CFrame,position)
   check(current.CameraSubject==subject and current.CameraType==kind and current.Focus==focus)
   frames+=1
  end,debug.traceback)
  if not updated then issue=errorMessage end
 end)
 local started=os.clock()
 while frames<24 and not issue and os.clock()-started<5 do task.wait(0.02) end
 unbind();controller:destroy()
 check(not issue,issue);check(frames==24,"Native render test timed out before 24 engine frames")
end)
test("Scheduled 30/60/120/144 deltaTimes have equal yaw/pitch response",function()
 local results={}
 for _,hz in {30,60,120,144} do
  local camera,controller=nativeCamera(),Controller.new({Smoothness=0.405})
  local elapsed,duration=0,0.117
  while elapsed<duration-1e-10 do
   local dt=math.min(1/hz,duration-elapsed)
   camera.CFrame=CFrame.new()
   check(controller:update(camera,Vector3.new(70,40,-100),dt));level(camera.CFrame,Vector3.zero)
   elapsed+=dt
  end
  local diagnostics=controller:GetDiagnostics()
  near(diagnostics.roll,0,0.001,"Native diagnostic roll is nonzero")
  table.insert(results,camera.CFrame.LookVector)
  controller:destroy()
 end
 for index=2,#results do near((results[index]-results[1]).Magnitude,0,1e-5,"Scheduled FPS response differs") end
end)
API.Unload()
for index=#owned,1,-1 do pcall(owned[index]) end
print(string.format("[SEDWARE][NativeRoll][SUMMARY] %d tests, %d assertions, %d failures",tests,checks,failures))
if failures>0 then error("Native Roblox roll regressions failed; inspect FAILED lines above") end
