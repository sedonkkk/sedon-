--!nonstrict
-- Actual embedded V3.2 modules with Vector3/CFrame API doubles. Scheduled
-- timesteps are not Roblox FPS, and these cases do not verify native rendering,
-- character physics, weapons, network replication, or a third-party game.
return function(reloadBundle)
 local Mock=require("./CamV2Mock")
 local tests,checks,failures=0,0,0
 local function check(value,message)
  checks+=1;assert(value,message or ("V3.2 tracking assertion at line "..tostring(debug.info(2,"l"))))
 end
 local function near(actual,expected,tolerance)
  check(type(actual)=="number" and actual==actual and math.abs(actual-expected)<=(tolerance or 1e-7),
   tostring(actual).." ~= "..tostring(expected))
 end
 local function test(name,body)
  tests+=1;local mock=Mock.new();local api=reloadBundle(mock.env)
  local ok,problem=pcall(body,mock,api)
  if not ok then failures+=1;print("FAIL V3.2 tracking "..name..": "..tostring(problem)) end
  api.Unload()
  if mock:countConnections()~=0 or mock:countRenderBindings()~=0 or mock.tweens.active~=0 then
   failures+=1;print("FAIL V3.2 tracking cleanup "..name)
  end
 end
 local function controller(m,a,overrides)
  local config=assert(a.Modules.Config.new(overrides))
  return a.Modules.CameraController.new(config),{CFrame=m.env.CFrame.new(m.env.Vector3.zero)},config
 end
 local function predicted(m,pitch,yaw,distance)
  local p,y=math.rad(pitch),math.rad(yaw or 0);local d=distance or 10
  return m.env.Vector3.new(math.sin(y)*math.cos(p)*d,math.sin(p)*d,-math.cos(y)*math.cos(p)*d)
 end
 local function measuredAngles(frame)
  local v=frame.LookVector
  return math.atan2(v.X,-v.Z),math.atan2(v.Y,math.sqrt(v.X*v.X+v.Z*v.Z))
 end
 local function boundedFrame(c,cam,config,target,dt,context,previous)
  local oldYaw,oldPitch=measuredAngles(cam.CFrame)
  check(c:update(cam,target,dt,context))
  local yaw,pitch=measuredAngles(cam.CFrame)
  local yawRate=math.deg((yaw-oldYaw+math.pi)%(2*math.pi)-math.pi)/dt
  local pitchRate=math.deg(pitch-oldPitch)/dt
  local d=c:GetDiagnostics()
  near(pitchRate,d.pitchRate,1e-5);near(yawRate,d.yawRate,1e-5)
  check(math.abs(pitchRate)<=config.PitchMaxSpeed+1e-5,"applied pitch rate exceeded cap")
  if d.yawRateGuarded then check(math.abs(yawRate)<=config.AngularMaxSpeed+1e-5,"risk-guarded yaw rate exceeded cap") end
  if previous and not d.constraintConflict then
   local pitchAcceleration=(pitchRate-previous.pitchRate)/dt
   local yawAcceleration=(yawRate-previous.yawRate)/dt
   near(pitchAcceleration,d.accelerationApplied,1e-4);near(yawAcceleration,d.yawAccelerationApplied,1e-4)
   check(math.abs(pitchAcceleration)<=config.PitchMaxAcceleration+1e-4,"applied pitch acceleration exceeded cap")
   check(not d.yawAccelerationBounded,"a global yaw acceleration guarantee was claimed")
  end
  check(math.abs(cam.CFrame.RightVector.Y)<1e-6 and cam.CFrame.UpVector.Y>= -1e-7,"camera roll or inversion")
  check(d.angularError==d.angularError and d.safetyLimited)
  return d
 end
 test("static goal arrival brakes without the V3.1 acceleration discontinuity",function(m,a)
  for _,fps in {30,60,120,144} do for _,smooth in {.405,0} do
   local c,cam,config=controller(m,a,{Smoothness=smooth,TrackingMode="Fixed"})
   local previous=nil;local context={movementPhase="Rising",distanceStuds=10,reversalScale=1}
   for _=1,math.floor(fps*1.5) do
    previous=boundedFrame(c,cam,config,predicted(m,10),1/fps,context,previous)
    check(previous.pitchOvershootDegrees<1e-6,"static pitch goal crossed")
    check(not previous.constraintConflict,"ordinary arrival reported hard conflict")
   end
   check(math.abs(previous.pitchError)<.02,"static goal did not converge")
   check(previous.overshootReference=="STABLE_SETPOINT")
  end end
 end)
 test("Rising Falling Landing Grounded changes retain the applied velocity",function(m,a)
  for _,fps in {30,60,120,144} do
   local c,cam,config=controller(m,a,{Smoothness=.405});local previous=nil
   for i=1,fps do
    local phase=if i<4 then "Rising" elseif i<7 then "Falling" elseif i<10 then "Landing" else "Grounded"
    previous=boundedFrame(c,cam,config,predicted(m,25),1/fps,{movementPhase=phase,distanceStuds=10,reversalScale=1},previous)
    check(not previous.constraintConflict)
   end
   check(math.abs(previous.pitchError)<.1)
  end
 end)
 test("rapid moving goals brake with bounded inertia and disclose the reference",function(m,a)
  for _,fps in {30,60,120,144} do
   local c,cam,config=controller(m,a,{Smoothness=0});local previous=nil;local recovery=false;local changed=false
   for i=1,fps*2 do
    local t=i/fps;local pitch=if t<.16 then 25 elseif t<.32 then -25 elseif t<.48 then 20 else -10
    previous=boundedFrame(c,cam,config,predicted(m,pitch),1/fps,{movementPhase="Freefall",distanceStuds=10,reversalScale=1},previous)
    recovery=recovery or previous.safetyState=="BRAKING_RECOVERY"
    if previous.setpointChange>1 then changed=true;check(previous.overshootReference=="MOVING_SETPOINT") end
    check(not previous.constraintConflict)
   end
   check(recovery and changed,"goal reversal did not expose braking/reference diagnostics")
   check(math.abs(previous.pitchError)<.1)
  end
 end)
 test("near lateral reversals preserve historical yaw rate guard and report actual acceleration",function(m,a)
  for _,fps in {30,60,120,144} do
   local c,cam,config=controller(m,a,{Smoothness=0});local previous=nil
   for i=1,fps*2 do
    local yaw=if i<fps/3 then 40 elseif i<fps*2/3 then -40 else 15
    previous=boundedFrame(c,cam,config,predicted(m,5,yaw,3),1/fps,{movementPhase="Grounded",distanceStuds=3,reversalScale=.5},previous)
    check(not previous.constraintConflict)
   end
   check(math.abs(previous.yawError)<.1)
  end
 end)
 test("calibration without context and explicit AngularSafety false retain instant behavior",function(m,a)
  for _,withContext in {false,true} do
   local c,cam=controller(m,a,{Smoothness=0,AngularSafety=not withContext})
   local target=predicted(m,30,45)
   check(c:update(cam,target,1/144,if withContext then {movementPhase="Rising",distanceStuds=10,reversalScale=1} else nil))
   check((cam.CFrame.LookVector-target.Unit).Magnitude<1e-7)
   check(c:GetDiagnostics().safetyState=="BYPASSED")
  end
 end)
 test("reset and replacement cameras declare a new acceleration reference",function(m,a)
  local c,cam=controller(m,a,{Smoothness=0});local context={movementPhase="Rising",distanceStuds=10,reversalScale=1}
  check(c:update(cam,predicted(m,30),1/60,context));check(c:update(cam,predicted(m,30),1/60,context))
  check(c:GetDiagnostics().accelerationReference=="PREVIOUS_APPLIED_FRAME")
  c:reset();check(c:GetDiagnostics().safetyState=="IDLE")
  check(c:update(cam,predicted(m,-30),1/60,context))
  check(c:GetDiagnostics().accelerationReference=="INITIAL_OR_RESET_FRAME" and c:GetDiagnostics().safetyState=="INITIAL_FRAME")
  local replacement={CFrame=m.env.CFrame.new(m.env.Vector3.new(3,2,1))}
  check(c:update(replacement,predicted(m,20),1/60,context))
  check(c:GetDiagnostics().accelerationReference=="INITIAL_OR_RESET_FRAME")
  check((replacement.CFrame.Position-m.env.Vector3.new(3,2,1)).Magnitude==0)
 end)
 test("alternating airborne phases cannot bypass the vertical innovation cap",function(m,a)
  local V=m.env.Vector3;local config=assert(a.Modules.Config.new({Enabled=true}));local p=a.Modules.PredictionEngine.new(config)
  local previous=nil;local previousKnown=false;local anomalies=0
  for i,y in {0,2,1,2,1,2} do
   local t=(i-1)*.05;check(p:observe(t,V.new(0,y,-50),"Freefall"))
   local out=assert(p:predict(V.zero,t));check(out.verticalRawVelocityKnown==(i>1))
   if previousKnown then check(math.abs(out.verticalVelocityEstimate-previous)<=config.MaxVerticalVelocityChange*.05+1e-7) end
   if out.verticalAnomaly then anomalies+=1;check(out.verticalAnomalyReason=="VERTICAL_ACCELERATION_CAP") end
   check(math.abs(out.position.Y-out.currentPosition.Y)<=config.MaxVerticalLead+1e-7)
   previous=out.verticalVelocityEstimate;previousKnown=out.verticalRawVelocityKnown
  end
  check(anomalies>=3,"phase-changing spikes were not diagnosed")
 end)
 test("cold midair and gap restart do not invent a previous zero velocity",function(m,a)
  local V=m.env.Vector3;local p=a.Modules.PredictionEngine.new(assert(a.Modules.Config.new({Enabled=true})))
  check(p:observe(0,V.new(0,5,-50),"Jumping"))
  local first=assert(p:predict(V.zero,0));check(not first.verticalRawVelocityKnown and first.verticalRawVelocity==nil)
  near(first.verticalVelocityUsed,0)
  check(p:observe(.05,V.new(0,7,-50),"Jumping"))
  local measured=assert(p:predict(V.zero,.05));check(measured.verticalRawVelocityKnown and not measured.verticalAnomaly)
  near(measured.verticalRawVelocity,40);near(measured.verticalVelocityEstimate,40);near(measured.verticalVelocityUsed,40)
  check(p:observe(1,V.new(0,12,-50),"Freefall"))
  local gap=assert(p:predict(V.zero,1));check(not gap.verticalRawVelocityKnown and gap.verticalRawVelocity==nil)
  near(gap.verticalVelocityUsed,0)
  check(p:observe(1.05,V.new(0,8,-50),"Freefall"))
  local afterGap=assert(p:predict(V.zero,1.05));check(afterGap.verticalRawVelocityKnown and not afterGap.verticalAnomaly)
  near(afterGap.verticalVelocityEstimate,-80);near(afterGap.verticalVelocityUsed,-80)
 end)
 test("genuine Jumping and landing impulses remain explicit across consecutive jumps",function(m,a)
  local V=m.env.Vector3;local p=a.Modules.PredictionEngine.new(assert(a.Modules.Config.new({Enabled=true})))
  check(p:observe(0,V.new(0,0,-50),"Running"))
  check(p:observe(.05,V.new(0,2,-50),"Jumping"))
  local first=assert(p:predict(V.zero,.05));check(first.verticalJumpImpulse and first.movementPhase=="Rising")
  near(first.verticalVelocityUsed,40);check(not first.verticalAnomaly)
  check(p:observe(.10,V.new(0,0,-50),"Landed"))
  local landed=assert(p:predict(V.zero,.10));check(landed.verticalLandingTransition and landed.movementPhase=="Landing")
  near(landed.verticalVelocityUsed,0);near(landed.position.Y,0)
  check(p:observe(.15,V.new(0,2,-50),"Jumping"))
  local second=assert(p:predict(V.zero,.15));check(second.verticalJumpImpulse and second.movementPhase=="Rising")
  near(second.verticalVelocityUsed,40)
 end)
 test("apex hysteresis resists small noisy phase changes and rejected samples retain state",function(m,a)
  local V=m.env.Vector3;local p=a.Modules.PredictionEngine.new(assert(a.Modules.Config.new({Enabled=true})))
  local y=0;check(p:observe(0,V.new(0,y,-50),"Freefall"))
  for i=1,12 do
   y+=(if i%2==0 then -3.2 else 3.2)*.05
   check(p:observe(i*.05,V.new(0,y,-50),"Freefall"))
   local out=assert(p:predict(V.zero,i*.05));check(out.movementPhase=="Apex")
  end
  local latest=p.history:latest();local raw=p.vertical.rawVelocityY
  check(not p:observe(.65,V.new(0/0,0,-50),"Freefall"))
  check(p.history:latest()==latest and p.vertical.rawVelocityY==raw)
 end)
 test("jump fall reversal and near trajectories remain finite across FPS and RTT fixtures",function(m,a)
  local V=m.env.Vector3
  for _,fps in {30,60,120,144} do for _,rtt in {.060,.100,.300} do
   local config=assert(a.Modules.Config.new({Enabled=true,AutoPrediction=true}))
   local p=a.Modules.PredictionEngine.new(config);local c,cam=controller(m,a,{Enabled=true,AutoPrediction=true})
   local previous=nil;local nextObservation=0
   for i=0,fps*2 do
    local t=i/fps;local cycle=t%.7;local air=cycle>0 and cycle<.5
    local y=if air then 20*cycle-40*cycle*cycle else 0
    local state=if not air then "Running" elseif cycle<.25 then "Jumping" else "Freefall"
    local x=if t<1 then 8*t else 8-8*(t-1)
    if t+1e-7>=nextObservation then
     check(p:observe(t,V.new(x,y,-6),state));nextObservation=t+1/30
    end
    p:samplePing(rtt,t);local out=assert(p:predict(V.zero,t))
    previous=boundedFrame(c,cam,config,out.position,1/fps,out,previous)
    check(math.abs(out.position.Y-out.currentPosition.Y)<=config.MaxVerticalLead+1e-7)
    check(not out.physicsVerified and out.observationDelaySeconds==nil)
   end
  end end
 end)
 print(string.format("SEDWARE V3.2 tracking actual-bundle doubles: %d tests, %d assertions, %d failures",tests,checks,failures))
 assert(failures==0,"V3.2 tracking regressions failed")
end
