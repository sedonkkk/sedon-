--!nonstrict
-- INSTALL ONLY in ServerScriptService of your own/authorized experience.
-- This server grants its own players movement; adjust grant() to your ACL.
local Players=game:GetService("Players")
local Storage=game:GetService("ReplicatedStorage")
local Run=game:GetService("RunService")
assert(not Storage:FindFirstChild("SEDWAREMovementControl"),"SEDWARE server component already installed")
local control=Instance.new("RemoteFunction");control.Name="SEDWAREMovementControl";control.Parent=Storage
local input=Instance.new("RemoteEvent");input.Name="SEDWAREMovementInput";input.Parent=Storage
local states,connections,globalConnections={},{},{}
local function connect(signal,callback) local c=signal:Connect(callback);table.insert(globalConnections,c);return c end
local function finite(v) return type(v)=="number" and v==v and math.abs(v)<math.huge end
local function restore(s)
 if s.player and s.player:GetAttribute("SEDWAREMovementToken")==s.token then
  s.player:SetAttribute("SEDWAREServerFlyActive",false);s.player:SetAttribute("SEDWAREServerSpeedActive",false)
  s.player:SetAttribute("SEDWAREMeasuredHorizontalSpeed",0);s.player:SetAttribute("SEDWAREMeasuredVerticalSpeed",0)
 end
 if s.constraint then s.constraint:Destroy();s.constraint=nil end
 if s.attachment then s.attachment:Destroy();s.attachment=nil end
 if s.humanoid and s.original then pcall(function()
  if s.humanoid.WalkSpeed==s.appliedSpeed then s.humanoid.WalkSpeed=s.original.speed end
  if s.flyApplied then
   s.humanoid.AutoRotate=s.original.rotate;s.humanoid.PlatformStand=s.original.platform
   if s.humanoid.Health>0 then s.humanoid:ChangeState(s.original.state) end
  end
 end) end
 if s.root and s.flyApplied then pcall(function() if s.ownerAutomatic==false then s.root:SetNetworkOwner(s.previousOwner) else s.root:SetNetworkOwnershipAuto() end end) end
 s.humanoid=nil;s.original=nil;s.root=nil;s.flyApplied=false
end
local function apply(player,s)
 restore(s)
 local character=player.Character;local h=character and character:FindFirstChildOfClass("Humanoid")
 local root=character and character:FindFirstChild("HumanoidRootPart")
 if not h or h.Health<=0 or not root or not root:IsA("BasePart") or root.Anchored then return false,"Character not ready or root anchored" end
 s.humanoid=h;s.root=root;s.original={speed=h.WalkSpeed,rotate=h.AutoRotate,platform=h.PlatformStand,state=h:GetState()}
 if s.fly then
  local ownershipOK,automatic=pcall(function() return root:GetNetworkOwnershipAuto() end)
  s.ownerAutomatic=if ownershipOK then automatic else true
  if s.ownerAutomatic==false then s.previousOwner=root:GetNetworkOwner() end
  root:SetNetworkOwner(nil) -- server owns and applies flight physics
  s.flyApplied=true
  s.attachment=Instance.new("Attachment");s.attachment.Name="SEDWAREServerFlyAttachment";s.attachment.Parent=root
  s.constraint=Instance.new("LinearVelocity");s.constraint.Name="SEDWAREServerFlyVelocity"
  s.constraint.Attachment0=s.attachment;s.constraint.RelativeTo=Enum.ActuatorRelativeTo.World
  s.constraint.VelocityConstraintMode=Enum.VelocityConstraintMode.Vector;s.constraint.ForceLimitsEnabled=true
  s.constraint.MaxForce=s.maxForce;s.constraint.VectorVelocity=Vector3.zero;s.constraint.Parent=root
  h.AutoRotate=false;h.PlatformStand=true;h:ChangeState(Enum.HumanoidStateType.Physics)
 elseif s.speed then h.WalkSpeed=s.walkSpeed;s.appliedSpeed=s.walkSpeed end
 player:SetAttribute("SEDWAREMovementToken",s.token)
 player:SetAttribute("SEDWAREServerFlyActive",s.fly)
 player:SetAttribute("SEDWAREServerSpeedActive",s.speed and not s.fly)
 return true,"Server applied; physical result must be measured separately"
