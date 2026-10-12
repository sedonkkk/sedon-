--!nonstrict
-- Numerical orientation tests through injected CFrame operations. These verify
-- the controller contract with the official Luau CLI, not native Roblox behavior.
local V=require("./Vector")
local Controller=require("../src/cam/CameraController")
local zero=V.new(0,0,0)
local tests,checks,failures=0,0,0
local function check(value,message)
 checks+=1
 assert(value,message or "assertion failed")
end
local function near(value,expected,tolerance,message)
 check(type(value)=="number" and value==value and math.abs(value-expected)<=(tolerance or 1e-9),
  (message or "numeric mismatch")..": "..tostring(value).." expected "..tostring(expected))
end
local function vectorNear(value,expected,tolerance,message)
 check(value~=nil and (value-expected).Magnitude<=(tolerance or 1e-9),message or "vector mismatch")
end
local function test(name,body)
 tests+=1
 local ok,message=pcall(body)
 if not ok then failures+=1;print("FAIL "..name..": "..tostring(message)) end
end
local function cross(a,b)
 return V.new(a.Y*b.Z-a.Z*b.Y,a.Z*b.X-a.X*b.Z,a.X*b.Y-a.Y*b.X)
end
local function normalize(v) return v/v.Magnitude end

-- A quaternion test adapter supplies angular slerp rather than interpolating
-- view vectors linearly. This keeps elapsed-time comparisons mathematically
-- meaningful for the same-axis orientation steps used below.
local function frame(position,q)
 local w,x,y,z=q[1],q[2],q[3],q[4]
 return {Position=position,q=q,
  RightVector=V.new(1-2*(y*y+z*z),2*(x*y+w*z),2*(x*z-w*y)),
  UpVector=V.new(2*(x*y-w*z),1-2*(x*x+z*z),2*(y*z+w*x)),
  LookVector=-V.new(2*(x*z+w*y),2*(y*z-w*x),1-2*(x*x+y*y))}
end
local function matrixQuaternion(right,up,back)
 local m00,m01,m02=right.X,up.X,back.X
 local m10,m11,m12=right.Y,up.Y,back.Y
 local m20,m21,m22=right.Z,up.Z,back.Z
 local trace=m00+m11+m22
 if trace>0 then
  local scale=math.sqrt(trace+1)*2
  return {scale/4,(m21-m12)/scale,(m02-m20)/scale,(m10-m01)/scale}
 elseif m00>m11 and m00>m22 then
  local scale=math.sqrt(1+m00-m11-m22)*2
  return {(m21-m12)/scale,scale/4,(m01+m10)/scale,(m02+m20)/scale}
 elseif m11>m22 then
  local scale=math.sqrt(1+m11-m00-m22)*2
  return {(m02-m20)/scale,(m01+m10)/scale,scale/4,(m12+m21)/scale}
 else
  local scale=math.sqrt(1+m22-m00-m11)*2
  return {(m10-m01)/scale,(m02+m20)/scale,(m12+m21)/scale,scale/4}
 end
end
local callbacks={newVector=V.new}
function callbacks.lookAt(position,target,up)
 local look=normalize(target-position)
 local right=cross(look,up)
 assert(right.Magnitude>1e-6,"lookAt received parallel direction and up")
 right=normalize(right)
 local correctedUp=normalize(cross(right,look))
 return frame(position,matrixQuaternion(right,correctedUp,-look))
end
function callbacks.rebase(value,position) return frame(position,value.q) end
function callbacks.lerp(a,b,alpha)
 local qa,qb=a.q,b.q
 local cosine=0
 for i=1,4 do cosine+=qa[i]*qb[i] end
 local sign=if cosine<0 then -1 else 1
 cosine=math.clamp(math.abs(cosine),-1,1)
 local wa,wb
 if cosine>0.9995 then wa,wb=1-alpha,alpha
 else
  local theta=math.acos(cosine)
  wa,wb=math.sin((1-alpha)*theta)/math.sin(theta),math.sin(alpha*theta)/math.sin(theta)
 end
 local q,length={},0
 for i=1,4 do q[i]=qa[i]*wa+qb[i]*wb*sign;length+=q[i]*q[i] end
 length=math.sqrt(length)
 for i=1,4 do q[i]/=length end
 return frame(a.Position+(b.Position-a.Position)*alpha,q)
