--!nonstrict
-- Selection/lifecycle comparison of actual standalone Sessions, not a camera
-- mathematics surrogate. FPS is a scheduled timestep; all objects and events
-- are explicit CamV2Mock doubles. No Roblox renderer, network, hits or physics.
return function(currentSource,baselineSource)
 local Mock=require("./CamV2Mock")
 local columns={"version","scenario","fps","faultSeconds","actualFaultSeconds","lossCount",
  "reacquisitionCount","pausedSeconds","unlockedSeconds","lockedAtEnd","recoveredSamePlayer",
  "autoReacquired","otherPlayerSelections","firstLossAfterFaultSeconds","firstRecoveryAfterFaultSeconds",
  "finalTrackingState","lastLossCode","reacquirePolicy","frames"}
 print("V31_PERSISTENCE_HEADER,"..table.concat(columns,","))
 local scenarios={
  {name="BriefOcclusion",kind="occlusion",duration=.1},
  {name="LongOcclusion",kind="occlusion",duration=.4},
  {name="BriefPartAbsence",kind="part",duration=.1},
  {name="LongPartAbsence",kind="part",duration=.3},
 }
 local rows,totalFrames=0,0
 for _,version in {"V3","V3.1"} do for _,fps in {30,60,120,144} do for _,scenario in scenarios do
  local mock=Mock.new();local V=mock.env.Vector3
  local target=mock:addPlayer("PersistenceTarget",V.new(0,0,-50))
  local chunk=assert(loadstring(if version=="V3" then baselineSource else currentSource,"Persistence."..version))
  setfenv(chunk,mock.env);local api=chunk()
  -- Only fields shared by both versions. The different default reacquisition
  -- policies are preserved and exported rather than silently equalized.
  local session=api.init({Enabled=true,SmartSelection=true,TargetGraceSeconds=.2,
   Radius=180,MaxDistance=350,HitPart="HumanoidRootPart",WelcomeNotification=false})
  assert(session:GetLockedTarget()==target,"fixture failed initial target acquisition")
  local previous=target;local frames,losses,reacquisitions,paused,unlocked,other=0,0,0,0,0,0
  local faultStarted,firstLoss,firstRecovery
  local function observe(dt)
   local locked=session:GetLockedTarget()
   if previous==target and locked==nil then
    losses+=1;firstLoss=firstLoss or (faultStarted and mock:getTime()-faultStarted)
   elseif previous==nil and locked==target then
    reacquisitions+=1;firstRecovery=firstRecovery or (faultStarted and mock:getTime()-faultStarted)
   end
   if locked~=nil and locked~=target then other+=1 end
   if locked==target and session.pauseReason~=nil then paused+=dt end
   if locked==nil then unlocked+=dt end
   previous=locked
  end
  local function advanceFor(seconds)
   local stop=mock:getTime()+seconds
   while mock:getTime()<stop-1e-10 do
    local dt=math.min(1/fps,stop-mock:getTime())
    mock:advance(dt);frames+=1;observe(dt)
    assert(not session.destroyed,"actual session failed during fixture")
   end
  end
  advanceFor(.5)
  -- Warm-up frames cannot manufacture a loss/recovery result.
  assert(losses==0 and previous==target,"initial lock unstable before fault")
  faultStarted=mock:getTime()
  local character=target.Character
  local root=character:FindFirstChild("HumanoidRootPart")
  local position,size,frame=root.Position,root.Size,root.CFrame
  if scenario.kind=="occlusion" then mock:setOccluded(target,true)
  else root:Destroy() end
  observe(0) -- destruction signals can synchronously release a lock
  advanceFor(scenario.duration)
  local actualFault=mock:getTime()-faultStarted
  if scenario.kind=="occlusion" then mock:setOccluded(target,false)
  else
   -- A genuinely different part on the SAME character tests reference refresh;
   -- no player respawn or success notification is injected into the session.
   local replacement=mock.env.Instance.new("Part")
   replacement.Name="HumanoidRootPart";replacement.Position=position;replacement.Size=size
   replacement.CFrame=frame;replacement.AssemblyLinearVelocity=V.zero;replacement.Anchored=false
   replacement.Parent=character
  end
  observe(0)
  advanceFor(.8) -- permits the old .25-second acquisition schedule to run
  local final=session:GetLockedTarget()
  local diagnostic=if session.GetTrackingDiagnostics then session:GetTrackingDiagnostics() else nil
  local reacquirePolicy=if session.config.ReacquireOnLoss==nil then "implicit-auto" else tostring(session.config.ReacquireOnLoss)
  assert(other==0,"single-candidate fixture selected an unexpected player")
  local values={version,scenario.name,fps,scenario.duration,actualFault,losses,reacquisitions,paused,unlocked,
   tostring(final~=nil),tostring(final==target),tostring(losses>0 and reacquisitions>0),other,
   firstLoss or -1,firstRecovery or -1,
   diagnostic and diagnostic.trackingState or "Unavailable",
   if diagnostic then (diagnostic.lastLoss and diagnostic.lastLoss.code or "None") else "Unavailable",
   reacquirePolicy,frames}
  for index,value in values do
   if type(value)=="number" then values[index]=string.format("%.9f",value) end
  end
  print("V31_PERSISTENCE,"..table.concat(values,","))
  api.Unload()
  assert(mock:countConnections()==0 and mock:countRenderBindings()==0 and mock.tweens.active==0,"persistence fixture leaked session resources")
  rows+=1;totalFrames+=frames
 end end end
 print(string.format("V31 PERSISTENCE SUMMARY: %d rows, %d scheduled frames; actual-bundle API doubles only",rows,totalFrames))
 assert(rows==32,"persistence matrix incomplete")
end
