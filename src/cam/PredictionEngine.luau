--!nonstrict
-- Preserve the existing bounded Memory Tracking, reversal/teleport recovery,
-- elapsed-time ping EMA and axis prediction. Camera interpolation is separate.
local Config = if script then require(script.Parent.Config) else require("./Config")
local Prediction = if script then require(script.Parent.Parent.pink.Prediction) else require("../pink/Prediction")
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
 aliases(self)
 return self
end
function PredictionEngine:observe(t,position,state)
 local accepted=self.prediction:observe(t,position,state)
 aliases(self)
 return accepted
end
function PredictionEngine:samplePing(rttSeconds,now)
 local accepted=self.prediction:samplePing(rttSeconds,now)
 aliases(self)
 return accepted
end
function PredictionEngine:predict(origin,now)
 local output=self.prediction:predict(origin,now)
 if output then
  output.camPrediction=self.config.CamPrediction
  output.camGain=self.config.CamPrediction/Config.referenceCamPrediction
  output.hitPart=self.config.HitPart
  output.predictionUnits="seconds"
  output.camPredictionUnits="dimensionless"
 end
 return output
end
function PredictionEngine:reset()
 self.prediction:reset()
 aliases(self)
end
function PredictionEngine:updateConfig(config)
 local normalized,message=Config.new(config)
 if not normalized then return false,message end
 local legacy
 legacy,message=Config.toPredictionConfig(normalized)
 if not legacy then return false,message end
 local hitPartChanged=normalized.HitPart~=self.config.HitPart
 self.config=normalized
 self.prediction.config=legacy
 self.prediction:_sync()
 -- GUI edits must retain motion samples and accepted ping. Rebase auto slew
 -- so explicit prediction edits take effect on the next camera frame.
 for _,policy in self.prediction.policies do
  policy.baseX=nil;policy.baseY=nil;policy.lastBaseTime=nil
 end
 if hitPartChanged then
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