end
local function initial(position)
 return frame(position or zero,{1,0,0,0})
end
local function camera(position)
 return {CFrame=initial(position),CameraType="Custom",CameraSubject={},Focus=initial()}
end
local function controller(smoothness)
 return Controller.new({Smoothness=if smoothness==nil then 0.405 else smoothness},callbacks)
end
local function yaw(value) return math.atan2(value.LookVector.X,-value.LookVector.Z) end

test("default response closes 95 percent in about 59 milliseconds",function()
 near(Controller.timeConstant(0.405),0.019683)
 near(1-Controller.alpha(0.405,0.019683*math.log(20)),0.05)
 near(Controller.alpha(0,1/144),1)
 near(Controller.alpha(0.405,0),0)
 check(Controller.alpha(0.405,1/60)>0.57,"default follows less than 57 percent in its first 60 FPS frame")
 check(Controller.alpha(0.405,1/60)>Controller.alpha(0.8,1/60))
end)

test("angular tracking converges at equivalent elapsed time at 30 60 and 144 FPS",function()
 local target=V.new(100,0,0)
 local function run(hz)
  local c,cam=controller(),camera()
  local now,duration=0,0.065
  while now<duration-1e-12 do
   local dt=math.min(1/hz,duration-now)
   -- Roblox camera resets its orientation BEFORE our post-camera render step.
   cam.CFrame=initial()
   check(c:update(cam,target,dt))
   now+=dt
  end
  return yaw(cam.CFrame)
 end
 local expected=math.pi/2*(1-math.exp(-0.065/0.019683))
 local slow,normal,fast=run(30),run(60),run(144)
 near(slow,expected,2e-5)
 near(normal,expected,2e-5)
 near(fast,expected,2e-5)
 near(slow,fast,2e-5)
 check(fast>math.pi/2*0.95,"tracking remains behind despite sufficient elapsed time")
end)

test("irregular deltaTime and a stalled frame preserve elapsed-time response",function()
 local c,cam=controller(0.8),camera()
 local elapsed=0
 for _,dt in {0.003,0.014,0.009,0.081,0.006} do
  cam.CFrame=initial()
  check(c:update(cam,V.new(0,0,100),dt))
  elapsed+=dt
 end
 near(math.abs(yaw(cam.CFrame)),math.pi*(1-math.exp(-elapsed/(0.12*0.8*0.8))),2e-5)
 check(Controller.alpha(0.405,10)<=1)
end)

test("Smoothness is live and instant mode follows the selected predicted point",function()
 local config={Smoothness=1}
 local c,cam=Controller.new(config,callbacks),camera()
 check(c:update(cam,V.new(100,0,0),1/60))
 check(yaw(cam.CFrame)<math.pi/4)
 config.Smoothness=0
 check(c:update(cam,V.new(0,20,-40),1/144))
 vectorNear(cam.CFrame.LookVector,normalize(V.new(0,20,-40)))
 local changed={Smoothness=0.7}
 check(c:setConfig(changed))
 check(c.config==changed)
 check(not c:setConfig(false))
 check(c.config==changed)
end)

test("only orientation changes while camera position and control properties survive",function()
 local c,cam=controller(),camera(V.new(4,3,2))
 local cameraType,subject,focus=cam.CameraType,cam.CameraSubject,cam.Focus
 for i=1,5 do
  local livePosition=V.new(i*3,i,-i)
  cam.CFrame=initial(livePosition)
  check(c:update(cam,V.new(100,0,-10),1/60))
  vectorNear(cam.CFrame.Position,livePosition,0)
  check(cam.CameraType==cameraType and cam.CameraSubject==subject and cam.Focus==focus)
 end
end)

test("replacement Camera starts from its own live orientation",function()
 local c,old=controller(),camera()
 check(c:update(old,V.new(100,0,0),0.1))
 local replacement=camera(V.new(5,0,0))
 check(c:update(replacement,V.new(105,0,0),1/60))
 near(yaw(replacement.CFrame),math.pi/2*Controller.alpha(0.405,1/60))
 vectorNear(replacement.CFrame.Position,V.new(5,0,0),0)
 check(c.camera==replacement)
end)

