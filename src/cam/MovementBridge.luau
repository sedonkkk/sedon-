--!nonstrict
-- Talks ONLY to the public protocol supplied by this repository for owned places.
-- Never probes another game's remotes. Requests yield in task.spawn, never render.
local MovementBridge={};MovementBridge.__index=MovementBridge
function MovementBridge.new(config,report)
 local self=setmetatable({config=config,report=report,available=false,active=false,state="SERVER_COMPONENT_MISSING",
  token=tostring(os.clock())..":"..tostring(math.random(1,1000000000)),revision=0,generation=0},MovementBridge)
 self:refresh()
 return self
end
function MovementBridge:_invalidate(reason)
 -- Responses from the previous component cannot confirm its replacement.
 if self.input and (self.active or self.wanted and (self.wanted.fly or self.wanted.speed)) then
  pcall(function() self.input:FireServer(self.token,"Stop") end)
 end
 self.generation+=1;self.revision+=1;self.inflight=false;self.rateRetries=0
 self.available=false;self.active=false;self.serverFly=false;self.serverSpeed=false
 self.wanted=nil;self.character=nil;self.humanoid=nil;self.root=nil;self.ready=nil;self.authorized=nil
 self.control=nil;self.input=nil;self.storage=nil;self.nextSend=nil
 self.state="SERVER_COMPONENT_MISSING";self.reason=reason
end
function MovementBridge:refresh()
 if self.destroyed then return end
 local storage,control,input
 if self.report.world:GetAttribute("SEDWAREMovementProtocolVersion")==1 then
  local ok,result=pcall(function() return game:GetService("ReplicatedStorage") end)
  if ok and result then
   storage=result;control=storage:FindFirstChild("SEDWAREMovementControl");input=storage:FindFirstChild("SEDWAREMovementInput")
   if not control or not control:IsA("RemoteFunction") or not input or not input:IsA("RemoteEvent") then control=nil;input=nil end
  end
 end
 local available=control~=nil and input~=nil
 if self.available==available and self.control==control and self.input==input and self.storage==storage then return end
 self:_invalidate("Own movement server component disappeared or changed")
 self.storage=storage
 if available then
  self.storage=storage;self.control=control;self.input=input;self.available=true
  self.state="SERVER_READY";self.reason=nil
 end
end
function MovementBridge:sync(entry)
 if not self.available or self.destroyed or self.config.MovementMode=="Local" then return end
 local c=self.config
 local character=entry and entry.character
 local humanoid,root=entry and entry.humanoid,entry and entry.root
 local ready=humanoid~=nil and humanoid.Health>0 and root~=nil and not root.Anchored
 local authorized=self.report.player:GetAttribute("SEDWAREMovementAuthorized")==true
 local previous=self.wanted
 if previous and self.character==character and self.humanoid==humanoid and self.root==root and self.ready==ready and self.authorized==authorized
  and previous.fly==c.Fly and previous.speed==c.Speed and previous.flySpeed==c.FlySpeed and previous.walkSpeed==c.WalkSpeed and previous.maxForce==c.FlyMaxForce
  and previous.flyOrientation==c.FlyOrientation and previous.maxTorque==c.FlyMaxTorque
  and previous.maxAngularVelocity==c.FlyMaxAngularVelocity and previous.orientationResponsiveness==c.FlyOrientationResponsiveness then return end
 self.character=character;self.humanoid=humanoid;self.root=root;self.ready=ready;self.authorized=authorized;self.revision+=1
 self.wanted={token=self.token,fly=c.Fly,speed=c.Speed,flySpeed=c.FlySpeed,walkSpeed=c.WalkSpeed,maxForce=c.FlyMaxForce,
  flyOrientation=c.FlyOrientation,maxTorque=c.FlyMaxTorque,maxAngularVelocity=c.FlyMaxAngularVelocity,orientationResponsiveness=c.FlyOrientationResponsiveness}
 self:_send()
end
function MovementBridge:_send()
 if self.inflight or self.destroyed or not self.available or not self.wanted then return end
 local revision,generation=self.revision,self.generation;local request=table.clone(self.wanted);local control=self.control
 self.active=false;self.serverFly=false;self.serverSpeed=false
 self.inflight=true;self.state="WAITING_SERVER";self.started=os.clock();self.reason=nil
 task.spawn(function()
  local ok,result=pcall(function() return control:InvokeServer(request) end)
  if self.destroyed or generation~=self.generation then return end
  self.inflight=false
  if revision~=self.revision then self:_send();return end
  self.active=ok and type(result)=="table" and result.ok==true
  self.state=if self.active then "SERVER_CONFIRMED" else "SERVER_REJECTED"
  self.reason=if ok and type(result)=="table" then result.reason else tostring(result)
  if self.reason=="Request rate exceeded" and (self.rateRetries or 0)<3 then
   self.rateRetries=(self.rateRetries or 0)+1
   task.delay(.1,function() if not self.destroyed and generation==self.generation and revision==self.revision then self:_send() end end)
  else self.rateRetries=0 end
 end)
end
function MovementBridge:step(now,velocity)
 if self.destroyed then return end
 -- Probe at a bounded rate; a removed parent/protocol invalidates immediately.
 if not self.nextProbe or now>=self.nextProbe or (self.available and
  (self.report.world:GetAttribute("SEDWAREMovementProtocolVersion")~=1 or self.control.Parent~=self.storage or self.input.Parent~=self.storage)) then
  self.nextProbe=now+.5;self:refresh()
 end
 if not self.available then return end
 if self.inflight and os.clock()-self.started>3 then
  self.active=false;self.serverFly=false;self.serverSpeed=false;self.state="SERVER_TIMEOUT";self.reason="Own server request timed out after 3 seconds"
 end
 if not self.nextSend or now>=self.nextSend then
  self.nextSend=now+0.1
  local player=self.report.player
  local own=self.active and player:GetAttribute("SEDWAREMovementToken")==self.token
  self.serverFly=own and player:GetAttribute("SEDWAREServerFlyActive")==true
  self.serverSpeed=own and player:GetAttribute("SEDWAREServerSpeedActive")==true
  if self.config.MovementMode~="Local" and (self.config.Fly or self.config.Speed) and (self.active or self.inflight and self.state~="SERVER_TIMEOUT") then
   local sent,problem=pcall(function() self.input:FireServer(self.token,velocity or Vector3.zero) end)
   if not sent then
    self.active=false;self.serverFly=false;self.serverSpeed=false;self.state="SERVER_REJECTED";self.reason="Own movement input failed: "..tostring(problem)
   end
  end
 end
end
function MovementBridge:destroy()
 if self.destroyed then return end;self.destroyed=true;self.generation+=1;self.active=false;self.serverFly=false;self.serverSpeed=false
 if self.available then pcall(function() self.input:FireServer(self.token,"Stop") end) end
end
return MovementBridge
