--!nonstrict
-- Mathematical regression tests for the actual CameraController through the
-- CamMock CFrame/Vector3 operations. This is not a Roblox renderer or an in-game
-- verification: every frame below is a numerical fixture supplied by this test.
local Controller = require("../src/cam/CameraController")
local CamMock = require("./CamMock")
local env = CamMock.new().env
local V, F = env.Vector3, env.CFrame
local tests, checks, failures = 0, 0, 0
local function check(value, message)
 checks += 1
 assert(value, message or "assertion failed")
end
local function near(value, expected, tolerance, message)
 check(type(value)=="number" and value==value and math.abs(value-expected)<=(tolerance or 1e-9),
  (message or "numeric mismatch")..": "..tostring(value).." expected "..tostring(expected))
end
local function test(name, body)
 tests += 1
 local ok, message = pcall(body)
 if not ok then failures += 1; print("FAIL "..name..": "..tostring(message)) end
end
local function finite(value) return value==value and math.abs(value)<math.huge end
local function wrap(value) return (value+math.pi)%(2*math.pi)-math.pi end
local function direction(yaw, pitch)
 return V.new(math.sin(yaw)*math.cos(pitch), math.sin(pitch), -math.cos(yaw)*math.cos(pitch))
end
local function yaw(value) return math.atan2(value.LookVector.X, -value.LookVector.Z) end
local function pitch(value) return math.asin(math.clamp(value.LookVector.Y, -1, 1)) end
local function angular(a, b) return math.acos(math.clamp(a.Unit:Dot(b.Unit), -1, 1)) end
local function levelFrame(position, heading, elevation)
 local look = direction(heading or 0, elevation or 0)
 local up = V.new(-math.sin(heading or 0)*math.sin(elevation or 0), math.cos(elevation or 0),
  math.cos(heading or 0)*math.sin(elevation or 0))
 return F.lookAt(position, position+look, up)
end
local function rolledFrame(position, heading, elevation, roll)
 local value = levelFrame(position, heading, elevation)
 return F.lookAt(position, position+value.LookVector,
  value.UpVector*math.cos(roll)+value.RightVector*math.sin(roll))
end
local function camera(position, heading, elevation, roll)
 position = position or V.zero
 return {CFrame=if roll then rolledFrame(position, heading or 0, elevation or 0, roll)
   else levelFrame(position, heading, elevation),
  Focus=F.new(V.new(0,0,-10)), CameraType="Custom", CameraSubject={name="subject"}}
end
local callbacks = {newVector=V.new, lookAt=function(position, target, up)
 check(up~=nil and finite(up.X) and finite(up.Y) and finite(up.Z), "lookAt requires finite analytic up")
 check((target-position).Unit:Cross(up.Unit).Magnitude>0.99999999, "lookAt up must remain orthogonal, including poles")
 return F.lookAt(position, target, up)
end}
local function controller(smoothness)
 return Controller.new({Smoothness=if smoothness==nil then 0.405 else smoothness}, callbacks)
end
local function signedRoll(frame)
 local reference = V.yAxis-frame.LookVector*frame.LookVector.Y
 if reference.Magnitude<1e-7 then return nil end -- Roll Euler angle is undefined at the pole.
 reference = reference.Unit
 return math.atan2(frame.LookVector:Dot(reference:Cross(frame.UpVector)), reference:Dot(frame.UpVector))
end
local function assertLevel(frame, livePosition)
 for _, vector in {frame.LookVector, frame.UpVector, frame.RightVector, frame.Position} do
  check(finite(vector.X) and finite(vector.Y) and finite(vector.Z), "camera axis/position contains NaN or infinity")
 end
 near(frame.LookVector.Magnitude, 1, 2e-9, "look length")
 near(frame.UpVector.Magnitude, 1, 2e-9, "up length")
 near(frame.RightVector.Magnitude, 1, 2e-9, "right length")
 near(frame.LookVector:Dot(frame.UpVector), 0, 2e-9, "look/up orthogonality")
 near(frame.RightVector:Dot(frame.UpVector), 0, 2e-9, "right/up orthogonality")
 near(frame.RightVector.Y, 0, 2e-9, "horizon tilted: right vertical component")
 check(frame.UpVector.Y>=-2e-12, "camera became upside down")
 local roll = signedRoll(frame)
 if roll then near(roll, 0, 2e-8, "world-up roll") end
 if livePosition then near((frame.Position-livePosition).Magnitude, 0, 0, "current camera position must be preserved exactly") end
end
local function follow(name, positionAt, count, smoothness)
 test(name, function()
  local c, cam = controller(smoothness), camera()
  for i=0,count do
   local target = positionAt(i/count)
   -- Simulate Roblox replacing the orientation before its post-camera callback.
   cam.CFrame=levelFrame(V.zero, 0, 0)
   local ok, message=c:update(cam, target, 1/60)
   check(ok, message)
   assertLevel(cam.CFrame, V.zero)
  end
 end)
end

