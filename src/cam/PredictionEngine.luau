--!nonstrict
-- Preserve the existing bounded Memory Tracking, reversal/teleport recovery,
-- elapsed-time ping EMA and axis prediction. Camera interpolation is separate.
local Config = if script then require(script.Parent.Config) else require("./Config")
local Prediction = if script then require(script.Parent.Parent.pink.Prediction) else require("../pink/Prediction")
local MotionFilter=if script then require(script.Parent.MotionFilter) else require("./MotionFilter")
local Vertical=if script then require(script.Parent.VerticalControl) else require("./VerticalControl")
local PredictionEngine = {}
PredictionEngine.__index = PredictionEngine

local function aliases(self)
 self.history=self.prediction.history
 self.latency=self.prediction.latency
 self.settings=self.prediction.settings
end
function PredictionEngine.new(config)
 local normalized,message=Config.new(config)
 assert(normalized,message or "Configuración Cam Lock inválida")
 local legacy
 legacy,message=Config.toPredictionConfig(normalized)
 assert(legacy,message)
 local self=setmetatable({config=normalized,prediction=Prediction.new(legacy)},PredictionEngine)
 self.sync=self.prediction._sync
 -- Config is private; recompute settings on edits, not on each render.
 self.prediction._sync=function() end
 self.filter=MotionFilter.new(normalized);self.vertical=Vertical.new(normalized)
 aliases(self)
 return self
end
function PredictionEngine:observe(t,position,state)
 -- Validate raw sample before any optional filter state mutation.
 local latest=self.history:latest()
 if type(t)~="number" or t~=t or math.abs(t)==math.huge then return false,"INVALID_OBSERVATION_TIME" end
 if latest and t<=latest.t then return false,"NON_INCREASING_OBSERVATION_TIME" end
 local valid,ok=pcall(function() return position.Magnitude<math.huge and position.X==position.X and position.Y==position.Y and position.Z==position.Z end)
 if not valid or not ok then return false,"INVALID_OBSERVATION_POSITION" end
 if state~=nil and type(state)~="string" then return false,"INVALID_HUMANOID_STATE" end
 if self.config.MotionFilter~="Memory" and self.filter.time then
  local dt=t-self.filter.time;local displacement=(position-self.filter.raw).Magnitude
  local maximum=self.config.MaxObservedSpeed*dt
  if displacement>maximum and displacement<=maximum+self.config.TeleportSlack then return false,"OBSERVED_SPEED_LIMIT" end
 end
 local filtered=self.filter:observe(t,position,state)
 local accepted=self.prediction:observe(t,filtered,state)
 if accepted then self.vertical:observe(t,position,state) end
 if not accepted and self.config.MotionFilter~="Memory" then self.filter:reset() end
 aliases(self)
 return accepted,if accepted then nil else "MOTION_HISTORY_REJECTED"
end
function PredictionEngine:samplePing(rttSeconds,now)
 local accepted=self.prediction:samplePing(rttSeconds,now)
 aliases(self)
 return accepted
end
function PredictionEngine:predict(origin,now)
 local output=self.prediction:predict(origin,now)
 if output then
  self.vertical:apply(output,now)
  output.hitPart=self.config.HitPart
  output.predictionUnits="seconds"
  output.visibleX=self.config.PredictionX;output.visibleY=self.config.PredictionY
  output.calibration="SedwareLinearProvisional"
  output.requestedHorizontalSeconds=self.config.PredictionX*self.config.ReferenceHorizontalSeconds/self.config.ReferenceScale
  output.requestedVerticalSeconds=self.config.PredictionY*self.config.ReferenceVerticalSeconds/self.config.ReferenceScale
  output.calibrationClamped=output.requestedHorizontalSeconds>self.config.MaxPredictionX or output.requestedHorizontalSeconds<self.config.MinPredictionX or output.requestedVerticalSeconds>self.config.MaxPredictionY or output.requestedVerticalSeconds<self.config.MinPredictionY
  output.observationDelaySeconds=nil -- published clients do not expose sample capture time
  output.motionFilter=self.config.MotionFilter
 end
 return output
end
function PredictionEngine:reset()
 self.prediction:reset();self.filter:reset();self.vertical:reset()
 aliases(self)
end
function PredictionEngine:updateConfig(config)
 local normalized,message=Config.new(config)
 if not normalized then return false,message end
 local legacy
 legacy,message=Config.toPredictionConfig(normalized)
 if not legacy then return false,message end
 local filterChanged=normalized.MotionFilter~=self.config.MotionFilter
 local baseChanged=false
 for _,key in {"PredictionX","PredictionY","ReferenceScale","ReferenceHorizontalSeconds","ReferenceVerticalSeconds","AutoPrediction","PingReferences","MinPredictionX","MaxPredictionX","MinPredictionY","MaxPredictionY"} do
  if key~="PingReferences" and normalized[key]~=self.config[key] then baseChanged=true end
 end
 for i,p in normalized.PingReferences do local old=self.config.PingReferences[i];if not old or p.X~=old.X or p.Y~=old.Y or p.PingMs~=old.PingMs then baseChanged=true end end
 if #normalized.PingReferences~=#self.config.PingReferences then baseChanged=true end
 local hitPartChanged=normalized.HitPart~=self.config.HitPart
 self.config=normalized
 self.prediction.config=legacy
 self.sync(self.prediction)
 self.filter.config=normalized;self.vertical.config=normalized
 -- GUI edits must retain motion samples and accepted ping. Rebase auto slew
 -- so explicit prediction edits take effect on the next camera frame.
 if baseChanged then for _,policy in self.prediction.policies do
  policy.baseX=nil;policy.baseY=nil;policy.lastBaseTime=nil
 end end
 if hitPartChanged or filterChanged then
  self.filter:reset();self.vertical:reset()
  -- A different body part is a new position stream. Retain latency but reset
  -- the motion and output filters; never infer velocity across body parts.
  local retainedLatency=self.prediction.latency
  local retainedPing=self.prediction.pingAvailable
  self.prediction:reset()
  self.prediction.latency=retainedLatency
  self.prediction.pingAvailable=retainedPing
 end
 aliases(self)
 return true
end
return PredictionEngine
