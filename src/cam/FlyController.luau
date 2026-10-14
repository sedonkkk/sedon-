--!nonstrict
local MovementAccess=if script then require(script.Parent.MovementAccess) else require("./MovementAccess")
local FlyController={}
FlyController.__index=FlyController
function FlyController.new(config,report)
 return setmetatable({config=config,report=report,active=false,velocity=Vector3.zero},FlyController)
end
function FlyController:stop()
 if self.orientation then self.orientation:Destroy();self.orientation=nil end
 if self.constraint then self.constraint:Destroy();self.constraint=nil end
 if self.attachment then self.attachment:Destroy();self.attachment=nil end
 if self.humanoid and self.original then
  pcall(function()
   self.humanoid.AutoRotate=self.original.autoRotate;self.humanoid.PlatformStand=self.original.platformStand
   if self.humanoid.Health>0 then self.humanoid:ChangeState(self.original.state) end
  end)
 end
 self.humanoid=nil;self.root=nil;self.original=nil;self.active=false;self.velocity=Vector3.zero;self.heading=nil
end
function FlyController:_updateOrientation(camera)
 if not self.config.FlyOrientation then
  if self.orientation then self.orientation:Destroy();self.orientation=nil end
  return
 end
 if not self.orientation or self.orientation.Parent~=self.root then
  if self.orientation then self.orientation:Destroy() end
  self.orientation=Instance.new("AlignOrientation");self.orientation.Name="SEDWAREFlyOrientation"
  self.orientation.Mode=Enum.OrientationAlignmentMode.OneAttachment;self.orientation.Attachment0=self.attachment
  self.orientation.AlignType=Enum.AlignType.AllAxes
  self.orientation.RigidityEnabled=false;self.orientation.ReactionTorqueEnabled=false;self.orientation.Parent=self.root
 end
 self.orientation.MaxTorque=self.config.FlyMaxTorque
 self.orientation.MaxAngularVelocity=self.config.FlyMaxAngularVelocity
 self.orientation.Responsiveness=self.config.FlyOrientationResponsiveness
 local forward=if camera then camera.CFrame.LookVector else self.root.CFrame.LookVector
 local horizontal=Vector3.new(forward.X,0,forward.Z)
 if horizontal.Magnitude>1e-5 then self.heading=horizontal.Unit end
 self.heading=self.heading or Vector3.new(0,0,-1)
 -- Only the constraint goal changes. Never assign the character's CFrame.
 self.orientation.CFrame=CFrame.lookAt(Vector3.zero,self.heading,Vector3.yAxis)
end
function FlyController:start(entry)
 if not MovementAccess.allowed(self.config,self.report) then return false,"Fly requiere una experiencia propia o autorización explícita" end
 if not MovementAccess.ready(entry,self.report.world) then return true,"Waiting for character" end
 if self.active and self.root==entry.root and self.humanoid==entry.humanoid
  and self.constraint and self.constraint.Parent==entry.root
  and self.attachment and self.attachment.Parent==entry.root then return true end
 if MovementAccess.server(self.config,self.report) then return true,"Waiting for server confirmation" end
 if entry.root:FindFirstChild("SEDWAREServerFlyVelocity") then return true,"Waiting for server controller to release" end
 self:stop()
 self.humanoid=entry.humanoid;self.root=entry.root
 self.original={autoRotate=self.humanoid.AutoRotate,platformStand=self.humanoid.PlatformStand,state=self.humanoid:GetState()}
 local ok,problem=pcall(function()
  self.attachment=Instance.new("Attachment");self.attachment.Name="SEDWAREFlyAttachment";self.attachment.Parent=self.root
  self.constraint=Instance.new("LinearVelocity");self.constraint.Name="SEDWAREFlyVelocity"
  self.constraint.Attachment0=self.attachment;self.constraint.RelativeTo=Enum.ActuatorRelativeTo.World
  self.constraint.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector;self.constraint.ForceLimitsEnabled=true
  self.constraint.MaxForce=self.config.FlyMaxForce;self.constraint.VectorVelocity=Vector3.zero;self.constraint.Parent=self.root
  self:_updateOrientation(nil)
  self.humanoid.AutoRotate=false;self.humanoid.PlatformStand=true;self.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
  self.active=true
 end)
 if not ok then self:stop();return false,"Fly API: "..tostring(problem) end
 return true
end
function FlyController:update(entry,camera,dt,keys)
 if not self.config.Fly or not MovementAccess.allowed(self.config,self.report) or not MovementAccess.ready(entry,self.report.world) then self:stop();return end
 if not self.active or self.root~=entry.root or self.humanoid~=entry.humanoid
  or (not MovementAccess.server(self.config,self.report) and
   (not self.constraint or self.constraint.Parent~=entry.root or not self.attachment or self.attachment.Parent~=entry.root)) then
  local started,reason=self:start(entry);assert(started,reason)
 end
 local bridge=self.report.movementBridge
 if MovementAccess.server(self.config,self.report) then
  self.active=bridge.active and bridge.serverFly==true and self.config.Fly
  if not camera then self.velocity=Vector3.zero;return end
 elseif not self.active then return end
 if not MovementAccess.server(self.config,self.report) then self:_updateOrientation(camera) end
 if not camera then self.velocity=Vector3.zero;self.constraint.VectorVelocity=Vector3.zero;return end
 if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge then return end
 local direction=camera.CFrame.LookVector*((keys.W and 1 or 0)-(keys.S and 1 or 0))
  +camera.CFrame.RightVector*((keys.D and 1 or 0)-(keys.A and 1 or 0))
  +Vector3.yAxis*((keys.up and 1 or 0)-(keys.down and 1 or 0))
 if direction.Magnitude>1 then direction=direction.Unit end
 local wanted=direction*self.config.FlySpeed
 local alpha=if self.config.FlySmoothing==0 then 1 else 1-math.exp(-dt/self.config.FlySmoothing)
 self.velocity=self.velocity:Lerp(wanted,alpha)
 -- A speed edit is also a new server input limit. Old smoothing state must
 -- not exceed it or valid flight can expire while its inputs are rejected.
 if self.velocity.Magnitude>self.config.FlySpeed then self.velocity=self.velocity.Unit*self.config.FlySpeed end
 if MovementAccess.server(self.config,self.report) then return end
 self.constraint.VectorVelocity=self.velocity
 if self.constraint.MaxForce~=self.config.FlyMaxForce then self.constraint.MaxForce=self.config.FlyMaxForce end
end
function FlyController:destroy() self:stop() end
return FlyController
