--!nonstrict
-- Bounded kinematic lead; no assumed ballistic flight or server capture time.
local Vertical={};Vertical.__index=Vertical
local function vector(reference,x,y,z)
 local make=if Vector3 then Vector3.new else reference.new
 return make(x,y,z)
end
function Vertical.new(config) return setmetatable({config=config,phase="Grounded",velocityY=0},Vertical) end
function Vertical:reset()
 self.time=nil;self.position=nil;self.rawVelocity=nil;self.velocityY=0;self.phase="Grounded"
 self.landingUntil=nil;self.reversalAt=nil;self.previousHorizontal=nil
 self.jumping=nil;self.anomaly=false;self.anomalyReason=nil;self.rawVelocityY=nil
 self.jumpImpulse=false;self.landingTransition=false;self.hasMeasuredVelocity=false
end
function Vertical:observe(t,p,state)
 local c=self.config;state=state or "Running"
 local dt=self.time and t-self.time;local velocity=p*0
 local previousKnown=self.hasMeasuredVelocity==true
 local known=dt~=nil and dt>0 and dt<=c.StaleAfter and (p-self.position).Magnitude<=c.MaxObservedSpeed*dt+c.TeleportSlack
 if known then
  velocity=(p-self.position)/dt
 else self:reset();previousKnown=false end
 local jumping=state:find("Jumping",1,true)~=nil
 local airborne=jumping or state:find("Freefall",1,true)~=nil
 local landing=state:find("Landed",1,true)~=nil
 local wasAir=self.phase=="Rising" or self.phase=="Apex" or self.phase=="Falling"
 if (not airborne and wasAir) or landing then self.landingUntil=t+c.LandingHoldSeconds end
 local vy=math.clamp(velocity.Y,-c.MaxVerticalSpeed,c.MaxVerticalSpeed)
 self.anomaly=vy~=velocity.Y;self.anomalyReason=if self.anomaly then "VERTICAL_SPEED_CAP" else nil
 -- A genuine Jumping entry and a landing can contain physical impulses. A
 -- noisy Rising/Falling/Apex classification is not such an exception: the old
 -- same-phase check let alternating vertical spikes bypass every safeguard.
 self.jumpImpulse=jumping and self.jumping~=true
 self.landingTransition=(not airborne and wasAir) or landing
 if known and previousKnown and airborne and wasAir and not self.jumpImpulse then
  local limit=c.MaxVerticalVelocityChange*dt
  if math.abs(vy-self.velocityY)>limit then
   vy=self.velocityY+math.clamp(vy-self.velocityY,-limit,limit)
   self.anomaly=true;self.anomalyReason="VERTICAL_ACCELERATION_CAP"
  end
 end
 -- Small apex hysteresis prevents horizon chatter around the speed threshold;
 -- it is a classification margin, not another position/velocity EMA.
 -- Classify the observed motion, independently of the bounded lead velocity.
 -- An anomaly cap must not conceal an observed apex or turn in diagnostics.
 local observedY=math.clamp(velocity.Y,-c.MaxVerticalSpeed,c.MaxVerticalSpeed)
 local apex=math.abs(observedY)<=(if self.phase=="Apex" then c.ApexVelocity*1.5 else c.ApexVelocity)
 local phase=if airborne then (if apex then "Apex" elseif observedY>0 then "Rising" else "Falling")
  elseif self.landingUntil and t<self.landingUntil then "Landing" else "Grounded"
 if phase=="Landing" then vy=0 end
 local horizontal=vector(p,velocity.X,0,velocity.Z)
 if self.previousHorizontal and self.previousHorizontal.Magnitude>1 and horizontal.Magnitude>1
  and self.previousHorizontal:Dot(horizontal)/(self.previousHorizontal.Magnitude*horizontal.Magnitude)<c.ReversalDotThreshold then self.reversalAt=t end
 self.previousHorizontal=horizontal;self.time=t;self.position=p;self.rawVelocity=if known then velocity else nil
 self.rawVelocityY=if known then velocity.Y else nil;self.hasMeasuredVelocity=known
 self.velocityY=vy;self.phase=phase;self.jumping=jumping
end
function Vertical:apply(out,now)
 local c=self.config;local factor=1
 if c.ReversalDamping and self.reversalAt then
  factor=c.ReversalScale+(1-c.ReversalScale)*math.clamp((now-self.reversalAt)/c.ReversalWindow,0,1)
 end
 out.horizontalHorizonUsed=out.predictionX*factor;out.reversalScale=factor
 if factor<1 then
  local v=out.velocity;local h=out.horizontalHorizonUsed+out.ageSeconds
  for _,key in {"position","rawPosition","targetPosition","rawTargetPosition"} do
   local p=out[key];out[key]=vector(p,out.currentPosition.X+v.X*h,p.Y,out.currentPosition.Z+v.Z*h)
  end
 end
 out.movementPhase=self.phase;out.verticalAnomaly=self.anomaly==true;out.verticalHorizonUsed=out.predictionY
 out.verticalAnomalyReason=self.anomalyReason;out.verticalRawVelocity=self.rawVelocityY
 out.verticalRawVelocityKnown=self.hasMeasuredVelocity==true;out.verticalVelocityEstimate=self.velocityY
 out.verticalEstimatedVelocity=self.velocityY;out.verticalApexLeadLimited=false;out.verticalLeadSuppressed=false
 out.verticalJumpImpulse=self.jumpImpulse;out.verticalLandingTransition=self.landingTransition
 out.verticalVelocityUsed=out.velocity.Y;out.verticalLeadLimited=false
 if not c.VerticalControl or self.phase=="Grounded" then return out end
 local horizon=if self.phase=="Rising" then c.RisingHorizon elseif self.phase=="Falling" then c.FallingHorizon elseif self.phase=="Apex" then c.ApexHorizon else 0
 horizon=math.min(out.predictionY,horizon)
 local vy=if c.VelocityPrediction then self.velocityY else 0
 -- An innovation cap must not preserve an excessive rising lead when a
 -- smaller or reversed measured velocity says the target has already braked.
 -- Suppress that extrapolation while retaining the bounded estimate and raw
 -- anomaly for diagnostics; this is not another velocity/position filter.
 if self.anomaly and self.hasMeasuredVelocity and c.VelocityPrediction then
  local observed=self.rawVelocityY
  local safe=if vy*observed<=0 then 0 else math.sign(vy)*math.min(math.abs(vy),math.abs(observed))
  out.verticalLeadSuppressed=safe~=vy;vy=safe
  out.verticalApexLeadLimited=self.phase=="Apex" and out.verticalLeadSuppressed
 end
 local lead=math.clamp(vy*(horizon+out.ageSeconds),-c.MaxVerticalLead,c.MaxVerticalLead)
 out.verticalLeadLimited=math.abs(vy*(horizon+out.ageSeconds))>c.MaxVerticalLead
 out.verticalVelocityUsed=vy;out.verticalHorizonUsed=horizon;out.verticalTotalLeadSeconds=if math.abs(vy)>1e-8 then math.abs(lead/vy) else 0
 local y=out.currentPosition.Y+lead
 for _,key in {"position","rawPosition","targetPosition","rawTargetPosition"} do
  local p=out[key];out[key]=vector(p,p.X,y,p.Z)
 end
 return out
end
return Vertical
