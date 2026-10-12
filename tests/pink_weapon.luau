--!nonstrict
-- Contract and transport tests for the REAL owned-weapon controllers, prediction
-- and ShotAdapter. Raycast/equipment/health callbacks below are explicit doubles;
-- these tests do not claim Roblox physics, Studio or Da Hood verification.
local ClientController = require("../src/pink_weapon/ClientController")
local ServerController = require("../src/pink_weapon/ServerController")
local WeaponSettings = require("../src/pink_weapon/WeaponSettings")
local Config = require("../src/pink/Config")
local Prediction = require("../src/pink/Prediction")
local ShotAdapter = require("../src/pink/ShotAdapter")
local V = require("./Vector")
local tests, checks, failures = 0, 0, 0
local function check(value, message)
 checks += 1
 assert(value, message or "assertion failed")
end
local function near(actual, expected)
 check(type(actual)=="number" and math.abs(actual-expected)<1e-8,
  "expected "..tostring(expected)..", got "..tostring(actual))
end
local function vectorNear(actual, expected)
 check(actual~=nil and (actual-expected).Magnitude<1e-7,
  "expected "..tostring(expected)..", got "..tostring(actual))
end
local function test(name, body)
 tests += 1
 local ok, problem = pcall(body)
 if not ok then failures += 1; print("FAIL "..name..": "..tostring(problem)) end
end
local function fixture(options)
 options = options or {}
 local state = {now=100, equipped=true, locked=options.locked~=false, statuses={}, sent={},
  targetAvailable=true, forceField=false, rayCalls=0, damageCalls=0, getLockedCalls=0,
  getPredictedCalls=0, cameraAimCalls=0, targetCalls=0, destroyed=false}
 local shooter = {UserId=-1}
 local target = {UserId=-2}
 local character, shooterCharacter = {}, {}
 target.Character = character
 local targetPart = {Name="HumanoidRootPart", Position=V.new(0,0,-30)}
 local targetHumanoid, shooterHumanoid = {Health=100}, {Health=100}
 local origin = V.new(0,0,0)
 local cameraAim = V.new(50,0,-30)
 local cameraToken = table.freeze({Position=V.new(0,2,10), Focus=V.new(0,2,0)})
 local config = assert(Config.new({PredictionSmoothing=0}))
 local predictor = Prediction.new(config)
 assert(predictor:observe(state.now-0.1,targetPart.Position,"Running"))
 assert(predictor:observe(state.now,targetPart.Position,"Running"))
 local comparisons = predictor:predictComparisons(origin,state.now)
 local snapshot
 local function refresh()
  comparisons = predictor:predictComparisons(origin,state.now)
  snapshot = {targetUserId=target.UserId,character=character,part=targetPart,
   sampleTime=comparisons.active.sampleTime,createdAt=state.now,
   active=comparisons.active,manual=comparisons.manual,auto=comparisons.auto}
 end
 refresh()
 local adapter = ShotAdapter.new({clock=function() return state.now end,
  getSnapshot=function() if state.locked then refresh(); return snapshot end; return nil end,
  isTargetValid=function(ticket) return state.locked and state.targetAvailable
   and ticket.targetUserId==target.UserId and ticket.character==target.Character end,
  maxAge=1,capacity=120})
 local api = {session={config=config}}
 function api.GetLockedTarget() state.getLockedCalls+=1; return if state.locked then target else nil end
 function api.GetPredictedPosition() state.getPredictedCalls+=1; return comparisons.active.position end
 function api.CreateShotAdapter() return adapter end
 local server = ServerController.new({
  clock=function() return state.now end,
  getEquippedWeapon=function(player)
   check(player==shooter)
   if not state.equipped then return nil end
   return {tool={},character=shooterCharacter,humanoid=shooterHumanoid,origin=origin}
  end,
  getTarget=function(userId,partName,requestedCharacter)
   state.targetCalls+=1
   if not state.targetAvailable or userId~=target.UserId or partName~=targetPart.Name
    or requestedCharacter~=target.Character then return nil end
   return {player=target,character=target.Character,part=targetPart,
    humanoid=targetHumanoid,position=targetPart.Position}
  end,
  raycast=function(rayOrigin,direction,ignoredCharacter)
   state.rayCalls+=1; state.rayOrigin=rayOrigin; state.rayDirection=direction
   check(ignoredCharacter==shooterCharacter,"raycast must exclude the shooter")
   if state.onRaycast then state.onRaycast() end
   return state.rayResult
  end,
  describeHit=function(result)
   return {name=result.name,position=result.position,character=result.character,
    humanoid=result.humanoid,playerUserId=result.playerUserId}
  end,
  applyDamage=function(humanoid,amount)
   state.damageCalls+=1
   local before=humanoid.Health
   if not state.forceField then humanoid.Health=math.max(0,before-amount) end
   return {before=before,after=humanoid.Health}
  end,
  settings=options.settings,
 })
 state.rayResult = {name="HumanoidRootPart",position=targetPart.Position,character=character,
  humanoid=targetHumanoid,playerUserId=target.UserId}
 local client = ClientController.new({api=api,clock=function() return state.now end,
  getOrigin=function() return origin end,
  getCameraAim=function() state.cameraAimCalls+=1; return cameraAim end,
  isEquipped=function() return state.equipped end,
  send=function(request) table.insert(state.sent,request); if state.sendCallback then return state.sendCallback(request) end end,
  sessionId=options.sessionId or "owned-test-session",timeout=options.timeout or 2,
  maxPending=options.maxPending or 64,
  onStatus=function(kind,details) table.insert(state.statuses,{kind=kind,details=details}) end})
 local f={state=state,client=client,server=server,api=api,adapter=adapter,predictor=predictor,
  config=config,shooter=shooter,target=target,targetPart=targetPart,targetHumanoid=targetHumanoid,
  shooterHumanoid=shooterHumanoid,character=character,shooterCharacter=shooterCharacter,
  origin=origin,cameraAim=cameraAim,cameraToken=cameraToken}
 function f:advance(seconds)
  state.now+=seconds
  assert(predictor:observe(state.now,targetPart.Position,"Running"))
  refresh()
 end
 function f:fire() local request,problem=client:fire(); check(request~=nil,problem); return request end
 function f:deliver(request)
  local response=server:process(shooter,request)
  local result,problem=client:receive(response)
  check(result~=nil,problem)
  return result,response
 end
 function f:mutated(changes)
  local request=table.clone(self:fire())
  for key,value in changes do request[key]=value end
  return request
 end
 function f:reject(request, reason)
  local response=server:process(shooter,request)
  check(response.accepted==false,"unexpected acceptance: "..tostring(response.reason))
  check(response.reason==reason,"expected "..reason..", got "..tostring(response.reason))
  near(state.rayCalls,0); near(state.damageCalls,0); near(targetHumanoid.Health,100)
  return response
 end
 return f
