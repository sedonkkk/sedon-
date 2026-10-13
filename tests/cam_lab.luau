-- CLI math comparison using the ACTUAL V2 controller snapshot as baseline.
local Lab=require("../src/cam/CalibrationLab")
local Mock=require("./CamV2Mock").new()
local Baseline=require("./baselines/CamV2Camera")
local function emit(row)
 print(string.format("LAB,%s,%d,%d,%s,%s,%d,%.9f,%.9f,%.9f,%.9f,%.9f,%.9f,%d,%.9f,%.9f,%.9f,%.9f,%s",
 row.scenario,row.fps,row.pingMs,row.mode,row.filter,row.samples,row.meanAngular,row.maxAngular,
 row.acquisitionSeconds,row.trackingSeconds,row.meanPredictedError,row.maxRoll,row.oscillations,row.stopOvershoot,row.lateralLagSeconds or 0,row.meanSetpointAngular,row.maxSetpointAngular,row.policy))
 assert(row.samples>0 and row.maxRoll<1e-6,"Lab produced missing samples or roll")
 assert(row.meanAngular==row.meanAngular and row.meanPredictedError<math.huge,"Lab invalid metrics")
end
print("scenario,fps,pingMs,mode,filter,samples,meanAngularDegrees,maxAngularDegrees,acquisitionSeconds,trackingSeconds,meanPredictedErrorStuds,maxRollDegrees,signChanges,stopOvershootDegrees,lateralLagSeconds,meanSetpointAngularDegrees,maxSetpointAngularDegrees,policy")
local rows=Lab.run({Vector=Mock.env.Vector3,Frame=Mock.env.CFrame,BaselineController=Baseline},emit,{noise=true})
print(string.format("LAB SUMMARY: %d synthetic comparisons; native rendering/network not tested",#rows))
