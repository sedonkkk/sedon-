--!nonstrict
-- Talks ONLY to the public protocol supplied by this repository for owned places.
-- Never probes another game's remotes. Requests yield in task.spawn, never render.
local MovementBridge={};MovementBridge.__index=MovementBridge
function MovementBridge.new(config,report)
 local self=setmetatable({config=config,report=report,available=false,active=false,state="LOCAL_DECLARATION_ONLY",
  token=tostring(os.clock())..":"..tostring(math.random(1,1000000000)),revision=0},MovementBridge)
 self:refresh()
 return self
end
function MovementBridge:refresh()
 if self.available or self.destroyed then return end
 local report=self.report
 if report.world:GetAttribute("SEDWAREMovementProtocolVersion")~=1 then return end
 local ok,storage=pcall(function() return game:GetService("ReplicatedStorage") end)
 if ok then
  self.control=storage:FindFirstChild("SEDWAREMovementControl")
  self.input=storage:FindFirstChild("SEDWAREMovementInput")
  self.available=self.control~=nil and self.control:IsA("RemoteFunction") and self.input~=nil and self.input:IsA("RemoteEvent")
 end
 self.state=if self.available then "SERVER_READY" else "SERVER_COMPONENT_MISSING"
end
function MovementBridge:sync(entry)
 if not self.available or self.destroyed then return end
 local c=self.config
 local character=entry and entry.character
 local previous=self.wanted
 if previous and self.character==character and self.humanoid==(entry and entry.humanoid) and self.root==(entry and entry.root) and previous.fly==c.Fly and previous.speed==c.Speed
  and previous.flySpeed==c.FlySpeed and previous.walkSpeed==c.WalkSpeed and previous.maxForce==c.FlyMaxForce then return end
 self.character=character;self.humanoid=entry and entry.humanoid;self.root=entry and entry.root;self.revision+=1
 self.wanted={token=self.token,fly=c.Fly,speed=c.Speed,flySpeed=c.FlySpeed,walkSpeed=c.WalkSpeed,maxForce=c.FlyMaxForce}
 self:_send()
end
function MovementBridge:_send()
 if self.inflight or self.destroyed then return end
 local revision=self.revision;local request=table.clone(self.wanted)
 self.inflight=true;self.state="WAITING_SERVER";self.started=os.clock()
 task.spawn(function()
  local ok,result=pcall(function() return self.control:InvokeServer(request) end)
  self.inflight=false
  if self.destroyed then return end
  if revision~=self.revision then self:_send();return end
  self.active=ok and type(result)=="table" and result.ok==true
  self.state=if self.active then "SERVER_CONFIRMED" else "SERVER_REJECTED"
  self.reason=if ok and type(result)=="table" then result.reason else tostring(result)
  if self.reason=="Request rate exceeded" and (self.rateRetries or 0)<3 then
   self.rateRetries=(self.rateRetries or 0)+1
   task.delay(.1,function() if not self.destroyed and revision==self.revision then self:_send() end end)
  else self.rateRetries=0 end
 end)
end
function MovementBridge:step(now,velocity)
 if self.destroyed then return end
 if not self.available then
  if not self.nextProbe or now>=self.nextProbe then self.nextProbe=now+.5;self:refresh() end
  if not self.available then return end
 end
 if self.inflight and os.clock()-self.started>3 then self.active=false;self.state="SERVER_TIMEOUT" end
 if self.config.Fly or self.config.Speed then
  if not self.nextSend or now>=self.nextSend then
   self.nextSend=now+0.1
   local player=self.report.player
   local own=player:GetAttribute("SEDWAREMovementToken")==self.token
   self.serverFly=own and player:GetAttribute("SEDWAREServerFlyActive")==true
   self.serverSpeed=own and player:GetAttribute("SEDWAREServerSpeedActive")==true
   self.input:FireServer(self.token,velocity or Vector3.zero)
  end
 end
end
function MovementBridge:destroy()
 if self.destroyed then return end;self.destroyed=true;self.active=false
 if self.available then pcall(function() self.input:FireServer(self.token,"Stop") end) end
end
return MovementBridge
