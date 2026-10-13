--!nonstrict
local Access={}
function Access.allowed(config,report)
 if config.ESPAuthorized or report.player:GetAttribute("SEDWAREESPAuthorized")==true
  or report.world:GetAttribute("SEDWAREESPAuthorized")==true then return true end
 local ok,studio=pcall(function() return report.services.RunService:IsStudio() end)
 return ok and studio==true
end
return Access
