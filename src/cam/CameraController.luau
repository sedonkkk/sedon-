--!nonstrict
-- Orientation-only camera tracking. The session runs this AFTER Roblox's camera
-- step and supplies the current Camera and the already predicted world position.
-- Prediction never passes through an additional position filter here.
local CameraController = {}
CameraController.__index = CameraController

local EPSILON = 1e-6
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
local function nativeLookAt(position,target,up) return CFrame.lookAt(position,target,up) end
local function nativeRebase(frame,position) return CFrame.new(position)*frame.Rotation end
local function nativeLerp(frame,goal,alpha) return frame:Lerp(goal,alpha) end

-- Adapters are deliberately optional: production always uses native Roblox
-- Vector3/CFrame APIs. Numerical CLI checks can inject these four operations.
function CameraController.new(config,callbacks)
 assert(type(config)=="table","CameraController requires a Config table")
 callbacks=callbacks or {}
 return setmetatable({config=config,camera=nil,lastFrame=nil,
  newVector=callbacks.newVector or nativeVector,lookAt=callbacks.lookAt or nativeLookAt,
  rebase=callbacks.rebase or nativeRebase,lerp=callbacks.lerp or nativeLerp},CameraController)
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
end
function CameraController:destroy() self:reset() end

function CameraController:_stableUp(direction,frame)
 -- Project the previous up vector onto the new view plane. This parallel
-- transports the orientation through vertical aim without world-up singularities.
 local up=unit(frame.UpVector-direction*dot(frame.UpVector,direction))
 if up then return up end
 -- A sudden 90-degree turn can point exactly along the previous UpVector.
 -- The previous LookVector then supplies a perpendicular reference.
 up=unit(frame.LookVector-direction*dot(frame.LookVector,direction))
 if up then return up end
 -- Defensive fallback for malformed adapters; choose the least parallel axis.
 local reference=if math.abs(direction.Y)<0.9 then self.newVector(0,1,0) else self.newVector(1,0,0)
 return unit(reference-direction*dot(reference,direction))
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

 -- Roblox may replace its CFrame before every camera callback. Retain our last
-- OUTPUT rotation so smoothing actually converges, but repivot at the live
-- position every frame. A replacement Camera starts from its own orientation.
 local previous=if self.camera==camera and self.lastFrame then self.lastFrame else current
 local base=self.rebase(previous,current.Position)
 local up=self:_stableUp(direction,base)
 if not up then return false,"Cannot construct a stable camera up vector" end
 local goal=self.lookAt(current.Position,predicted,up)
 if not frameOK(goal) then return false,"Camera orientation is invalid" end
 local result=if alpha==1 then goal else self.lerp(base,goal,alpha)
 -- Rebase after interpolation as well, guaranteeing the live position is the
-- sole translation source, including when injected adapters round positions.
 result=self.rebase(result,current.Position)
 if not frameOK(result) then return false,"Interpolated camera CFrame is invalid" end
 camera.CFrame=result
 self.camera=camera
 self.lastFrame=result
 return true
end
function CameraController:update(camera,predicted,dt)
 -- Missing/destroyed cameras and engine errors are skipped without throwing out
-- of RenderStepped. All validation precedes the single CFrame assignment.
 local ok,updated,message=pcall(self._update,self,camera,predicted,dt)
 if not ok then return false,"Camera update failed: "..tostring(updated) end
 return updated,message
end

return CameraController