test("vertical aim and crossing a pole produce orthogonal finite camera axes",function()
 local c,cam=controller(0),camera()
 for _,goal in {V.new(0,100,0),V.new(0,100,0.001),V.new(0,100,-0.001),V.new(0,-100,0),V.new(0,0,100)} do
  -- Near a pole, heading is held within the documented small cone. Exiting
  -- it can require a bounded yaw transition instead of an instantaneous flip.
  for _=1,16 do
   check(c:update(cam,goal,1/60))
   near(cam.CFrame.RightVector.Y,0,1e-8)
   check(cam.CFrame.UpVector.Y>=-1e-9,"vertical transition inverted the horizon")
  end
  vectorNear(cam.CFrame.LookVector,normalize(goal),4e-4)
  near(cam.CFrame.LookVector:Dot(cam.CFrame.UpVector),0,1e-8)
  near(cam.CFrame.RightVector.Magnitude,1,1e-8)
  near(cam.CFrame.UpVector.Magnitude,1,1e-8)
 end
 -- Vertical turns also remain well-defined while smoothed.
 c:setConfig({Smoothness=0.405});c:reset();cam.CFrame=initial()
 for _=1,12 do check(c:update(cam,V.new(0,100,0),1/60)) end
 check(cam.CFrame.LookVector.Y>0.999)
end)

test("direction reversals change response immediately without a target position filter",function()
 local c,cam=controller(),camera()
 check(c:update(cam,V.new(100,0,0),1/60))
 local previous=yaw(cam.CFrame)
 check(previous>0)
 check(c:update(cam,V.new(-100,0,0),1/60))
 check(yaw(cam.CFrame)<0,"camera did not reverse toward the newly predicted point")
end)

test("invalid target dt configuration and camera inputs never commit a frame",function()
 local c,cam=controller(),camera()
 local current=cam.CFrame
 for _,dt in {0,-0.001,0/0,math.huge,-math.huge,"bad"} do
  local ok,message=c:update(cam,V.new(100,0,0),dt)
  check(not ok and type(message)=="string")
  check(cam.CFrame==current)
 end
 for _,goal in {zero,V.new(0/0,0,0),V.new(0,math.huge,0),{},false} do
  local ok,message=c:update(cam,goal,1/60)
  check(not ok and type(message)=="string")
  check(cam.CFrame==current)
 end
 check(not c:update(nil,V.new(100,0,0),1/60))
 check(not c:update({CFrame={}},V.new(100,0,0),1/60))
 for _,smoothness in {-1,1.001,0/0,math.huge,"bad"} do
  c.config.Smoothness=smoothness
  check(not c:update(cam,V.new(100,0,0),1/60))
  check(cam.CFrame==current)
 end
 check(Controller.alpha(0.405,-1)==nil)
 check(c.camera==nil and c.lastFrame==nil)
end)

test("engine errors are reported and reset never restores an old camera frame",function()
 local broken={newVector=V.new,rebase=callbacks.rebase,lerp=callbacks.lerp,
  lookAt=function() error("lookAt rejected") end}
 local cam=camera()
 local current=cam.CFrame
 local failed,message=Controller.new({Smoothness=0.405},broken):update(cam,V.new(100,0,0),1/60)
 check(not failed and string.find(message,"lookAt rejected",1,true)~=nil)
 check(cam.CFrame==current)
 local c=controller()
 check(c:update(cam,V.new(100,0,0),1/60))
 local live=initial(V.new(7,8,9))
 cam.CFrame=live
 c:reset()
 check(cam.CFrame==live)
 check(c.camera==nil and c.lastFrame==nil)
 check(c:update(cam,V.new(107,8,9),1/60))
 near(yaw(cam.CFrame),math.pi/2*Controller.alpha(0.405,1/60))
 current=cam.CFrame
 c:destroy()
 check(cam.CFrame==current and c.lastFrame==nil and c.camera==nil)
end)

print(string.format("CAM camera: %d tests, %d assertions, %d failures",tests,checks,failures))
assert(failures==0,"CAM camera numerical tests failed")
