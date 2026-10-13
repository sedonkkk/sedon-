--!nonstrict
-- Reuse the existing deterministic screen-distance selector. Character and
-- visibility checks happen on acquisition; a valid locked player is retained.
local Selection=if script then require(script.Parent.Parent.pink.Selection) else require("../pink/Selection")
local ModeDetector=if script then require(script.Parent.Parent.pink.ModeDetector) else require("../pink/ModeDetector")
local TargetSelector={}
TargetSelector.__index=TargetSelector
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<math.huge end
local function vector(v)
 local ok,result=pcall(function() return v~=nil and finite(v.X) and finite(v.Y) and finite(v.Z) end)
 return ok and result
end
function TargetSelector.new(config,report)
 local self=setmetatable({config=config,world=report.world,player=report.player,services=report.services,
  registry=report.registry,modeDetector=ModeDetector.new()},TargetSelector)
 if config.VisibilityCheck then
  self.rayParams=RaycastParams.new();self.rayParams.FilterType=Enum.RaycastFilterType.Exclude;self.rayParams.IgnoreWater=true
 end
 return self
end
function TargetSelector:reference(now)
 local camera=self.world.CurrentCamera;if not camera then return nil end
 local character=self.player.Character
 local head=character and character:FindFirstChild("Head")
 local position=camera.CFrame.Position
 local mode=self.modeDetector:update(now or self.world:GetServerTimeNow(),{
  forcedFirstPerson=self.player.CameraMode==Enum.CameraMode.LockFirstPerson,
  subjectIsLocal=camera.CameraSubject and character and camera.CameraSubject:IsDescendantOf(character)==true,
  headDistance=head and (position-head.Position).Magnitude,
  focusDistance=camera.Focus and (position-camera.Focus.Position).Magnitude,
 })
 local input=self.services.UserInputService
 if mode=="FirstPerson" or input.MouseBehavior==Enum.MouseBehavior.LockCenter then
  return Selection.reference("FirstPerson",camera.ViewportSize)
 end
 return Selection.reference("ThirdPerson",camera.ViewportSize,input:GetMouseLocation())
end
function TargetSelector:origin()
 local camera=self.world.CurrentCamera
 if camera and vector(camera.CFrame.Position) then return camera.CFrame.Position end
 local character=self.player.Character
 local head=character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
 return if head and vector(head.Position) then head.Position else nil
end
function TargetSelector:resolve(player)
 if not player or player==self.player or player.Parent~=self.services.Players then return nil,"player unavailable" end
 local character=player.Character
 if not character or not character:IsDescendantOf(self.world) then return nil,"character unavailable" end
 local humanoid=character:FindFirstChildOfClass("Humanoid")
 if not humanoid or not finite(humanoid.Health) or humanoid.Health<=0 then return nil,"target is dead" end
 local part=character:FindFirstChild(self.config.HitPart)
 if not part and self.config.HitPart=="UpperTorso" and self.config.FallbackR6 then part=character:FindFirstChild("Torso") end
 if not part or not part:IsA("BasePart") or not part:IsDescendantOf(character) or not vector(part.Position) then
  return nil,"selected Hit Part is unavailable"
 end
 local origin=self:origin()
 if not vector(origin) then return nil,"camera origin unavailable" end
 local distance=(part.Position-origin).Magnitude
 if not finite(distance) or distance>self.config.MaxDistance then return nil,"target exceeds MaxDistance" end
 return {player=player,character=character,humanoid=humanoid,part=part,actualHitPart=part.Name,
  distanceStuds=distance,valid=true}
end
function TargetSelector:visible(data)
 if not self.config.VisibilityCheck then return true end
 if not self.rayParams then
  self.rayParams=RaycastParams.new();self.rayParams.FilterType=Enum.RaycastFilterType.Exclude;self.rayParams.IgnoreWater=true
 end
 local origin=self:origin()
 if not vector(origin) then return false end
 self.rayParams.FilterDescendantsInstances=if self.player.Character then {self.player.Character} else {}
 local direction=data.part.Position-origin
 if direction.Magnitude<0.001 then return true end
 local hit=self.world:Raycast(origin,direction,self.rayParams)
 return hit==nil or (hit.Instance and hit.Instance:IsDescendantOf(data.character))
end
function TargetSelector:acquire(player)
 self.acquisitionCount=(self.acquisitionCount or 0)+1
 local camera=self.world.CurrentCamera
 local size=camera and camera.ViewportSize
 if not size or not finite(size.X) or not finite(size.Y) or size.X<=0 or size.Y<=0 then return nil,"camera viewport unavailable" end
 local reference=self:reference()
 if not reference then return nil,"selection reference unavailable" end
 local candidates,diagnostics={}, {reference=reference,evaluated=0,valid=0,reasons={}}
 local players={}
 if player then players={player}
 elseif self.registry then for _,entry in self.registry.list do table.insert(players,entry.player) end
 else players=self.services.Players:GetPlayers() end
 for _,candidate in players do
  if candidate~=self.player then
   diagnostics.evaluated+=1
   local data,reason=self:resolve(candidate)
   if data then
    local point,onScreen=camera:WorldToViewportPoint(data.part.Position)
    data.screenPosition=point;data.onScreen=onScreen==true and vector(point) and point.Z>0
    data.visible=self:visible(data)
    if not data.onScreen then reason="offscreen or behind camera"
    elseif not data.visible then reason="occluded"
    elseif not Selection.within(data,reference,self.config.Radius) then reason="outside Radius"
    else table.insert(candidates,data);diagnostics.valid+=1 end
   end
   if reason and #diagnostics.reasons<32 then table.insert(diagnostics.reasons,tostring(candidate.Name)..": "..reason) end
  end
 end
 local selected=Selection.nearest(candidates,reference,self.config.Radius)
 diagnostics.selected=selected and selected.player.Name
 self.lastSelection=diagnostics
 return selected,if selected then nil else "No valid target inside Radius"
end
return TargetSelector
