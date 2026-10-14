--!nonstrict
local MovementAccess=if script then require(script.Parent.MovementAccess) else require("./MovementAccess")
local SpeedController={}
SpeedController.__index=SpeedController
-- WalkSpeed is a native float; Luau configuration numbers can have more
-- precision. Compare readback within float32 noise, never a real correction.
local function close(a,b)
 return type(a)=="number" and type(b)=="number" and a==a and b==b
  and math.abs(a)<math.huge and math.abs(b)<math.huge and math.abs(a-b)<=1e-4
end
function SpeedController.new(config,report)
 return setmetatable({config=config,report=report,active=false,writes=0},SpeedController)
end
function SpeedController:stop()
 if self.humanoid and self.original~=nil then pcall(function()
  if close(self.humanoid.WalkSpeed,self.applied) then self.humanoid.WalkSpeed=self.original end
 end) end
 self.humanoid=nil;self.original=nil;self.applied=nil;self.configured=nil;self.active=false;self.limited=false;self.reason=nil
end
function SpeedController:sync(entry,flying)
 if not self.config.Speed or flying or not MovementAccess.allowed(self.config,self.report) or not MovementAccess.ready(entry,self.report.world) then self:stop();return end
 if MovementAccess.server(self.config,self.report) then
  local bridge=self.report.movementBridge
  local reason=if self.report.player:GetAttribute("SEDWAREMovementToken")==bridge.token then self.report.player:GetAttribute("SEDWAREServerSpeedReason") else nil
  local confirmed=bridge.active and bridge.serverSpeed==true
  self.limited=bridge.active and ((type(reason)=="string" and reason~="") or (confirmed and not close(entry.humanoid.WalkSpeed,self.config.WalkSpeed)))
  self.reason=if self.limited then (if type(reason)=="string" and reason~="" then reason else "WalkSpeed changed externally; not overwritten") else nil
  self.active=confirmed and not self.limited;return
 end
 if self.humanoid~=entry.humanoid then
  self:stop();self.humanoid=entry.humanoid;self.original=self.humanoid.WalkSpeed
 end
 -- Deliberately do not fight a server that overwrites WalkSpeed. Reapply only
 -- for a new character, a config edit or a state transition.
 if self.configured~=self.config.WalkSpeed then
  self.humanoid.WalkSpeed=self.config.WalkSpeed;self.configured=self.config.WalkSpeed;self.writes+=1
  local actual=self.humanoid.WalkSpeed
  self.applied=if close(actual,self.configured) then actual else nil
 end
 self.active=close(self.humanoid.WalkSpeed,self.applied)
 self.limited=not self.active
 self.reason=if self.limited then "WalkSpeed changed externally; not overwritten" else nil
end
function SpeedController:destroy() self:stop() end
return SpeedController
