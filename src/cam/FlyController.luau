--!nonstrict
local MovementAccess=if script then require(script.Parent.MovementAccess) else require("./MovementAccess")
local FlyController={}
FlyController.__index=FlyController
function FlyController.new(config,report)
 return setmetatable({config=config,report=report,active=false,velocity=Vector3.zero},FlyController)
end
function FlyController:stop()
 if self.constraint then self.constraint:Destroy();self.constraint=nil end
 if self.attachment then self.attachment:Destroy();self.attachment=nil end
 if self.humanoid and self.original then
  pcall(function()
   self.humanoid.AutoRotate=self.original.autoRotate;self.humanoid.PlatformStand=self.original.platformStand
   if self.humanoid.Health>0 then self.humanoid:ChangeState(self.original.state) end
  end)
 end
 self.humanoid=nil;self.root=nil;self.original=nil;self.active=false;self.velocity=Vector3.zero
end
function FlyController:start(entry)
 if not MovementAccess.allowed(self.config,self.report) then return false,"Fly requiere una experiencia propia o autorización explícita" end
 if not MovementAccess.ready(entry,self.report.world) then return true,"Waiting for character" end
 if self.active and self.root==entry.root then return true end
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
  self.humanoid.AutoRotate=false;self.humanoid.PlatformStand=true;self.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
  self.active=true
 end)
 if not ok then self:stop();return false,"Fly API: "..tostring(problem) end
 return true
end
function FlyController:update(entry,camera,dt,keys)
 if not self.config.Fly or not MovementAccess.allowed(self.config,self.report) or not MovementAccess.ready(entry,self.report.world) then self:stop();return end
 if not self.active or self.root~=entry.root then
  local started,reason=self:start(entry);assert(started,reason)
 end
 local bridge=self.report.movementBridge
 if MovementAccess.server(self.config,self.report) then
  self.active=bridge.active and bridge.serverFly==true and self.config.Fly
  if not camera then self.velocity=Vector3.zero;return end
 elseif not self.active then return end
 if not camera then self.velocity=Vector3.zero;self.constraint.VectorVelocity=Vector3.zero;return end
 if type(dt)~="number" or dt<=0 or dt~=dt or dt==math.huge then return end
 local direction=camera.CFrame.LookVector*((keys.W and 1 or 0)-(keys.S and 1 or 0))
  +camera.CFrame.RightVector*((keys.D and 1 or 0)-(keys.A and 1 or 0))
  +Vector3.yAxis*((keys.up and 1 or 0)-(keys.down and 1 or 0))
 if direction.Magnitude>1 then direction=direction.Unit end
 local wanted=direction*self.config.FlySpeed
 local alpha=if self.config.FlySmoothing==0 then 1 else 1-math.exp(-dt/self.config.FlySmoothing)
 self.velocity=self.velocity:Lerp(wanted,alpha)
 if MovementAccess.server(self.config,self.report) then return end
 self.constraint.VectorVelocity=self.velocity
 if self.constraint.MaxForce~=self.config.FlyMaxForce then self.constraint.MaxForce=self.config.FlyMaxForce end
end
function FlyController:destroy() self:stop() end
return FlyController