follow("walking left stays level at every step", function(t) return V.new(-80*t,0,-100) end, 180)
follow("walking right stays level at every step", function(t) return V.new(80*t,0,-100) end, 180)
follow("jumping target stays level while pitch increases and decreases", function(t)
 return V.new(30*t,60*math.sin(math.pi*t),-100)
end, 180)
follow("falling target stays level across positive and negative pitch", function(t)
 return V.new(-20*t,60-130*t,-100)
end, 180)
follow("six complete elevated circles do not accumulate camera roll", function(t)
 local angle=t*12*math.pi
 return V.new(100*math.sin(angle),40,-100*math.cos(angle))
end, 1440)
follow("target passes behind the camera and returns without inversions", function(t)
 local angle=t*2*math.pi
 return V.new(100*math.sin(angle),30*math.sin(2*angle),-100*math.cos(angle))
end, 480)

test("inherited roll is removed before the very first smoothed frame", function()
 for _, initialRoll in {0.2, math.pi/2, math.pi, -math.pi/2} do
  local heading, elevation = math.rad(35), math.rad(20)
  local cam, c = camera(V.zero, heading, elevation, initialRoll), controller()
  local goalYaw, goalPitch = math.rad(-70), math.rad(-25)
  check(c:update(cam, direction(goalYaw,goalPitch)*100, 1/60))
  assertLevel(cam.CFrame, V.zero)
  local alpha=Controller.alpha(0.405,1/60)
  near(wrap(yaw(cam.CFrame)-heading), wrap(goalYaw-heading)*alpha, 2e-9, "yaw starts from leveled live orientation")
  near(pitch(cam.CFrame), elevation+(goalPitch-elevation)*alpha, 2e-9, "pitch starts from live orientation")
 end
end)

test("directly above and below use a finite level basis and preserve heading", function()
 for _, heading in {0, math.rad(70), math.rad(-140)} do
  for _, sign in {1,-1} do
   local cam, c = camera(V.new(3,4,5),heading,0), controller(0)
   local initialRight = cam.CFrame.RightVector
   check(c:update(cam, cam.CFrame.Position+V.new(0,sign*100,0), 1/60))
   assertLevel(cam.CFrame,V.new(3,4,5))
   near(cam.CFrame.LookVector.Y,sign,2e-9,"vertical direction")
   near((cam.CFrame.RightVector-initialRight).Magnitude,0,2e-8,"heading should not change at exact pole")
   for _=1,12 do
    check(c:update(cam, cam.CFrame.Position+V.new(0,sign*100,0), 1/60))
    assertLevel(cam.CFrame,V.new(3,4,5))
    near((cam.CFrame.RightVector-initialRight).Magnitude,0,2e-8,"pole should not accumulate heading error")
   end
  end
 end
end)

test("nearly vertical numerical noise does not cause arbitrary heading flips", function()
 for _, sign in {1,-1} do
  local cam, c = camera(V.zero,math.rad(55),0), controller(0)
  local initialRight=cam.CFrame.RightVector
  for _, noise in {V.zero,V.new(1e-9,0,1e-9),V.new(-1e-9,0,1e-9),V.new(1e-9,0,-1e-9),V.new(-1e-9,0,-1e-9),V.zero} do
   check(c:update(cam,V.new(0,sign*100,0)+noise,1/144))
   assertLevel(cam.CFrame,V.zero)
   check(cam.CFrame.RightVector:Dot(initialRight)>0.999999, "tiny pole noise caused heading flip")
   check(cam.CFrame.LookVector.Y*sign>0.999999999,"nearly vertical target should be tracked")
  end
 end
end)

test("near vertical visible approach exit and upper-to-lower changes remain level", function()
 local cam,c=camera(),controller()
 for _, goal in {V.new(1,90,-1),V.new(0.01,100,-0.01),V.new(0,100,0),
  V.new(-0.01,100,0.01),V.new(-1,90,1),V.new(0,-100,0),V.new(1,-90,-1),V.new(0,0,-100)} do
  for _=1,24 do
   check(c:update(cam,goal,1/60))
   assertLevel(cam.CFrame,V.zero)
  end
 end
end)

test("180 degree yaw changes are finite and level in both instant and smooth modes", function()
 for _, smoothness in {0,0.405,1} do
  local cam,c=camera(),controller(smoothness)
  for _, heading in {math.pi,0,-math.pi,0,math.pi/2,-math.pi/2} do
   for _=1,60 do
    check(c:update(cam,direction(heading,0)*100,1/60))
    assertLevel(cam.CFrame,V.zero)
   end
   check(angular(cam.CFrame.LookVector,direction(heading,0))<0.01,"camera failed to converge across reversal")
  end
 end
end)

test("yaw crosses plus/minus 180 degrees by the short path in either direction", function()
 for _, sign in {1,-1} do
  local start,goal=math.rad(179)*sign,math.rad(-179)*sign
  local cam,c=camera(V.zero,start,0),controller()
  check(c:update(cam,direction(goal,0)*100,1/60))
  assertLevel(cam.CFrame,V.zero)
  local delta=wrap(yaw(cam.CFrame)-start)
  near(delta,wrap(goal-start)*Controller.alpha(0.405,1/60),2e-9,"wrapped yaw interpolation")
  check(math.abs(delta)<math.rad(2),"camera travelled through zero instead of across wrap")
 end
end)

