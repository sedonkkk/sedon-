--!nonstrict
local MovementAccess=if script then require(script.Parent.MovementAccess) else require("./MovementAccess")
local SpeedController={}
SpeedController.__index=SpeedController
function SpeedController.new(config,report)
 return setmetatable({config=config,report=report,active=false,writes=0},SpeedController)
end
function SpeedController:stop()
 if self.humanoid and self.original~=nil then pcall(function()
  if self.humanoid.WalkSpeed==self.applied then self.humanoid.WalkSpeed=self.original end
 end) end
 self.humanoid=nil;self.original=nil;self.applied=nil;self.active=false;self.limited=false
end
function SpeedController:sync(entry,flying)
 if not self.config.Speed or flying or not MovementAccess.allowed(self.config,self.report) or not MovementAccess.ready(entry,self.report.world) then self:stop();return end
 if MovementAccess.server(self.config,self.report) then
  self.active=self.report.movementBridge.active and self.report.movementBridge.serverSpeed==true;return
 end
 if self.humanoid~=entry.humanoid then
  self:stop();self.humanoid=entry.humanoid;self.original=self.humanoid.WalkSpeed
 end
 -- Deliberately do not fight a server that overwrites WalkSpeed. Reapply only
 -- for a new character, a config edit or a state transition.
 if self.applied~=self.config.WalkSpeed then
  self.humanoid.WalkSpeed=self.config.WalkSpeed;self.applied=self.config.WalkSpeed;self.writes+=1
 end
 self.active=self.humanoid.WalkSpeed==self.applied
 self.limited=not self.active
end
function SpeedController:destroy() self:stop() end
return SpeedController
