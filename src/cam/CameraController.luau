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
 return {yaw=0,pitch=0,roll=0,targetAngle=0,deltaTime=0,angularError=0,state=state,
  yawRate=0,pitchRate=0,accelerationApplied=0,yawAccelerationApplied=0,
  safetyState="IDLE",overshootReference="INITIAL",setpointChange=0,
  pitchOvershootDegrees=0,yawOvershootDegrees=0,constraintConflict=false}
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

-- Closed-form critically damped response to a piecewise constant setpoint.
-- Rate/acceleration saturation is explicit and measured separately in the lab.
function CameraController.critical(delta,velocity,omega,dt,maxRate,maxAcceleration)
 local x=-delta;local e=math.exp(-omega*dt);local q=velocity+omega*x
 local step=delta+(x+q*dt)*e
 local v=(velocity-omega*q*dt)*e
 local bounded=math.clamp(v,-maxRate,maxRate)
 bounded=math.clamp(bounded,velocity-maxAcceleration*dt,velocity+maxAcceleration*dt)
 if bounded~=v then step=(velocity+bounded)*dt*0.5 end
 if delta==0 or step*delta<0 or math.abs(step)>math.abs(delta) then return delta,0 end
 return step,bounded
end

-- Limit the velocity that will ACTUALLY be applied this frame. An internal
-- velocity reset at the goal does not bound the acceleration of the CFrame.
-- The stopping ceiling includes this frame's travel and a conservative
-- continuous braking distance; it starts braking before reaching the goal.
-- A moved goal can make stopping before it impossible. Preserve acceleration
-- continuity then, report the crossing, and brake instead of snapping to zero.
local function appliedStep(step,delta,prior,dt,rate,acceleration)
 local distance=math.abs(delta)
 local aDt=acceleration*dt
 local stop=if distance==0 then 0 else
  (2*acceleration*distance)/(math.sqrt(aDt*aDt+2*acceleration*distance)+aDt)
 local desired=math.clamp(step/dt,-rate,rate)
 desired=math.clamp(desired,-stop,stop)
 if desired*delta<0 then desired=0 end
 local velocity=math.clamp(desired,prior-aDt,prior+aDt)
 velocity=math.clamp(velocity,-rate,rate)
 local value=velocity*dt
 local crossing=(distance>EPSILON and value*delta>0 and math.abs(value)>distance+EPSILON)
 local recovery=value*delta<0 or crossing or (distance<=EPSILON and math.abs(value)>EPSILON)
 return value,velocity,recovery,math.abs(desired-step/dt)>EPSILON
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
 self.adaptiveTau=nil;self.yawVelocity=0;self.pitchVelocity=0;self.mode=nil;self.guardPitchVelocity=0;self.guardYawVelocity=0
 self.appliedPitchVelocity=nil;self.appliedYawVelocity=nil;self.targetYaw=nil;self.targetPitch=nil
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

