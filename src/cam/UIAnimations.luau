--!nonstrict
-- One cancellable tween per instance, created only on state changes.
local UIAnimations={}
UIAnimations.__index=UIAnimations
function UIAnimations.new()
 local ok,service=pcall(function() return game:GetService("TweenService") end)
 return setmetatable({service=if ok then service else nil,active={},destroyed=false},UIAnimations)
end
function UIAnimations:cancel(instance)
 local record=self.active[instance]
 if not record then return end
 self.active[instance]=nil
 if record.connection then record.connection:Disconnect() end
 pcall(function() record.tween:Cancel();record.tween:Destroy() end)
end
function UIAnimations:play(instance,duration,properties)
 if self.destroyed then return false end
 self:cancel(instance)
 if not self.service then for key,value in properties do instance[key]=value end;return false end
 local tween=self.service:Create(instance,TweenInfo.new(duration,Enum.EasingStyle.Quad,Enum.EasingDirection.Out),properties)
 local record={tween=tween};self.active[instance]=record
 record.connection=tween.Completed:Connect(function()
  if self.active[instance]==record then self.active[instance]=nil end
  record.connection:Disconnect();tween:Destroy()
 end)
 tween:Play();return true
end
function UIAnimations:destroy()
 if self.destroyed then return end
 self.destroyed=true
 local objects={};for object in self.active do table.insert(objects,object) end
 for _,object in objects do self:cancel(object) end
end
return UIAnimations