end

test("locked shot uses real public prediction and immutable ticket, never camera aim",function()
 local f=fixture()
 local request=f:fire()
 check(request.mode=="Locked")
 vectorNear(request.aimpoint,f.api.GetPredictedPosition())
 check(request.targetUserId==f.target.UserId and request.targetCharacter==f.character)
 check(request.partName=="HumanoidRootPart" and request.ticketId==1)
 near(f.state.cameraAimCalls,0); check(f.state.getLockedCalls>=2)
 near(f.state.getPredictedCalls,2)
 check(not pcall(function() request.mode="Normal" end))
 near(f.config.PredictionX,0.1205); near(f.config.PredictionY,0.0800)
end)

test("without lock weapon follows supplied crosshair and sends no target fields",function()
 local f=fixture({locked=false})
 local request=f:fire()
 check(request.mode=="Normal")
 vectorNear(request.aimpoint,f.cameraAim)
 check(request.targetUserId==nil and request.ticketId==nil and request.sampleTime==nil)
 near(f.state.getPredictedCalls,0); near(f.state.cameraAimCalls,1)
 near(f.adapter.nextId,0)
 local result=f:deliver(request)
 check(result.accepted and result.hit and not result.selectedTargetHit)
 near(f.state.targetCalls,0); near(f.targetHumanoid.Health,75)
end)

