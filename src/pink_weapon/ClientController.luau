--!nonstrict
-- OWNED weapon routing only. The client requests an aim point; only an independent
-- server raycast can confirm contact. This module does not touch camera or remotes.
local ClientController = {}
ClientController.__index = ClientController

local function finite(value)
 return type(value)=="number" and value==value and math.abs(value)<math.huge
end
local function vector(value)
 if typeof(value)~="Vector3" and type(value)~="table" then return false end
 local ok,x,y,z=pcall(function() return value.X,value.Y,value.Z end)
 return ok and finite(x) and finite(y) and finite(z)
end
local function integer(value) return finite(value) and value%1==0 end
local function samePosition(a,b)
 return vector(a) and vector(b) and a.X==b.X and a.Y==b.Y and a.Z==b.Z
end
local function traceback(problem)
 return if debug and type(debug.traceback)=="function" then debug.traceback(tostring(problem),2) else tostring(problem)
end
local function invoke(callback,...)
 return xpcall(callback,traceback,...)
end

function ClientController.new(options)
 assert(type(options)=="table","Owned weapon options required")
 local api=options.api
 assert(type(api)=="table" and type(api.GetLockedTarget)=="function" and type(api.GetPredictedPosition)=="function",
  "SEDWARE target/prediction API required")
 for _,name in {"clock","send","getCameraAim","getOrigin","isEquipped"} do
  assert(type(options[name])=="function",name.." callback required")
 end
 assert(type(options.sessionId)=="string" and #options.sessionId>=1 and #options.sessionId<=64,"Invalid owned weapon sessionId")
 assert(options.onStatus==nil or type(options.onStatus)=="function","Invalid onStatus callback")
 assert(options.getWeapon==nil or type(options.getWeapon)=="function","Invalid weapon provider")
 local timeout,maxPending=options.timeout or 2,options.maxPending or 64
 assert(finite(timeout) and timeout>0 and timeout<=10,"Invalid response timeout")
 assert(integer(maxPending) and maxPending>=1 and maxPending<=500,"Invalid pending capacity")
 local adapter=options.adapter
 if not adapter then
  assert(type(api.CreateShotAdapter)=="function","SEDWARE owned shot adapter API required")
  local ok,result,problem=invoke(api.CreateShotAdapter,nil,{getOrigin=options.getOrigin,maxAge=options.maxAge or 1})
  assert(ok and result,"Cannot create owned shot adapter: "..tostring(if ok then problem else result))
  adapter=result
 end
 assert(type(adapter)=="table" and type(adapter.capture)=="function" and type(adapter.record)=="function"
  and type(adapter.destroy)=="function","Invalid owned shot adapter")
 return setmetatable({api=api,adapter=adapter,clock=options.clock,send=options.send,getCameraAim=options.getCameraAim,
  getOrigin=options.getOrigin,isEquipped=options.isEquipped,onStatus=options.onStatus,sessionId=options.sessionId,
  weaponName=options.weaponName or "SEDWARE Revolver",getWeapon=options.getWeapon,timeout=timeout,maxPending=maxPending,pending={},pendingCount=0,
  nextId=0,destroyed=false,lastResult=nil,stats={sent=0,confirmed=0,hits=0,selectedTargetHits=0,misses=0,
   rejected=0,timedOut=0,measurementCount=0}},ClientController)
end

function ClientController:_status(kind,details)
 if self.onStatus then pcall(self.onStatus,kind,details) end
end
function ClientController:_reject(reason)
 self:_status("ClientRejected",{reason=tostring(reason)})
 return nil,tostring(reason)
end

function ClientController:fire()
 if self.destroyed then return nil,"destroyed" end
 local equipped,isEquipped=invoke(self.isEquipped)
 if not equipped or isEquipped~=true then return self:_reject(if equipped then "weapon-not-equipped" else "equipment-check-failed: "..tostring(isEquipped)) end
 local clockOK,now=invoke(self.clock)
 if not clockOK or not finite(now) then return self:_reject("invalid-clock") end
 self:step(now)
 if self.pendingCount>=self.maxPending then return self:_reject("pending-capacity") end
 local weapon
 if self.getWeapon then
  local weaponOK,result=invoke(self.getWeapon)
  if not weaponOK or type(result)~="table" or type(result.id)~="string" or #result.id<1 or #result.id>40
   or not finite(result.timeout) or result.timeout<=0 or result.timeout>10 then return self:_reject("invalid-compatible-weapon") end
  weapon=result
 end
 local originOK,origin=invoke(self.getOrigin)
 if not originOK or not vector(origin) then return self:_reject("muzzle-origin-unavailable") end
 local lockedOK,target=invoke(self.api.GetLockedTarget)
 if not lockedOK then return self:_reject("target-api-failed: "..tostring(target)) end
 local ticket,aimpoint,mode
 if target then
  mode="Locked"
  local captured,result,problem=invoke(function() return self.adapter:capture() end)
  if not captured or not result then return self:_reject("prediction-capture-failed: "..tostring(if captured then problem else result)) end
  ticket=result
  local predicted,resultPosition=invoke(self.api.GetPredictedPosition,origin)
  if not predicted or not vector(resultPosition) then return self:_reject("locked-prediction-unavailable") end
  aimpoint=resultPosition -- Exact public API position, never camera direction while locked.
  local currentOK,current=invoke(self.api.GetLockedTarget)
  if not currentOK or current~=target or target.UserId~=ticket.targetUserId then return self:_reject("target-changed-during-capture") end
  if not samePosition(aimpoint,ticket.aimpointActive) then return self:_reject("prediction-changed-during-capture") end
  if not integer(ticket.id) or not finite(ticket.sampleTime) or not finite(ticket.capturedAt) then return self:_reject("invalid-capture-ticket") end
 else
  mode="Normal"
  local aimed,result=invoke(self.getCameraAim)
  if not aimed or not vector(result) then return self:_reject("camera-aim-unavailable") end
  aimpoint=result
 end
 local dx,dy,dz=aimpoint.X-origin.X,aimpoint.Y-origin.Y,aimpoint.Z-origin.Z
 local length=math.sqrt(dx*dx+dy*dy+dz*dz)
 if not finite(length) or length<=0.001 then return self:_reject("degenerate-aimpoint") end
 self.nextId+=1
 local request={sessionId=self.sessionId,shotId=self.nextId,mode=mode,capturedAt=now,origin=origin,aimpoint=aimpoint}
 if weapon then request.weaponId=weapon.id end
 if ticket then
  local partName=if self.api.session and self.api.session.config then self.api.session.config.TargetPart else ticket.part and ticket.part.Name
  if type(partName)~="string" or #partName<1 or #partName>64 then return self:_reject("invalid-target-part") end
  request.ticketId=ticket.id;request.targetUserId=ticket.targetUserId
  request.targetCharacter=ticket.character;request.partName=partName;request.sampleTime=ticket.sampleTime
 end
 table.freeze(request)
 -- Register before send, so synchronous owned transports can return a result.
 local entry={request=request,ticket=ticket,sentAt=now,timeout=if weapon then weapon.timeout else self.timeout,launched=false}
 self.pending[request.shotId]=entry;self.pendingCount+=1
 self:_status("Pending",{request=request,shotId=request.shotId,mode=mode})
 local sent,result=invoke(self.send,request)
 if not sent or result==false then
  if self.pending[request.shotId] then self.pending[request.shotId]=nil;self.pendingCount-=1 end
  return self:_reject("send-failed: "..tostring(result))
 end
 self.stats.sent+=1
 return request
end

function ClientController:receive(response)
 if self.destroyed then return nil,"destroyed" end
 if type(response)~="table" or response.sessionId~=self.sessionId or not integer(response.shotId) then return nil,"foreign-or-invalid-response" end
 local clockOK,now=invoke(self.clock)
 if not clockOK or not finite(now) then return nil,"invalid-clock" end
 self:step(now)
 local entry=self.pending[response.shotId]
 if not entry then return nil,"unknown-or-expired-shot" end
 local request=entry.request
 if type(response.accepted)~="boolean" or (response.mode~=nil and response.mode~=request.mode) then return nil,"malformed-response" end
 if response.ticketId~=nil and response.ticketId~=request.ticketId then return nil,"ticket-mismatch" end
 if response.weaponId~=request.weaponId then return nil,"weapon-mismatch" end
 if response.pending==true then
  if response.accepted~=true or response.mode~=request.mode or response.stage~="Launched" or response.hit~=nil
   or response.selectedTargetHit~=nil or response.damageApplied~=nil or entry.launched then return nil,"invalid-launch-confirmation" end
  entry.launched=true
  self:_status("InFlight",{shotId=request.shotId,mode=request.mode,weaponId=request.weaponId})
  return {pending=true,shotId=request.shotId,weaponId=request.weaponId}
 end
 if response.accepted then
  if response.mode~=request.mode or type(response.hit)~="boolean" or type(response.selectedTargetHit)~="boolean"
   or (response.selectedTargetHit and (not response.hit or request.mode~="Locked"))
   or (response.damageApplied~=nil and (not finite(response.damageApplied) or response.damageApplied<0))
   or not finite(response.referenceTime) or response.referenceTime<entry.sentAt-0.05 or response.referenceTime>now+0.25 then
   return nil,"malformed-confirmation"
  end
  if response.impactPosition~=nil and not vector(response.impactPosition) then return nil,"invalid-impact-position" end
  if request.mode=="Locked" then
   if response.targetUserId~=request.targetUserId or response.character~=request.targetCharacter then return nil,"target-mismatch" end
   if response.actualPosition~=nil and not vector(response.actualPosition) then return nil,"invalid-reference-position" end
  end
 end
 self.pending[response.shotId]=nil;self.pendingCount-=1
 local result={sessionId=self.sessionId,shotId=request.shotId,mode=request.mode,accepted=response.accepted,
  reason=response.reason,referenceTime=response.referenceTime,impactPosition=response.impactPosition,
  hit=response.accepted and response.hit==true,selectedTargetHit=response.accepted and response.selectedTargetHit==true,
  damageApplied=response.damageApplied,hitName=response.hitName,request=request,weaponId=request.weaponId,
  pelletCount=response.pelletCount,pelletHits=response.pelletHits,pellets=response.pellets,
  engine=response.engine,physicsKind=response.physicsKind}
 if response.accepted then
  self.stats.confirmed+=1
  if result.hit then self.stats.hits+=1 else self.stats.misses+=1 end
  if result.selectedTargetHit then self.stats.selectedTargetHits+=1 end
  if entry.ticket and response.actualPosition then
   local measured,record,problem=invoke(function() return self.adapter:record(entry.ticket,response) end)
   if measured and record then result.measurement=record;self.stats.measurementCount+=1
   else result.measurementError=tostring(if measured then problem else record) end
  elseif entry.ticket then result.measurementError="server-reference-unavailable" end
 else self.stats.rejected+=1 end
 self.lastResult=table.freeze(result)
 self:_status(if response.accepted then "Confirmed" else "ServerRejected",self.lastResult)
 return self.lastResult
end

function ClientController:step(now)
 if self.destroyed then return end
 if now==nil then
  local ok,value=invoke(self.clock)
  if not ok then return end
  now=value
 end
 if not finite(now) then return end
 for id,entry in self.pending do
  if now-entry.sentAt>=entry.timeout then
   self.pending[id]=nil;self.pendingCount-=1;self.stats.timedOut+=1
   self:_status("Timeout",{shotId=id,mode=entry.request.mode,reason="server-response-timeout"})
  end
 end
end
function ClientController:summary()
 local result=table.clone(self.stats)
 result.pending=self.pendingCount
 return result
end
function ClientController:destroy()
 if self.destroyed then return end
 self.destroyed=true
 table.clear(self.pending);self.pendingCount=0
 self.adapter:destroy()
 self.api=nil;self.send=nil;self.clock=nil;self.getCameraAim=nil;self.getOrigin=nil;self.isEquipped=nil;self.onStatus=nil;self.getWeapon=nil
end
return ClientController
