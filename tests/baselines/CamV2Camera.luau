--!nonstrict
-- Orientation-only camera tracking. The session runs this AFTER Roblox's camera
-- step and supplies the current Camera and the already predicted world position.
-- Prediction never passes through an additional position filter here.
local CameraController = {}
CameraController.__index = CameraController

local EPSILON = 1e-6
local TAU, HALF_PI = 2*math.pi, math.pi/2
-- Yaw is undefined at the poles. This small hysteresis cone suppresses
-- numerical noise; up to 0.023 degrees of aim error is possible inside it.
local POLE_ENTER, POLE_EXIT = 1e-4, 2e-4
local POLAR_BAND, POLAR_YAW_RATE = math.sin(math.rad(3)), math.rad(720)
local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function vectorOK(value)
 local ok,valid=pcall(function()
  return value~=nil and finite(value.X) and finite(value.Y) and finite(value.Z)
   and finite(value.Magnitude)
 end)
 return ok and valid
end
local function frameOK(value)
 local ok,valid=pcall(function()
  return value~=nil and vectorOK(value.Position) and vectorOK(value.LookVector)
   and vectorOK(value.UpVector) and vectorOK(value.RightVector)
   and value.LookVector.Magnitude>EPSILON and value.UpVector.Magnitude>EPSILON
   and value.RightVector.Magnitude>EPSILON
 end)
 return ok and valid
end
local function dot(a,b)
 return a.X*b.X+a.Y*b.Y+a.Z*b.Z
end
local function unit(value)
 if not vectorOK(value) or value.Magnitude<=EPSILON then return nil end
 return value/value.Magnitude
end
local function wrap(value) return (value+math.pi)%TAU-math.pi end
local function shortest(value)
 local delta=wrap(value)
 -- Choose a deterministic direction for the exactly opposite heading.
 return if math.abs(delta+math.pi)<1e-12 then math.pi else delta
end
local function angle(a,b) return math.deg(math.acos(math.clamp(dot(a,b),-1,1))) end
local function diagnostic(state)
 return {yaw=0,pitch=0,roll=0,targetAngle=0,deltaTime=0,angularError=0,state=state}
end

-- Smoothness is a dimensionless 0..1 strength control, not a per-frame Lerp
-- fraction. Default .405 => tau=.019683 s and ~59 ms to close 95% of an angular
-- step. Doubling FPS preserves the response over the same elapsed time.
function CameraController.timeConstant(smoothness)
 if not finite(smoothness) or smoothness<0 or smoothness>1 then
  return nil,"Smoothness must be finite and between 0 and 1"
 end
 return 0.12*smoothness*smoothness
end
function CameraController.alpha(smoothness,dt)
 local tau,message=CameraController.timeConstant(smoothness)
 if not tau then return nil,message end
 if not finite(dt) or dt<0 then return nil,"deltaTime must be finite and nonnegative" end
 if dt==0 then return 0 end
 if tau==0 then return 1 end
 return math.clamp(1-math.exp(-dt/tau),0,1)
end

local function nativeVector(x,y,z) return Vector3.new(x,y,z) end
local function nativeFromBasis(position,right,up,look) return CFrame.fromMatrix(position,right,up,-look) end

-- Adapters are deliberately optional: production always uses native Roblox
-- Vector3/CFrame APIs. Numerical CLI checks inject vector construction/lookAt.
function CameraController.new(config,callbacks)
 assert(type(config)=="table","CameraController requires a Config table")
 callbacks=callbacks or {}
 local fromBasis=callbacks.fromBasis
 if not fromBasis and callbacks.lookAt then
  fromBasis=function(position,right,up,look) return callbacks.lookAt(position,position+look,up) end
 end
 return setmetatable({config=config,camera=nil,lastFrame=nil,diagnostics=diagnostic("IDLE"),
  newVector=callbacks.newVector or nativeVector,fromBasis=fromBasis or nativeFromBasis,
 },CameraController)
end
function CameraController:setConfig(config)
 if type(config)~="table" then return false,"Config must be a table" end
 self.config=config
 return true
end
function CameraController:reset()
 -- Forget only our orientation state. No stale camera CFrame is restored, and
-- CameraType, CameraSubject, Focus, mouse and character properties are untouched.
 self.camera=nil
 self.lastFrame=nil
 self.yaw=nil;self.pitch=nil;self.polarHold=nil;self.polarTurn=nil
 self.diagnostics=diagnostic("RESET")
end
function CameraController:destroy() self:reset() end
function CameraController:GetDiagnostics() return table.clone(self.diagnostics) end

function CameraController:_level(position,yaw,pitch)
 -- This is the world-Y yaw/pitch basis, including the exact pole. Right.Y=0,
 -- Up.Y=cos(pitch)>=0. Analytic Up is the normalized world-Y projection
 -- away from the pole and its heading-defined limit at the pole: no division
 -- by a nearly zero cross product and no inherited previous UpVector.
 local sy,cy,sp,cp=math.sin(yaw),math.cos(yaw),math.sin(pitch),math.cos(pitch)
 local look=self.newVector(sy*cp,sp,-cy*cp)
 local up=self.newVector(-sy*sp,cp,cy*sp)
 local right=self.newVector(cy,0,sy)
 -- fromMatrix does not subtract two large world positions to recover a unit
 -- direction. It preserves the zero-roll basis even at float32 map distances.
 return self.fromBasis(position,right,up,look),look,up,right
