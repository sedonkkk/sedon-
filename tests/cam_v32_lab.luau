--!nonstrict
-- Reproducible V3.1 / V3.2 comparison of the ACTUAL standalone module factories.
-- Every Vector3/CFrame is a CLI double. FPS is a scheduled timestep, RTT and
-- capture delay are fixtures; no native renderer, network, physics or hit runs.
return function(currentSource, baselineSource, options)
 options=options or {}
 local Mock=require("./CamV2Mock")
 local versions={}
 for _,label in {"V3.1","V3.2"} do
  local mock=Mock.new()
  local chunk=assert(loadstring(if label=="V3.1" then baselineSource else currentSource,"Calibration."..label))
  setfenv(chunk,mock.env)
  local api=chunk()
  versions[label]={mock=mock,api=api,config=api.Modules.Config,
   engine=api.Modules.PredictionEngine,controller=api.Modules.CameraController}
 end
 local scenarios={"Walking","Running","RepeatedJump","Landing","Falling","Reversal","Near","Far","Circle","Stop","Teleport","VariablePing"}
 local fpsValues=if options.quick then {30,144} else {30,60,120,144}
 local pingValues=if options.quick then {60,300} else {60,100,150,300}
 local policies=if options.quick then {"Manual"} else {"Manual","Auto"}
 local duration=options.duration or 3
 local function trajectory(name,t,V)
  t=math.max(t,0)
  local x,y,z,state=12*t,0,-60,"Running"
  if name=="Running" then x=24*t
  elseif name=="RepeatedJump" then
   local phase=t%0.8;local flight=2*45/196.2
   x=18*t;y=math.max(0,45*phase-98.1*phase*phase)
   state=if phase<flight then (if phase<45/196.2 then "Jumping" else "Freefall") elseif phase<flight+0.06 then "Landed" else "Running"
  elseif name=="Landing" then
   local phase=math.max(0,t-0.3);local flight=2*42/120
   x=16*t;y=if t<0.3 or phase>=flight then 0 else 42*phase-60*phase*phase
   state=if t<0.3 then "Running" elseif phase<flight then (if phase<42/120 then "Jumping" else "Freefall") elseif phase<flight+0.08 then "Landed" else "Running"
  elseif name=="Falling" then
   x=12*t;y=math.max(0,24-48*t*t);z=-40
   state=if t<math.sqrt(0.5) then "Freefall" elseif t<math.sqrt(0.5)+0.08 then "Landed" else "Running"
  elseif name=="Reversal" then x=if t<1.5 then 20*t else 30-20*(t-1.5)
  elseif name=="Near" then x=8*math.sin(3*t);z=-12
  elseif name=="Far" then x=24*t;z=-250
  elseif name=="Circle" then x=20*math.sin(2*t);z=-60+20*math.cos(2*t)
  elseif name=="Stop" then x=24*math.min(t,1.5);z=-40
  elseif name=="Teleport" then x=12*t+(if t>=1.5 then 70 else 0);z=-80
  elseif name=="VariablePing" then x=18*t;z=-80 end
  return V.new(x,y,z),state
 end
 local function rtt(name,base,t)
  if name~="VariablePing" then return base end
  return math.clamp(base*(0.85+0.35*math.sin(3*t))+(if t>=1.3 and t<1.8 then base*0.35 else 0),1,1000)
 end
 local function wrap(x) return (x+math.pi)%(2*math.pi)-math.pi end
 local function angles(v)
  return math.atan2(v.X,-v.Z),math.atan2(v.Y,math.sqrt(v.X*v.X+v.Z*v.Z))
 end
 local function sign(value) return if value>0.05 then 1 elseif value< -0.05 then -1 else 0 end
 local function finite(value) return value==value and math.abs(value)<math.huge end
 local columns={"version","scenario","fps","nominalRttMs","mode","policy","samples",
  "meanAngularDegrees","maxAngularDegrees","meanYawErrorDegrees","maxYawErrorDegrees",
  "meanPitchErrorDegrees","maxPitchErrorDegrees","meanSetpointAngularDegrees","maxSetpointAngularDegrees",
  "acquisitionSeconds","trackedSeconds","meanPredictedErrorStuds","maxPredictedErrorStuds",
  "meanInstantPositionErrorStuds","maxInstantPositionErrorStuds","maxRollDegrees",
  "yawSignChanges","pitchSignChanges","stopYawOvershootDegrees","landingPitchUndershootDegrees",
  "maxYawRateDegreesPerSecond","maxPitchRateDegreesPerSecond","maxPitchAccelerationDegreesPerSecond2",
  "meanVerticalHorizonSeconds","meanHorizontalHorizonSeconds","limitedLeadSamples","rawFutureHorizonSecondsY"}
 local extraColumns={"postWarmupSamples","meanYawAfterWarmupDegrees","meanPitchAfterWarmupDegrees",
  "maxContinuousPitchAccelerationDegreesPerSecond2","pitchAccelerationViolationFrames",
  "hardConstraintFrames","initialReferenceFrames","brakingRecoveryFrames","goalCrossingFrames",
  "stableGoalOvershootMaxDegrees","movingGoalFrames","verticalAnomalyFrames","apexLeadLimitedFrames","unknownRawVelocityFrames"}
 for _,column in extraColumns do table.insert(columns,column) end
 -- Emit the complete schema after appending scoped continuity metrics.
 print("V32_HEADER,"..table.concat(columns,","))
 local rows=0;local totalSamples=0
 for _,name in scenarios do for _,fps in fpsValues do for _,ping in pingValues do
  for _,mode in {"Fixed","Adaptive","Critical"} do for _,policy in policies do
   for _,version in {"V3.1","V3.2"} do
    local bundle=versions[version];local V,F=bundle.mock.env.Vector3,bundle.mock.env.CFrame
    local config=assert(bundle.config.new({Enabled=true,TrackingMode=mode,MotionFilter="Memory",AutoPrediction=policy=="Auto",MaxDistance=1000}))
    local engine=bundle.engine.new(config)
    local cam={CFrame=F.lookAt(V.zero,V.new(-60,0,-60))}
    local controller=bundle.controller.new(config)
    local nextSample,nextPing=0,0
    local count,totalAngular,maxAngular,totalYaw,maxYaw,totalPitch,maxPitch=0,0,0,0,0,0,0
    local totalSetpoint,maxSetpoint,totalPred,maxPred,totalInstant,maxInstant=0,0,0,0,0,0
    local yawChanges,pitchChanges,previousYawSign,previousPitchSign=0,0,nil,nil
    local maxRoll,maxYawRate,maxPitchRate,maxPitchAccel,previousPitchRate=0,0,0,0,nil
    local stopOvershoot,landingUndershoot=0,0
    local acquire,tracked,held,lastYaw,lastPitch=nil,0,0,nil,nil
    local totalVerticalHorizon,totalHorizontalHorizon,limited,rawHorizon=0,0,0,0
    local postCount,postYaw,postPitch,continuousAccel,violations=0,0,0,0,0
    local hardFrames,initialFrames,recoveryFrames,crossingFrames,stableOvershoot,movingFrames=0,0,0,0,0,0
    local anomalyFrames,apexFrames,unknownFrames=0,0,0
    for i=0,math.floor(duration*fps) do
     local t=i/fps;local dt=1/fps
     if t+1e-7>=nextPing then engine:samplePing(rtt(name,ping,t)/1000,t);nextPing=t+0.2 end
     if t+1e-7>=nextSample then
      local receipt=math.floor((t+1e-7)*30)/30
      -- Only the simulator knows the capture time. The production estimator
      -- receives the local receipt timestamp, with no invented server API.
      local capture=math.max(0,receipt-rtt(name,ping,receipt)/2000)
      local position,state=trajectory(name,capture,V)
      position+=V.new(0.04*math.sin(capture*80),0.025*math.sin(capture*60),0)
      engine:observe(receipt,position,state)
      nextSample=(math.floor((t+1e-7)*30)+1)/30
     end
     local out=engine:predict(V.zero,t)
     if out then
      assert(controller:update(cam,out.position,dt,out),version.." camera failed in "..name)
      local actual=trajectory(name,t,V)
      local trueYaw,truePitch=angles(actual)
      local yaw,pitch=angles(cam.CFrame.LookVector)
      local signedYaw,signedPitch=math.deg(wrap(yaw-trueYaw)),math.deg(pitch-truePitch)
      local angular=math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(actual.Unit),-1,1)))
      local expectedX=trajectory(name,t+out.predictionX,V)
      local expectedY=trajectory(name,t+out.predictionY,V)
      local expected=V.new(expectedX.X,expectedY.Y,expectedX.Z)
      local predicted=(out.position-expected).Magnitude;local instant=(out.position-actual).Magnitude
      local diagnostics=controller:GetDiagnostics()
      local setpoint=diagnostics.angularError
      if t>=.5 then postCount+=1;postYaw+=math.abs(signedYaw);postPitch+=math.abs(signedPitch) end
      if diagnostics.constraintConflict then hardFrames+=1 end
      if diagnostics.accelerationReference=="INITIAL_OR_RESET_FRAME" then initialFrames+=1 end
      if diagnostics.safetyState=="BRAKING_RECOVERY" then recoveryFrames+=1 end
      if diagnostics.pitchGoalCrossed then crossingFrames+=1 end
      if diagnostics.overshootReference=="MOVING_SETPOINT" then movingFrames+=1 end
      stableOvershoot=math.max(stableOvershoot,diagnostics.pitchOvershootDegrees or 0)
      if out.verticalAnomaly then anomalyFrames+=1 end
      if out.verticalApexLeadLimited then apexFrames+=1 end
      if out.verticalRawVelocityKnown==false then unknownFrames+=1 end
      count+=1;totalAngular+=angular;maxAngular=math.max(maxAngular,angular)
      totalYaw+=math.abs(signedYaw);maxYaw=math.max(maxYaw,math.abs(signedYaw))
      totalPitch+=math.abs(signedPitch);maxPitch=math.max(maxPitch,math.abs(signedPitch))
      totalSetpoint+=setpoint;maxSetpoint=math.max(maxSetpoint,setpoint)
      totalPred+=predicted;maxPred=math.max(maxPred,predicted)
      totalInstant+=instant;maxInstant=math.max(maxInstant,instant)
      maxRoll=math.max(maxRoll,math.abs(controller.diagnostics.roll))
      if setpoint<=1 then
       tracked+=dt;held+=dt
       -- Acquisition means 100ms of angular agreement with the prediction;
       -- it is not a candidate-selection or weapon-hit measurement.
       if held>=0.1 and not acquire then acquire=t+dt end
      else held=0 end
      local ys,ps=sign(signedYaw),sign(signedPitch)
      if ys~=0 then if previousYawSign and ys~=previousYawSign then yawChanges+=1 end;previousYawSign=ys end
      if ps~=0 then if previousPitchSign and ps~=previousPitchSign then pitchChanges+=1 end;previousPitchSign=ps end
      if name=="Stop" and t>=1.5 then stopOvershoot=math.max(stopOvershoot,signedYaw) end
      if (name=="Landing" and t>=1) or (name=="Falling" and t>=math.sqrt(0.5)) then landingUndershoot=math.max(landingUndershoot,-signedPitch) end
      if lastYaw then
       local yr=math.deg(wrap(yaw-lastYaw))/dt;local pr=math.deg(pitch-lastPitch)/dt
       maxYawRate=math.max(maxYawRate,math.abs(yr));maxPitchRate=math.max(maxPitchRate,math.abs(pr))
       if previousPitchRate then
        local acceleration=math.abs(pr-previousPitchRate)/dt
        maxPitchAccel=math.max(maxPitchAccel,acceleration)
        -- The baseline has no epoch/conflict metadata, so its consecutive
        -- output frames are measured directly. The new controller discloses
        -- resets/hard poles rather than quietly excluding a failed bound.
        local continuous=not diagnostics.constraintConflict
         and diagnostics.accelerationReference~="INITIAL_OR_RESET_FRAME"
        if continuous then
         continuousAccel=math.max(continuousAccel,acceleration)
         if acceleration>config.PitchMaxAcceleration+1e-4 then violations+=1 end
        end
       end
       previousPitchRate=pr
      end
      lastYaw,lastPitch=yaw,pitch
      totalVerticalHorizon+=out.verticalHorizonUsed or out.predictionY
      totalHorizontalHorizon+=out.horizontalHorizonUsed or out.predictionX
      rawHorizon=out.predictionY
      if out.verticalLeadLimited then limited+=1 end
      assert(finite(angular) and finite(predicted) and finite(instant),"Non-finite lab metric")
     end
    end
    assert(count>0 and maxRoll<1e-6,"Lab missing samples or nonzero roll")
    local values={version,name,fps,ping,mode,policy,count,totalAngular/count,maxAngular,totalYaw/count,maxYaw,
     totalPitch/count,maxPitch,totalSetpoint/count,maxSetpoint,acquire or -1,tracked,totalPred/count,maxPred,
     totalInstant/count,maxInstant,maxRoll,yawChanges,pitchChanges,stopOvershoot,landingUndershoot,
     maxYawRate,maxPitchRate,maxPitchAccel,totalVerticalHorizon/count,totalHorizontalHorizon/count,limited,rawHorizon,
     postCount,if postCount>0 then postYaw/postCount else 0,if postCount>0 then postPitch/postCount else 0,
     continuousAccel,violations,hardFrames,initialFrames,recoveryFrames,crossingFrames,stableOvershoot,movingFrames,
     anomalyFrames,apexFrames,unknownFrames}
    local encoded={}
    for _,value in values do table.insert(encoded,if type(value)=="number" then string.format("%.9f",value) else value) end
    print("V32_LAB,"..table.concat(encoded,","))
    rows+=1;totalSamples+=count
   end
  end end
 end end end
 for _,bundle in versions do bundle.api.Unload() end
 print(string.format("V32 SUMMARY: %d paired-version rows, %d scheduled samples; CLI math / API doubles only",rows,totalSamples))
 return {rows=rows,samples=totalSamples}
end