test("no local hit or damage appears before authoritative confirmation",function()
 local f=fixture()
 local request=f:fire()
 near(f.state.rayCalls,0); near(f.state.damageCalls,0); near(f.targetHumanoid.Health,100)
 check(f.client.lastResult==nil)
 local pending=f.client:summary()
 near(pending.pending,1); near(pending.confirmed,0); near(pending.hits,0)
 check(f.state.statuses[#f.state.statuses].kind=="Pending")
 f.state.now+=0.01
 local result,response=f:deliver(request)
 check(result.accepted and result.hit and result.selectedTargetHit)
 near(result.damageApplied,25); near(f.targetHumanoid.Health,75)
 vectorNear(f.state.rayOrigin,f.origin)
 near(f.state.rayDirection.Magnitude,400)
 check(result.measurement~=nil)
 near(result.measurement.referenceTime,response.referenceTime)
 near(f.client:summary().measurementCount,1)
 check(f.state.statuses[#f.state.statuses].kind=="Confirmed")
end)

test("perfect predicted aim cannot manufacture a hit when raycast returns nil",function()
 local f=fixture(); f.state.rayResult=nil
 local result,response=f:deliver(f:fire())
 check(result.accepted and not result.hit and not result.selectedTargetHit)
 check(response.reason=="miss")
 near(result.damageApplied,0); near(f.state.damageCalls,0); near(f.targetHumanoid.Health,100)
 near(f.client:summary().misses,1)
 check(result.measurement~=nil,"an independent position measurement can exist for a missed shot")
end)

test("normal unblocked crosshair shot can miss without requiring any target",function()
 local f=fixture({locked=false}); f.state.rayResult=nil
 local result=f:deliver(f:fire())
 check(result.accepted and not result.hit and result.measurement==nil)
 near(f.state.targetCalls,0); near(f.state.damageCalls,0)
end)

test("obstacle contact is physical contact, not a selected-target hit",function()
 local f=fixture()
 f.state.rayResult={name="Wall",position=V.new(0,0,-10)}
 local result,response=f:deliver(f:fire())
 check(result.accepted and result.hit and not result.selectedTargetHit)
 check(response.reason=="surface-impact" and result.hitName=="Wall")
 vectorNear(result.impactPosition,V.new(0,0,-10))
 near(result.damageApplied,0); near(f.state.damageCalls,0); near(f.targetHumanoid.Health,100)
 near(f.client:summary().selectedTargetHits,0)
end)

test("contact with another player does not report contact with locked target",function()
 local f=fixture(); local otherHumanoid={Health=80}
 f.state.rayResult={name="OtherHead",position=V.new(0,0,-20),character={},humanoid=otherHumanoid,playerUserId=-3}
 local result=f:deliver(f:fire())
 check(result.hit and not result.selectedTargetHit)
 near(result.damageApplied,25); near(otherHumanoid.Health,55); near(f.targetHumanoid.Health,100)
end)

test("ForceField-equivalent damage callback yields contact with zero actual damage",function()
 local f=fixture(); f.state.forceField=true
 local result=f:deliver(f:fire())
 check(result.hit and result.selectedTargetHit)
 near(result.damageApplied,0); near(f.targetHumanoid.Health,100); near(f.state.damageCalls,1)
end)

test("prediction position error uses independently measured server time and part position",function()
 local f=fixture()
 local request=f:fire()
 f.state.onRaycast=function() f.state.now+=0.02; f.targetPart.Position=V.new(2,0,-30) end
 local result,response=f:deliver(request)
 check(result.accepted and result.measurement~=nil)
 near(response.referenceTime,100.02)
 vectorNear(response.actualPosition,V.new(2,0,-30))
 near(result.measurement.active.errorStuds,2)
 check(response.referenceTime~=request.capturedAt+f.config.PredictionX)
end)

test("server ray uses authorized muzzle, not a near but client-claimed origin",function()
 local f=fixture()
 local request=f:mutated({origin=V.new(1,0,0)})
 local response=f.server:process(f.shooter,request)
 check(response.accepted)
 vectorNear(f.state.rayOrigin,f.origin)
 vectorNear(response.origin,f.origin)
 vectorNear(f.state.rayDirection,V.new(0,0,-400))
end)

test("stale requests and future timestamps are rejected without physical effects",function()
 for _,time in {99,101,0/0,math.huge} do
  local f=fixture(); f:reject(f:mutated({capturedAt=time}),"stale-request")
 end
end)

test("stale and future target samples are rejected independently of request time",function()
 for _,time in {99,101,0/0,math.huge} do
  local f=fixture(); f:reject(f:mutated({sampleTime=time}),"stale-sample")
 end
end)

test("nonfinite and malformed direction vectors never reach raycast",function()
 for _,bad in {V.new(math.huge,0,0),V.new(0/0,0,0),{},"not a vector"} do
  local f=fixture(); f:reject(f:mutated({aimpoint=bad}),"invalid-vectors")
 end
end)

test("server rejects far origins, degenerate aim and excessive aim distance",function()
 local cases={{origin=V.new(10,0,0),reason="invalid-origin"},
  {aimpoint=V.new(0,0,0),reason="degenerate-aimpoint"},
  {aimpoint=V.new(0,0,-3000),reason="aimpoint-out-of-range"}}
 for _,case in cases do
  local f=fixture(); local reason=case.reason; case.reason=nil
  f:reject(f:mutated(case),reason)
 end
end)

test("invalid mode and unexpected request fields are rejected",function()
 local f=fixture(); f:reject(f:mutated({mode="Dot"}),"invalid-mode")
 local g=fixture(); g:reject(g:mutated({damage=100000}),"unknown-field")
end)

test("normal shots cannot smuggle lock fields",function()
 local f=fixture({locked=false})
 f:reject(f:mutated({targetUserId=-2}),"unexpected-target-fields")
end)

test("forged target identities and unsupported parts are rejected",function()
 for _,change in {{targetUserId=-1},{targetUserId=1.5},{partName="FakePart"}} do
  local f=fixture(); f:reject(f:mutated(change),"invalid-target")
 end
 local f=fixture(); f:reject(f:mutated({targetCharacter={}}),"target-lost")
end)

test("locked target must still exist and be alive on server",function()
 local f=fixture(); local request=f:fire(); f.state.targetAvailable=false
 f:reject(request,"target-lost")
 local g=fixture(); local another=g:fire(); g.targetHumanoid.Health=0
 local response=g.server:process(g.shooter,another)
 check(not response.accepted and response.reason=="target-lost")
 near(g.state.rayCalls,0); near(g.state.damageCalls,0)
end)

test("locked target beyond actual weapon range cannot be fired at",function()
 local f=fixture(); local request=f:fire(); f.targetPart.Position=V.new(0,0,-401)
 f:reject(request,"target-out-of-range")
end)

test("no authorized equipped weapon or dead shooter cannot fire",function()
 local f=fixture(); local request=f:fire(); f.state.equipped=false
 f:reject(request,"weapon-not-equipped")
 local g=fixture(); local another=g:fire(); g.shooterHumanoid.Health=0
 g:reject(another,"weapon-not-equipped")
end)

test("cooldown and duplicate transport do not duplicate physical damage",function()
 local f=fixture(); local request=f:fire()
 local result=f:deliver(request)
 check(result.accepted); near(f.targetHumanoid.Health,75)
 local duplicate=f.server:process(f.shooter,request)
 check(not duplicate.accepted and duplicate.reason=="duplicate-shot")
 f:advance(0.1)
 local second=f:fire(); local rejected=f.server:process(f.shooter,second)
 check(not rejected.accepted and rejected.reason=="cooldown")
 near(f.state.rayCalls,1); near(f.state.damageCalls,1); near(f.targetHumanoid.Health,75)
 f:advance(0.3)
 local thirdResult=f:deliver(f:fire())
 check(thirdResult.accepted); near(f.targetHumanoid.Health,50)
end)

test("new transport session cannot bypass per-player cooldown",function()
 local f=fixture(); f:deliver(f:fire())
 local request=table.clone(f.state.sent[1]); request.sessionId="new-session"
 local rejected=f.server:process(f.shooter,request)
 check(not rejected.accepted and rejected.reason=="cooldown")
 near(f.state.rayCalls,1); near(f.targetHumanoid.Health,75)
end)

test("server callback errors remain visible and cannot claim success",function()
 local f=fixture(); f.state.onRaycast=function() error("workspace raycast unavailable") end
 local result,response=f:deliver(f:fire())
 check(not result.accepted and not result.hit)
 check(response.reason=="server-error")
 check(string.find(response.error,"workspace raycast unavailable",1,true)~=nil)
 near(f.state.damageCalls,0); near(f.targetHumanoid.Health,100)
end)

test("foreign, duplicate and mismatched responses cannot inflate counters",function()
 local f=fixture(); local request=f:fire()
 local response=f.server:process(f.shooter,request)
 local foreign=table.clone(response); foreign.sessionId="other"
 local _,foreignError=f.client:receive(foreign)
 check(foreignError=="foreign-or-invalid-response"); near(f.client:summary().confirmed,0)
 local wrongTicket=table.clone(response); wrongTicket.ticketId=999
 local _,ticketError=f.client:receive(wrongTicket)
 check(ticketError=="ticket-mismatch"); near(f.client:summary().pending,1)
 local wrongTarget=table.clone(response); wrongTarget.targetUserId=-3
 local _,targetError=f.client:receive(wrongTarget)
 check(targetError=="target-mismatch"); near(f.client:summary().confirmed,0)
 check(f.client:receive(response)~=nil)
 local _,duplicateError=f.client:receive(response)
 check(duplicateError=="unknown-or-expired-shot"); near(f.client:summary().confirmed,1)
end)

test("malformed confirmations remain pending and do not announce success",function()
 for _,change in {{accepted="yes"},{mode="Normal"},{hit="yes"},{selectedTargetHit=1},
  {referenceTime=99},{referenceTime=101},{impactPosition=V.new(0/0,0,0)},
  {damageApplied=-1},{damageApplied=math.huge},{hit=false,selectedTargetHit=true}} do
  local f=fixture(); local request=f:fire()
  local response=f.server:process(f.shooter,request)
  for key,value in change do response[key]=value end
  local result=f.client:receive(response)
  check(result==nil); near(f.client:summary().confirmed,0); near(f.client:summary().pending,1)
  check(f.state.statuses[#f.state.statuses].kind=="Pending")
 end
end)

test("explicit server rejection reports failure even if a forged hit field is true",function()
 local f=fixture(); local request=f:fire()
 local result=f.client:receive({sessionId=request.sessionId,shotId=request.shotId,mode=request.mode,
  accepted=false,reason="weapon-not-equipped",hit=true,selectedTargetHit=true})
 check(result~=nil and not result.accepted and not result.hit and not result.selectedTargetHit)
 near(f.client:summary().rejected,1); near(f.client:summary().hits,0)
 check(f.state.statuses[#f.state.statuses].kind=="ServerRejected")
end)

test("a missing response times out and late success is discarded",function()
 local f=fixture(); local request=f:fire()
 local response=f.server:process(f.shooter,request)
 f.state.now+=2.1; f.client:step()
 near(f.client:summary().pending,0); near(f.client:summary().timedOut,1)
 near(f.client:summary().confirmed,0)
 check(f.state.statuses[#f.state.statuses].kind=="Timeout")
 local result,problem=f.client:receive(response)
 check(result==nil and problem=="unknown-or-expired-shot")
end)

test("pending capacity is bounded until confirmation or timeout",function()
 local f=fixture({maxPending=1})
 f:fire()
 local request,problem=f.client:fire()
 check(request==nil and problem=="pending-capacity")
 near(#f.state.sent,1); near(f.client:summary().pending,1)
 f.state.now+=2.1; f.client:step()
 f:advance(0.01); check(f.client:fire()~=nil)
end)

test("locked prediction failure never falls back to camera direction",function()
 local f=fixture()
 f.api.GetPredictedPosition=function() return nil end
 local request,problem=f.client:fire()
 check(request==nil and problem=="locked-prediction-unavailable")
 near(f.state.cameraAimCalls,0); near(#f.state.sent,0); near(f.state.rayCalls,0)
end)

test("prediction drift between immutable capture and API read aborts shot",function()
 local f=fixture()
 f.api.GetPredictedPosition=function() return V.new(20,0,-30) end
 local request,problem=f.client:fire()
 check(request==nil and problem=="prediction-changed-during-capture")
 near(#f.state.sent,0); near(f.state.cameraAimCalls,0)
end)

test("lock changes during capture cannot mix player identities",function()
 local f=fixture(); local calls=0
 f.api.GetLockedTarget=function() calls+=1; return if calls==1 then f.target else nil end
 local request,problem=f.client:fire()
 check(request==nil and problem=="target-changed-during-capture")
 near(#f.state.sent,0)
end)

test("unlock before result preserves authoritative contact but rejects stale comparison",function()
 local f=fixture(); local request=f:fire()
 local response=f.server:process(f.shooter,request)
 f.state.locked=false
 local result=f.client:receive(response)
 check(result.accepted and result.hit and result.selectedTargetHit)
 check(result.measurement==nil and result.measurementError=="target-invalid")
 near(f.client:summary().measurementCount,0)
end)

test("transport exceptions and invalid callback values do not leave pending work",function()
 local f=fixture(); f.state.sendCallback=function() error("own transport offline") end
 local request,problem=f.client:fire()
 check(request==nil and string.find(problem,"send-failed",1,true)~=nil)
 near(f.client:summary().pending,0); near(f.client:summary().sent,0)
 near(f.state.rayCalls,0)
 local g=fixture(); g.state.equipped=false
 local none,reason=g.client:fire()
 check(none==nil and reason=="weapon-not-equipped"); near(#g.state.sent,0)
end)

test("real prediction modules retain memory and manual X/Y before weapon routing",function()
 local f=fixture()
 f.predictor:reset()
 check(f.predictor:observe(99.9,V.new(-1,-2,-30),"Running"))
 check(f.predictor:observe(100,V.new(0,0,-30),"Running"))
 local request=f:fire()
 local velocity=f.predictor.history.velocity
 check(velocity.X>0 and velocity.Y>0)
 vectorNear(request.aimpoint,V.new(velocity.X*0.1205,velocity.Y*0.08,-30))
 near(f.config.PredictionX,0.1205); near(f.config.PredictionY,0.08)
 check(f.config.MemoryTracking and f.config.VelocityPrediction)
end)


test("synchronous transport emits Pending before confirmed result",function()
 local f=fixture()
 f.state.sendCallback=function(request)
  local response=f.server:process(f.shooter,request)
  check(f.client:receive(response)~=nil)
 end
 f:fire()
 check(f.state.statuses[1].kind=="Pending")
 check(f.state.statuses[2].kind=="Confirmed")
 near(#f.state.statuses,2)
 near(f.client:summary().pending,0); near(f.client:summary().confirmed,1)
end)

test("normal confirmations cannot claim a selected target hit",function()
 local f=fixture({locked=false}); local request=f:fire()
 local response=f.server:process(f.shooter,request)
 response.selectedTargetHit=true
 local result,problem=f.client:receive(response)
 check(result==nil and problem=="malformed-confirmation")
 near(f.client:summary().confirmed,0)
end)

test("destroy clears pending, destroys adapter, and all subsequent entry points reject",function()
 local f=fixture(); local request=f:fire()
 local response=f.server:process(f.shooter,request)
 f.client:destroy(); f.client:destroy()
 near(f.client:summary().pending,0); check(f.adapter.destroyed)
 local fired,fireError=f.client:fire(); check(fired==nil and fireError=="destroyed")
 local received,receiveError=f.client:receive(response); check(received==nil and receiveError=="destroyed")
 f.server:destroy(); f.server:destroy()
 check(next(f.server.states)==nil)
 local rejected=f.server:process(f.shooter,request)
 check(not rejected.accepted and rejected.reason=="destroyed")
end)

test("removePlayer discards retained authority state for disconnected players",function()
 local f=fixture(); f:deliver(f:fire())
 check(f.server.states[f.shooter]~=nil)
 f.server:removePlayer(f.shooter)
 check(f.server.states[f.shooter]==nil)
end)

test("bounded session state does not grow indefinitely on repeated setup",function()
 local f=fixture({settings={MaxSessionsPerPlayer=2}})
 local request=f:fire()
 for index=1,5 do
  local changed=table.clone(request); changed.sessionId="session-"..index
  f.server:process(f.shooter,changed)
 end
 local state=f.server.states[f.shooter]
 near(#state.order,2)
 local count=0; for _ in state.sessions do count+=1 end; near(count,2)
 near(f.state.rayCalls,1)
end)

test("weapon settings validate plain configuration and native-independent limits",function()
 local defaults=WeaponSettings.new()
 check(defaults.WeaponName=="SEDWARE Revolver")
 near(defaults.Damage,25); near(defaults.Cooldown,0.35); near(defaults.Range,400)
 check(table.isfrozen(defaults) and table.isfrozen(defaults.AllowedParts))
 for _,bad in {{Damage=math.huge},{Range=0},{Cooldown=0},{RequestMaxAge=-1},
  {MaxSessionsPerPlayer=1.5},{UnknownSetting=true},{WeaponName=""}} do
  check(not pcall(WeaponSettings.new,bad))
 end
end)

print(string.format("Pink owned weapon: %d tests, %d assertions, %d failures (callback doubles, not Studio/Da Hood)",tests,checks,failures))
assert(failures==0,"owned-weapon controller regressions")