function CameraController:_update(camera,predicted,dt,context)
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
 local mode=self.config.TrackingMode or "Fixed"
 if not sameCamera or self.mode~=mode then self.yawVelocity=0;self.pitchVelocity=0;self.adaptiveTau=nil end
 self.mode=mode
 if mode=="Adaptive" then
  local errorDegrees=math.deg(math.sqrt(yawDelta*yawDelta+(targetPitch-previousPitch)^2))
  local gain=errorDegrees/(errorDegrees+self.config.AdaptiveErrorDegrees)
  local wanted=math.clamp((self.config.Smoothness/.405)^2*(self.config.AdaptiveMaxTau+(self.config.AdaptiveMinTau-self.config.AdaptiveMaxTau)*gain),self.config.AdaptiveMinTau,self.config.AdaptiveMaxTau)
  local ga=if self.config.AdaptiveGainSmoothing==0 then 1 else 1-math.exp(-dt/self.config.AdaptiveGainSmoothing)
  self.adaptiveTau=if self.adaptiveTau then self.adaptiveTau+(wanted-self.adaptiveTau)*ga else wanted
  alpha=if self.config.Smoothness==0 then 1 else 1-math.exp(-dt/self.adaptiveTau)
 end
 local yawStep=yawDelta*alpha
 local pitchStep=(targetPitch-previousPitch)*alpha
 if mode=="Critical" and self.config.Smoothness>0 then
  local maxRate=math.rad(self.config.AngularMaxSpeed);local maxAccel=math.rad(self.config.AngularMaxAcceleration)
  yawStep,self.yawVelocity=CameraController.critical(yawDelta,self.yawVelocity or 0,self.config.CriticalFrequency*.405/math.max(self.config.Smoothness,.001),dt,maxRate,maxAccel)
  pitchStep,self.pitchVelocity=CameraController.critical(targetPitch-previousPitch,self.pitchVelocity or 0,self.config.CriticalFrequency*.405/math.max(self.config.Smoothness,.001),dt,maxRate,maxAccel)
 else self.yawVelocity=0;self.pitchVelocity=0 end
 -- Only the singular polar transition has a speed guard. It prevents an
 -- instant 180-degree heading flip on exit even with Smoothness=0, without
 -- adding another smoothing filter to ordinary tracking.
 local guarded=not held and (polarTurn or horizontal<POLAR_BAND)
 -- One continuous angular guard covers all tracking phases. Turning it off at
 -- Grounded previously produced a large discontinuity precisely at landing.
 -- Pure calibration calls without context retain their original response.
 local safety=self.config.AngularSafety and context~=nil
 local priorPitch=if sameCamera then self.appliedPitchVelocity or 0 else 0
 local priorYaw=if sameCamera then self.appliedYawVelocity or 0 else 0
 local recovery,braking=false,false
 local yawRisk=safety and (context.movementPhase~="Grounded" or context.distanceStuds<self.config.CloseSafetyDistance or (context.reversalScale or 1)<1)
 if safety then
  local pr,pb
  -- Preserve V3.1 yaw response: ordinary grounded yaw uses its chosen
  -- interpolation, with the existing rate guard only during risky contexts.
  -- Adding a second yaw acceleration controller delayed initial acquisition.
  if yawRisk then yawStep=math.clamp(yawStep,-math.rad(self.config.AngularMaxSpeed)*dt,math.rad(self.config.AngularMaxSpeed)*dt) end
  self.guardYawVelocity=yawStep/dt
  pitchStep,self.guardPitchVelocity,pr,pb=appliedStep(pitchStep,targetPitch-previousPitch,priorPitch,dt,math.rad(self.config.PitchMaxSpeed),math.rad(self.config.PitchMaxAcceleration))
  recovery=pr;braking=pb
 else self.guardPitchVelocity=0;self.guardYawVelocity=0 end
 local beforePolar=yawStep
 if guarded then yawStep=math.clamp(yawStep,-POLAR_YAW_RATE*dt,POLAR_YAW_RATE*dt) end
 local resultYaw=wrap(previousYaw+yawStep)
 local wantedPitch=previousPitch+pitchStep
 local resultPitch=math.clamp(wantedPitch,-HALF_PI,HALF_PI)
 -- Hard poles have precedence over inertia. They can make simultaneous rate,
 -- acceleration and horizon constraints impossible, and are disclosed below.
 local constraintConflict=resultPitch~=wantedPitch or beforePolar~=yawStep
 local appliedPitch=(resultPitch-previousPitch)/dt
 local appliedYaw=shortest(resultYaw-previousYaw)/dt
 if safety and math.abs(appliedPitch-priorPitch)>math.rad(self.config.PitchMaxAcceleration)*dt+1e-7 then constraintConflict=true end
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
 self.appliedPitchVelocity=appliedPitch;self.appliedYawVelocity=appliedYaw
 local data=self.diagnostics
 data.yawError=math.deg(shortest(targetYaw-resultYaw));data.pitchError=math.deg(targetPitch-resultPitch)
 data.pitchRate=math.deg(appliedPitch);data.yawRate=math.deg(appliedYaw)
 data.accelerationApplied=math.deg((appliedPitch-priorPitch)/dt)
 data.yawAccelerationApplied=math.deg((appliedYaw-priorYaw)/dt)
 data.safetyLimited=safety==true
 data.yawRateGuarded=yawRisk==true;data.yawAccelerationBounded=false
 data.safetyState=if not safety then "BYPASSED" elseif not sameCamera then "INITIAL_FRAME"
  elseif constraintConflict then "HARD_CONSTRAINT" elseif recovery then "BRAKING_RECOVERY"
  elseif braking then "BRAKING" else "BOUNDED"
 data.constraintConflict=constraintConflict;data.accelerationReference=if sameCamera then "PREVIOUS_APPLIED_FRAME" else "INITIAL_OR_RESET_FRAME"
 local changedYaw=if sameCamera and self.targetYaw then shortest(targetYaw-self.targetYaw) else 0
 local changedPitch=if sameCamera and self.targetPitch then targetPitch-self.targetPitch else 0
 local stable=sameCamera and self.targetYaw~=nil and math.abs(changedYaw)<1e-6 and math.abs(changedPitch)<1e-6
 data.setpointChange=math.deg(math.sqrt(changedYaw*changedYaw+changedPitch*changedPitch))
 data.setpointChanged=not stable;data.overshootReference=if stable then "STABLE_SETPOINT" elseif sameCamera and self.targetYaw then "MOVING_SETPOINT" else "INITIAL"
 local pitchCrossed=(targetPitch-previousPitch)*(targetPitch-resultPitch)< -1e-12
 local yawCrossed=yawDelta*shortest(targetYaw-resultYaw)< -1e-12
 data.pitchGoalCrossed=pitchCrossed;data.yawGoalCrossed=yawCrossed
 data.pitchOvershootDegrees=if stable and pitchCrossed then math.abs(data.pitchError) else 0
 data.yawOvershootDegrees=if stable and yawCrossed then math.abs(data.yawError) else 0
 self.targetYaw=targetYaw;self.targetPitch=targetPitch
 data.mode=mode;data.tauSeconds=if mode=="Adaptive" then self.adaptiveTau else CameraController.timeConstant(self.config.Smoothness)
 data.yawVelocity=self.yawVelocity;data.pitchVelocity=self.pitchVelocity
 data.yaw=math.deg(resultYaw);data.pitch=math.deg(resultPitch)
 data.roll=math.deg(math.atan2(dot(result.RightVector,referenceUp),dot(result.RightVector,referenceRight)))
 data.targetAngle=angle(previousLook,direction);data.deltaTime=dt;data.angularError=angle(result.LookVector,direction)
 data.state=if held then "POLAR_HOLD" elseif guarded then "POLAR_TURN" else "TRACKING"
 return true
end
function CameraController:update(camera,predicted,dt,context)
 -- Missing/destroyed cameras and engine errors are skipped without throwing out
-- of RenderStepped. All validation precedes the single CFrame assignment.
 local ok,updated,message=pcall(self._update,self,camera,predicted,dt,context)
 if not ok then self.diagnostics.state="ERROR";return false,"Camera update failed: "..tostring(updated) end
 if not updated then self.diagnostics.state="ERROR" end
 return updated,message
end

return CameraController