end
function CameraController:_angles(frame)
 local look=unit(frame.LookVector)
 local horizontal=math.sqrt(look.X*look.X+look.Z*look.Z)
 local yaw
 if horizontal>POLE_ENTER then yaw=math.atan2(look.X,-look.Z)
 else
  -- Heading cannot be recovered from a vertical LookVector. A horizontal
  -- projection of Right gives a finite initial heading without reusing roll.
  local right=frame.RightVector
  yaw=if right.X*right.X+right.Z*right.Z>EPSILON*EPSILON then math.atan2(right.Z,right.X) else 0
 end
 return wrap(yaw),math.atan2(look.Y,horizontal)
end

function CameraController:_update(camera,predicted,dt)
 local alpha,message=CameraController.alpha(self.config.Smoothness,dt)
 if not alpha then return false,message end
 if dt<=0 then return false,"deltaTime must be positive" end
 if camera==nil then return false,"CurrentCamera is unavailable" end
 if not vectorOK(predicted) then return false,"Predicted position must be a finite Vector3" end
 local current=camera.CFrame
 if not frameOK(current) then return false,"Camera CFrame is invalid" end
 local direction=unit(predicted-current.Position)
 if not direction then return false,"Predicted position coincides with camera position" end

 -- Retain only our scalar yaw/pitch, never a previous UpVector/quaternion.
 -- Roblox can replace its CFrame every frame; the current position remains
 -- the sole translation source. A different Camera discards angular state.
 local sameCamera=self.camera==camera and self.yaw~=nil and self.pitch~=nil
 local previousYaw,previousPitch
 if sameCamera then previousYaw,previousPitch=self.yaw,self.pitch
 else previousYaw,previousPitch=self:_angles(current) end
 local horizontal=math.sqrt(direction.X*direction.X+direction.Z*direction.Z)
 local wasHeld=sameCamera and self.polarHold==true
 local held=horizontal<=(if wasHeld then POLE_EXIT else POLE_ENTER)
 local targetYaw=if held then previousYaw else math.atan2(direction.X,-direction.Z)
 local targetPitch=math.atan2(direction.Y,horizontal)
 local yawDelta=shortest(targetYaw-previousYaw)
 local polarTurn=sameCamera and self.polarTurn==true
 if wasHeld and not held and math.abs(yawDelta)>1e-3 then polarTurn=true end
 local yawStep=yawDelta*alpha
 -- Only the singular polar transition has a speed guard. It prevents an
 -- instant 180-degree heading flip on exit even with Smoothness=0, without
 -- adding another smoothing filter to ordinary tracking.
 local guarded=not held and (polarTurn or horizontal<POLAR_BAND)
 if guarded then yawStep=math.clamp(yawStep,-POLAR_YAW_RATE*dt,POLAR_YAW_RATE*dt) end
 local resultYaw=wrap(previousYaw+yawStep)
 local resultPitch=math.clamp(previousPitch+(targetPitch-previousPitch)*alpha,-HALF_PI,HALF_PI)
 if math.abs(shortest(targetYaw-resultYaw))<1e-3 then polarTurn=false end
 local base,previousLook=self:_level(current.Position,previousYaw,previousPitch)
 if not frameOK(base) then return false,"Leveled initial camera CFrame is invalid" end
 local goal=self:_level(current.Position,targetYaw,targetPitch)
 if not frameOK(goal) then return false,"Leveled target camera CFrame is invalid" end
 local result,_,referenceUp,referenceRight=self:_level(current.Position,resultYaw,resultPitch)
 if not frameOK(result) then return false,"Interpolated camera CFrame is invalid" end
 if math.abs(result.RightVector.Y)>1e-5 or result.UpVector.Y< -1e-6 then return false,"Camera orientation lost its world-Y horizon" end
 camera.CFrame=result
 self.camera=camera
 self.lastFrame=result
 self.yaw=resultYaw;self.pitch=resultPitch;self.polarHold=held;self.polarTurn=polarTurn
 local data=self.diagnostics
 data.yaw=math.deg(resultYaw);data.pitch=math.deg(resultPitch)
 data.roll=math.deg(math.atan2(dot(result.RightVector,referenceUp),dot(result.RightVector,referenceRight)))
 data.targetAngle=angle(previousLook,direction);data.deltaTime=dt;data.angularError=angle(result.LookVector,direction)
 data.state=if held then "POLAR_HOLD" elseif guarded then "POLAR_TURN" else "TRACKING"
 return true
end
function CameraController:update(camera,predicted,dt)
 -- Missing/destroyed cameras and engine errors are skipped without throwing out
-- of RenderStepped. All validation precedes the single CFrame assignment.
 local ok,updated,message=pcall(self._update,self,camera,predicted,dt)
 if not ok then self.diagnostics.state="ERROR";return false,"Camera update failed: "..tostring(updated) end
 if not updated then self.diagnostics.state="ERROR" end
 return updated,message
end

return CameraController
