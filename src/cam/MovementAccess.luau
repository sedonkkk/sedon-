--!nonstrict
-- A declaration/attribute for an owned or explicitly authorized experience.
-- This is not a server permission bypass or a replication guarantee.
local MovementAccess={}
function MovementAccess.allowed(config,report)
 if config.MovementAuthorized then return true end
 return report.player:GetAttribute("SEDWAREMovementAuthorized")==true
  or report.world:GetAttribute("SEDWAREMovementAuthorized")==true
end
function MovementAccess.ready(entry,world)
 return entry and entry.character and entry.character:IsDescendantOf(world)
  and entry.humanoid and entry.humanoid.Health>0 and entry.root and entry.root:IsA("BasePart")
end
return MovementAccess
