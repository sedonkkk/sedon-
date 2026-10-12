--!nonstrict
-- Opt-in F6 exercise of ACTUAL equipped Tool.Activated + server responses.
-- This does not inject keyboard input, predict collisions or claim a pass from
-- mathematical errors. A native pass requires confirmed target contact/damage.
local NativeVerification={}
NativeVerification.__index=NativeVerification
function NativeVerification.new(options)
 for _,name in {"clock","wait","getTool","getHumanoid","getCameraAim","beginRun","endRun","publish"} do
  assert(type(options[name])=="function",name.." native verification callback required")
 end
 return setmetatable({options=options,running=false,destroyed=false,records={},order={},observedC=false,runId=nil},NativeVerification)
end
function NativeVerification:noteC()
 self.observedC=true
 self.observedTarget=self.options.api.GetLockedTarget()
 self.observedCharacter=self.observedTarget and self.observedTarget.Character
end
function NativeVerification:record(kind,details)
 if not self.running then return end
 if kind=="Pending" then
  if #self.order>=64 then self.overflow=true;return end
  local request=details.request
  local profile=self.options.manager.profiles[request.weaponId]
  local ok,aim=pcall(self.options.getCameraAim,profile)
  self.records[request.shotId]={request=request,normalAim=if ok then aim else nil}
  table.insert(self.order,request.shotId)
 elseif kind=="Confirmed" or kind=="ServerRejected" then
  local record=self.records[details.shotId]
  if record then record.result=details end
 elseif kind=="Timeout" then
  local record=self.records[details.shotId]
  if record then record.error="server-response-timeout" end
 end
end
function NativeVerification:_waitUntil(callback,seconds)
 local deadline=self.options.clock()+seconds
 while not self.destroyed and self.running and self.options.clock()<deadline do
  if callback() then return true end
  self.options.wait(0.05)
 end
 return callback() and not self.destroyed
end
function NativeVerification:_exercise(id,target)
 local o=self.options
 local profile=o.manager.profiles[id]
 local tool=o.getTool(id)
 assert(tool,"Native test Tool missing: "..id)
 o.manager:release()
 o.getHumanoid():EquipTool(tool)
 assert(self:_waitUntil(function() return o.manager.active and o.manager.active.profile.Id==id end,2),"Equip did not reach WeaponManager: "..id)
 assert(o.api.GetLockedTarget()==target,"Weapon change lost the locked target")
 local dotVisible=o.api.session.overlay.dot.Visible==true
 local delay=math.max(0,o.manager.nextFire-o.clock())+0.1
 o.wait(delay)
 local before=#self.order
 tool:Activate() -- Actual Tool event path, not a direct call to a mock fire API.
 if profile.Automatic then o.wait(profile.Cooldown*2.4) else o.wait(0.05) end
 tool:Deactivate();o.manager:release()
 assert(self:_waitUntil(function()
  if #self.order<=before then return false end
  for i=before+1,#self.order do local r=self.records[self.order[i]];if not r.result and not r.error then return false end end
  return true
 end,profile.Lifetime+2.5),"No authoritative final response: "..id)
 local record={weaponId=id,kind=profile.Kind,dotVisible=dotVisible,lockRetained=o.api.GetLockedTarget()==target,
  shots=0,targetHits=0,damageApplied=0,allAccepted=true,allNative=true,aimDiffers=false}
 for i=before+1,#self.order do
  local item=self.records[self.order[i]]
  local result=item.result
  record.shots+=1
  if not result or not result.accepted then record.allAccepted=false end
  if not result or result.engine~="RobloxWorkspace" or result.physicsKind~=profile.Kind then record.allNative=false end
  if result and result.selectedTargetHit then record.targetHits+=1;record.damageApplied+=result.damageApplied or 0 end
  if item.normalAim and (item.normalAim-item.request.aimpoint).Magnitude>1 then record.aimDiffers=true end
 end
 record.passed=record.lockRetained and record.dotVisible and record.allAccepted and record.allNative
  and record.targetHits>0 and record.damageApplied>0 and (not profile.Automatic or record.shots>=2)
 return record
end
function NativeVerification:run()
 if self.destroyed or self.running then return nil,"verification-already-running-or-destroyed" end
 local o=self.options
 local target=o.api.GetLockedTarget()
 if not target or not self.observedC or target~=self.observedTarget or target.Character~=self.observedCharacter then
  return nil,"Press C to select the current real player before F6"
 end
 local begun,setup=pcall(o.beginRun,target.UserId)
 if not begun or type(setup)~="table" or not setup.ok then return nil,"Native setup failed: "..tostring(if begun and type(setup)=="table" then setup.reason else setup) end
 self.runId=setup.runId;self.running=true;self.records={};self.order={};self.overflow=false
 local report={runId=setup.runId,runtime=o.runtimeName or "Unknown",observedC=self.observedC,
  targetUserId=target.UserId,startedAt=o.clock(),weapons={},passed=false}
 local ok,problem=xpcall(function()
  local ids={};for id in o.manager.profiles do table.insert(ids,id) end;table.sort(ids)
  for _,id in ids do
   assert(not self.destroyed,"Native verification cancelled")
   table.insert(report.weapons,self:_exercise(id,target))
  end
  o.api.UnlockTarget()
  assert(o.api.GetLockedTarget()==nil,"Unlock did not clear selection")
  local id=if o.manager.profiles.Pistol then "Pistol" else ids[1]
  o.getHumanoid():EquipTool(assert(o.getTool(id)))
  assert(self:_waitUntil(function() return o.manager.active and o.manager.active.profile.Id==id end,2),"Normal-fire Tool missing")
  o.wait(math.max(0,o.manager.nextFire-o.clock())+0.1)
  local before=#self.order
  local tool=o.getTool(id);tool:Activate();o.wait(0.05);tool:Deactivate();o.manager:release()
  assert(self:_waitUntil(function() return #self.order>before and self.records[self.order[before+1]].result~=nil end,3),"Normal fire was not confirmed")
  local normal=self.records[self.order[before+1]]
  report.normalFire=normal.request.mode=="Normal" and normal.request.targetUserId==nil
   and normal.result.accepted==true and normal.result.engine=="RobloxWorkspace"
  local allPassed,aimDiffers=true,false
  for _,entry in report.weapons do allPassed=allPassed and entry.passed;aimDiffers=aimDiffers or entry.aimDiffers end
  report.aimDiffersFromMira=aimDiffers
  report.passed=allPassed and report.normalFire and aimDiffers and not self.overflow and report.runtime=="RobloxStudio"
 end,debug.traceback)
 if not ok then report.error=tostring(problem) end
 self.running=false
 pcall(o.endRun,self.runId);self.runId=nil
 report.finishedAt=o.clock()
 o.publish(report)
 return report
end
function NativeVerification:destroy()
 if self.destroyed then return end
 self.destroyed=true;self.running=false
 if self.runId then
  local id=self.runId;self.runId=nil
  -- Native cleanup supplies a nonblocking endpoint wrapper; no shot is claimed.
  pcall(self.options.endRun,id)
 end
 table.clear(self.records);table.clear(self.order)
end
return NativeVerification