end
control.OnServerInvoke=function(player,r)
 if player:GetAttribute("SEDWAREMovementAuthorized")~=true then return {ok=false,reason="Server authorization denied"} end
 if type(r)~="table" or type(r.token)~="string" or #r.token>100 or type(r.fly)~="boolean" or type(r.speed)~="boolean"
  or not finite(r.flySpeed) or r.flySpeed<1 or r.flySpeed>200
  or not finite(r.walkSpeed) or r.walkSpeed<1 or r.walkSpeed>100
  or not finite(r.maxForce) or r.maxForce<1000 or r.maxForce>10000000 then return {ok=false,reason="Invalid movement request"} end
 local previous=states[player];local now=os.clock()
 if previous and now-(previous.lastRequest or 0)<0.03 then return {ok=false,reason="Request rate exceeded"} end
 if previous then restore(previous) end
 local s={player=player,token=r.token,fly=r.fly,speed=r.speed,flySpeed=r.flySpeed,walkSpeed=r.walkSpeed,maxForce=r.maxForce,lastInput=now,lastRequest=now}
 if not r.fly and not r.speed then states[player]=nil;return {ok=true,reason="Server movement disabled"} end
 states[player]=s
 local ok,accepted,reason=pcall(apply,player,s)
 if not ok or not accepted then restore(s);states[player]=nil;return {ok=false,reason=tostring(if ok then reason else accepted)} end
 return {ok=true,reason=reason}
end
connect(input.OnServerEvent,function(player,token,velocity)
 local s=states[player];if not s or token~=s.token then return end
 if velocity=="Stop" then restore(s);states[player]=nil;return end
 if player:GetAttribute("SEDWAREMovementAuthorized")~=true then restore(s);states[player]=nil;return end
 local now=os.clock();if now-s.lastInput<0.04 then return end
 if typeof(velocity)~="Vector3" or not finite(velocity.X) or not finite(velocity.Y) or not finite(velocity.Z)
  or velocity.Magnitude>s.flySpeed+0.01 then return end
 s.lastInput=now
 if s.constraint then s.constraint.VectorVelocity=velocity end
end)
connect(Run.Heartbeat,function()
 local now=os.clock()
 for player,s in states do
  if player:GetAttribute("SEDWAREMovementAuthorized")~=true or now-s.lastInput>0.8
   or player.Character==nil or not s.root or not s.root:IsDescendantOf(player.Character) or s.humanoid.Health<=0 then
   restore(s);states[player]=nil
  elseif not s.nextMeasure or now>=s.nextMeasure then
   s.nextMeasure=now+.2
   local v=s.root.AssemblyLinearVelocity
   if typeof(v)=="Vector3" and finite(v.X) and finite(v.Y) and finite(v.Z) then
    player:SetAttribute("SEDWAREMeasuredHorizontalSpeed",math.sqrt(v.X*v.X+v.Z*v.Z))
    player:SetAttribute("SEDWAREMeasuredVerticalSpeed",v.Y)
   end
  end
 end
end)
local function grant(player)
 player:SetAttribute("SEDWAREMovementAuthorized",true)
 connections[player]=player.CharacterRemoving:Connect(function() local s=states[player];if s then restore(s);states[player]=nil end end)
end
connect(Players.PlayerAdded,grant)
connect(Players.PlayerRemoving,function(player)
 local s=states[player];if s then restore(s);states[player]=nil end
 if connections[player] then connections[player]:Disconnect();connections[player]=nil end
end)
for _,player in Players:GetPlayers() do grant(player) end
workspace:SetAttribute("SEDWAREMovementProtocolVersion",1)

if script and script.Destroying then
 connect(script.Destroying,function()
  for _,s in states do restore(s) end;table.clear(states)
  for _,connection in connections do connection:Disconnect() end;table.clear(connections)
  for _,connection in globalConnections do connection:Disconnect() end;table.clear(globalConnections)
  workspace:SetAttribute("SEDWAREMovementProtocolVersion",nil)
  control.OnServerInvoke=nil;control:Destroy();input:Destroy()
 end)
end
