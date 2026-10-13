--!nonstrict
-- Independent lab: synthetic trajectories, known capture age and simulated RTT.
-- No claimed native rendering, network or Da Hood verification.
local Config=if script then require(script.Parent.Config) else require("./Config")
local Engine=if script then require(script.Parent.PredictionEngine) else require("./PredictionEngine")
local Controller=if script then require(script.Parent.CameraController) else require("./CameraController")
local Lab={}
Lab.scenarios={"Walking","Running","Jumping","Falling","Reversal","Circle","Stop","Far","AngularStep"}
local function trajectory(name,t,V)
 t=math.max(0,t)
 local y=0;local x=12*t;local z=-60;local state="Running"
 if name=="AngularStep" then x=60;y=10
 elseif name=="Running" then x=24*t
 elseif name=="Jumping" then y=math.max(0,12*math.sin(math.pi*(t%2)/2));state=if t%2<1 then "Jumping" else "Freefall"
 elseif name=="Falling" then y=math.max(-15,15-8*t*t);state="Freefall"
 elseif name=="Reversal" then x=if t<1.5 then 18*t else 27-18*(t-1.5)
 elseif name=="Circle" then x=20*math.sin(t*2);z=-60+20*math.cos(t*2)
 elseif name=="Stop" then x=24*math.min(t,1.5)
 elseif name=="Far" then z=-250 end
 return V.new(x,y,z),state
end
Lab.trajectory=trajectory
function Lab.run(adapters,emit,options)
 local V,F=adapters.Vector,adapters.Frame;options=options or {}
 local rows={};local fpsValues=options.fps or {30,60,120,144}
 for _,scenario in options.scenarios or Lab.scenarios do
  for _,fps in fpsValues do for _,ping in options.ping or {0,60,120} do
   for _,mode in options.modes or {"Fixed","Adaptive","Critical"} do
    for _,filter in options.filters or {"Memory","AlphaBeta","OneEuro"} do
     for _,policy in options.policies or {"Manual","Auto"} do
     local config=assert(Config.new({Enabled=true,TrackingMode=mode,MotionFilter=filter,AutoPrediction=policy=="Auto",MaxDistance=1000}))
     local engine=Engine.new(config);local cam={CFrame=F.lookAt(V.new(0,0,0),V.new(-60,0,-60))}
     local controller=(if mode=="Fixed" and adapters.BaselineController then adapters.BaselineController else Controller).new(config,{newVector=V.new,fromBasis=function(p,r,u,l) return F.fromMatrix(p,r,u,-l) end})
     local total,maxError,positionError,tracked,acquisition=0,0,0,0,nil
     local setpointTotal,setpointMax=0,0
     local maxRoll,oscillations,overshoot,previousSigned,previousSign=0,0,0,nil,nil
     local nextSample,nextPing=0,0;local lastOutput;local count=0
     local duration=options.duration or 3
     local cpu=os.clock()
     for i=0,math.floor(fps*duration) do
      local t=i/fps
      if t+1e-7>=nextPing then engine:samplePing(ping/1000,t);nextPing=t+0.2 end
      if t+1e-7>=nextSample then
       local sampleTime=math.floor((t+1e-7)*30)/30-ping/2000 -- lab-only capture timestamp is known
       if sampleTime>=0 then
        local p,state=trajectory(scenario,sampleTime,V)
        -- bounded deterministic measurement noise; same continuous function at all FPS
        if options.noise then p+=V.new(0.08*math.sin(sampleTime*80),0.04*math.cos(sampleTime*60),0) end
        engine:observe(sampleTime,p,state)
       end
       nextSample=(math.floor((t+1e-7)*30)+1)/30
      end
      local out=engine:predict(V.new(0,0,0),t)
      if out then
       assert(controller:update(cam,out.position,1/fps))
       local truth=trajectory(scenario,t,V);local direction=truth.Unit
       local error=math.deg(math.acos(math.clamp(cam.CFrame.LookVector:Dot(direction),-1,1)))
       total+=error;maxError=math.max(maxError,error);count+=1
       local setpointError=controller.diagnostics.angularError
       setpointTotal+=setpointError;setpointMax=math.max(setpointMax,setpointError)
       if setpointError<1 then tracked+=1/fps;acquisition=acquisition or ((i+1)/fps) end
       local fx=trajectory(scenario,t+out.predictionX,V);local fy=trajectory(scenario,t+out.predictionY,V)
       local expected=V.new(fx.X,fy.Y,fx.Z)
       positionError+=(out.position-expected).Magnitude
       local signed=math.deg(math.atan2(cam.CFrame.LookVector.X,-cam.CFrame.LookVector.Z)-math.atan2(direction.X,-direction.Z))
       local sign=if signed>0.05 then 1 elseif signed< -0.05 then -1 else 0
       if previousSign and sign~=0 and previousSign~=0 and sign~=previousSign then oscillations+=1 end
       if sign~=0 then previousSign=sign end
       -- Signed lead can be intentional prediction; overshoot is measured only
       -- after the Stop trajectory's setpoint becomes stationary.
       if scenario=="Stop" and t>1.5 and signed>0 then overshoot=math.max(overshoot,signed) end
       previousSigned=signed;lastOutput=out
       maxRoll=math.max(maxRoll,math.abs(controller.diagnostics.roll))
      end
     end
     local row={scenario=scenario,fps=fps,pingMs=ping,mode=mode,filter=filter,policy=policy,samples=count,
      meanAngular=total/math.max(count,1),maxAngular=maxError,
      meanSetpointAngular=setpointTotal/math.max(count,1),maxSetpointAngular=setpointMax,acquisitionSeconds=acquisition or -1,
      trackingSeconds=tracked,meanPredictedError=positionError/math.max(count,1),maxRoll=maxRoll,
      oscillations=oscillations,stopOvershoot=overshoot,cpuSeconds=os.clock()-cpu}
     -- Constant lateral-motion equivalent lag; signed lead is reported separately.
     if scenario=="Walking" or scenario=="Running" then
      local t=duration;local truth=trajectory(scenario,t,V)
      local targetYaw=math.atan2(truth.X,-truth.Z);local yaw=math.atan2(cam.CFrame.LookVector.X,-cam.CFrame.LookVector.Z)
      local rate=(if scenario=="Walking" then 12 else 24)*(-truth.Z)/(truth.X^2+truth.Z^2)
      row.lateralLagSeconds=(targetYaw-yaw)/rate
     end
     table.insert(rows,row);if emit then emit(row) end
     end
    end
   end
  end end
 end
 return rows
end
return Lab