test("yaw and pitch smoothing has the same elapsed-time response at 30 60 120 144 FPS", function()
 local duration, goalYaw, goalPitch = 0.117,math.rad(125),math.rad(62)
 local final={}
 for _,hz in {30,60,120,144} do
  local cam,c=camera(),controller()
  local elapsed=0
  while elapsed<duration-1e-12 do
   local dt=math.min(1/hz,duration-elapsed)
   cam.CFrame=levelFrame(V.zero,0,0)
   check(c:update(cam,direction(goalYaw,goalPitch)*100,dt))
   assertLevel(cam.CFrame,V.zero)
   elapsed+=dt
  end
  local alpha=1-math.exp(-duration/Controller.timeConstant(0.405))
  near(yaw(cam.CFrame),goalYaw*alpha,2e-9,"equal-duration yaw")
  near(pitch(cam.CFrame),goalPitch*alpha,2e-9,"equal-duration pitch")
  table.insert(final,cam.CFrame.LookVector)
 end
 for i=2,#final do near((final[i]-final[1]).Magnitude,0,2e-9,"FPS output mismatch") end
end)

test("reset repeatedly discards prior yaw pitch and inherited rolled frames", function()
 local c=controller()
 for i=1,24 do
  local position=V.new(i,2+i*0.1,-i)
  local heading=if i%2==0 then math.rad(120) else math.rad(-90)
  local cam=camera(position,heading,math.rad(10),math.rad(75))
  check(c:update(cam,position+direction(heading+0.3,0.7)*100,1/60))
  assertLevel(cam.CFrame,position)
  c:reset()
  local live=rolledFrame(position,0,0,math.rad(-105))
  cam.CFrame=live
  check(c:update(cam,position+direction(math.rad(60),math.rad(-30))*100,1/60))
  assertLevel(cam.CFrame,position)
  near(yaw(cam.CFrame),math.rad(60)*Controller.alpha(0.405,1/60),2e-9,"reset leaked previous yaw")
  near(pitch(cam.CFrame),math.rad(-30)*Controller.alpha(0.405,1/60),2e-9,"reset leaked previous pitch")
  local last=cam.CFrame
  c:destroy()
  check(cam.CFrame==last,"destroy restored a previous frame")
 end
end)

test("first and third person camera positions remain the sole translation source", function()
 local cam,c=camera(),controller()
 local subject,focus,kind=cam.CameraSubject,cam.Focus,cam.CameraType
 for i=1,120 do
  local first=i%2==0
  local livePosition=if first then V.new(i*0.01,5,0.5) else V.new(i*0.01,8,20)
  cam.CFrame=rolledFrame(livePosition,math.rad(-15),math.rad(5),math.rad(80))
  check(c:update(cam,V.new(50,15,-80),1/60))
  assertLevel(cam.CFrame,livePosition)
  check(cam.CameraSubject==subject and cam.Focus==focus and cam.CameraType==kind,
   "controller changed subject focus or camera type")
 end
 local replacement=camera(V.new(10,11,12),0,0,math.rad(90))
 check(c:update(replacement,replacement.CFrame.Position+V.new(100,0,0),1/60))
 assertLevel(replacement.CFrame,V.new(10,11,12))
 near(yaw(replacement.CFrame),math.pi/2*Controller.alpha(0.405,1/60),2e-9,"replacement camera inherited old heading")
end)

test("invalid targets and failed orientation creation do not poison interpolation", function()
 local c,cam=controller(),camera()
 check(c:update(cam,V.new(20,10,-100),1/60))
 local previous=cam.CFrame
 for _,target in {V.zero,V.new(0/0,0,0),V.new(math.huge,0,0),false,{}} do
  local ok,message=c:update(cam,target,1/60)
  check(not ok and type(message)=="string","invalid target must report a reason")
  check(cam.CFrame==previous,"failed target committed a frame")
 end
 for _,dt in {0,-1,0/0,math.huge} do
  local ok,message=c:update(cam,V.new(30,10,-100),dt)
  check(not ok and type(message)=="string","invalid dt must report a reason")
  check(cam.CFrame==previous,"failed dt committed a frame")
 end
 check(c:update(cam,V.new(40,15,-100),1/60))
 assertLevel(cam.CFrame,V.zero)
 local broken=Controller.new({Smoothness=0.405},{newVector=V.new,lookAt=function()error("fixture lookAt failed")end})
 previous=cam.CFrame
 local ok,message=broken:update(cam,V.new(10,5,-80),1/60)
 check(not ok and string.find(message,"fixture lookAt failed",1,true)~=nil,"orientation error lost original cause")
 check(cam.CFrame==previous,"failed lookAt committed a frame")
end)

print(string.format("CAM roll numerical: %d tests, %d assertions, %d failures",tests,checks,failures))
assert(failures==0,"CAM roll mathematical regressions failed")
