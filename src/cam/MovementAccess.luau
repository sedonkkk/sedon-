--!nonstrict
-- Local test permission and server authorization are independent contracts.
local Access={}
function Access.server(config,report)
 return config.MovementMode=="Server" or (config.MovementMode=="Auto" and report.movementBridge and report.movementBridge.available)
end
function Access.localAllowed(config,report)
 if config.LocalMovementAllowed or config.MovementAuthorized then return true end
 if report.player:GetAttribute("SEDWARELocalMovementAllowed")==true then return true end
 local ok,studio=pcall(function() return report.services.RunService:IsStudio() end)
 -- Studio is an owned local test context, not permission to change a published game.
 return ok and studio==true
end
function Access.allowed(config,report)
 if Access.server(config,report) then
  return report.movementBridge~=nil and report.movementBridge.available
   and report.player:GetAttribute("SEDWAREMovementAuthorized")==true
 end
 -- Legacy attributes preserve explicitly authorized local integrations.
 return Access.localAllowed(config,report) or report.player:GetAttribute("SEDWAREMovementAuthorized")==true
  or report.world:GetAttribute("SEDWAREMovementAuthorized")==true
end
function Access.ready(entry,world)
 return entry and entry.character and entry.character:IsDescendantOf(world)
  and entry.humanoid and entry.humanoid:IsDescendantOf(entry.character)
  and type(entry.humanoid.Health)=="number" and entry.humanoid.Health==entry.humanoid.Health and entry.humanoid.Health<math.huge and entry.humanoid.Health>0
  and entry.root and entry.root:IsA("BasePart") and entry.root:IsDescendantOf(entry.character) and not entry.root.Anchored
end
return Access
