--!nonstrict
-- Explicit API/event doubles; they do not simulate real movement or rendering.
local Base=require("./CamMock")
local Mock={}
function Mock.new()
 local mock=Base.new();local env=mock.env;local wrapped={}
 mock:setPointer(640,360)
 local oldNew=env.Instance.new
 local extraSignals={ChildAdded=true,ChildRemoved=true,TextBoxFocused=true}
 local function wrap(node)
  if wrapped[node] then return node end;wrapped[node]=true
  local base=getmetatable(node);local meta=table.clone(base)
  meta.__index=function(object,key)
   if extraSignals[key] then
    if not object._signals[key] then object._signals[key]=mock.signal() end
    return object._signals[key]
   end
   if key=="IsA" then
    return function(self,class)
     if class=="GuiObject" and (self.ClassName=="ImageLabel" or self.ClassName=="ImageButton") then return true end
     return base.__index(self,"IsA")(self,class)
    end
   end
   if key=="IsLoaded" then return object._props.IsLoaded==true end
   if key=="CanvasPosition" then return object._props.CanvasPosition or env.Vector2.new() end
   return base.__index(object,key)
  end
  meta.__newindex=function(object,key,value)
   local previous=object.Parent
   base.__newindex(object,key,value)
   if key=="Parent" and previous~=value then
    if previous and previous._signals.ChildRemoved then previous._signals.ChildRemoved:Fire(object) end
    if value and value._signals.ChildAdded then value._signals.ChildAdded:Fire(object) end
   end
  end
  setmetatable(node,meta);return node
 end
 for _,node in mock.instances do wrap(node) end
 env.Instance.new=function(class) return wrap(oldNew(class)) end
 local function character(player)
  local model=player.Character
  if not model then return end
  local humanoid=model:FindFirstChildOfClass("Humanoid")
  humanoid.WalkSpeed=16;humanoid.AutoRotate=true;humanoid.PlatformStand=false
  local root=model:FindFirstChild("HumanoidRootPart")
  root.CFrame=env.CFrame.new(root.Position);root.Size=env.Vector3.new(2,2,1);root.AssemblyLinearVelocity=env.Vector3.zero;root.Anchored=false
 end
 character(mock.services.Players.LocalPlayer)
 local add,respawn=mock.addPlayer,mock.respawn
 function mock:addPlayer(...)
  local player=add(self,...);character(player);return player
 end
 function mock:respawn(player,...)
  local result=respawn(self,player,...);character(player);return result
 end
 local tweenService={active=0,created=0}
 function tweenService:Create(object,info,properties)
  self.created+=1
  local tween={Completed=mock.signal(),cancelled=false}
  function tween:Play()
   self.playing=true;tweenService.active+=1
   env.task.delay(info[1],function()
    if self.cancelled then return end
    self.playing=false;tweenService.active-=1
    for key,value in properties do object[key]=value end
    self.Completed:Fire(env.Enum.PlaybackState.Completed)
   end)
  end
  function tween:Cancel()
   if self.playing then self.playing=false;tweenService.active-=1 end
   self.cancelled=true
  end
  function tween:Destroy() self:Cancel();self.Completed:DisconnectAll() end
  return tween
 end
 mock.services.TweenService=tweenService
 mock.tweens=tweenService
 local getService=env.game.GetService
 function env.game:GetService(name)
  if name=="TweenService" then return tweenService end
  return getService(self,name)
 end
 function mock:key(name,processed,ended)
  local event={KeyCode=env.Enum.KeyCode[name],UserInputType=env.Enum.UserInputType.Keyboard,Position=env.Vector3.zero}
  local signal=if ended then self.services.UserInputService.InputEnded else self.services.UserInputService.InputBegan
  signal:Fire(event,processed==true);return event
 end
 function mock:liveInstances(class)
  local count=0
  for _,node in self.instances do if not node._destroyed and (not class or node.ClassName==class) then count+=1 end end
  return count
 end
 return mock
end
return Mock
