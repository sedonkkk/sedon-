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
end
function Vertical:observe(t,p,state)
 local c=self.config;state=state or "Running"
 local dt=self.time and t-self.time;local velocity=p*0
 if dt and dt>0 and dt<=c.StaleAfter and (p-self.position).Magnitude<=c.MaxObservedSpeed*dt+c.TeleportSlack then
  velocity=(p-self.position)/dt
 else self:reset() end
 local airborne=state:find("Jumping",1,true)~=nil or state:find("Freefall",1,true)~=nil
 local landing=state:find("Landed",1,true)~=nil
 local wasAir=self.phase=="Rising" or self.phase=="Apex" or self.phase=="Falling"
 if (not airborne and wasAir) or landing then self.landingUntil=t+c.LandingHoldSeconds end
 local phase=if airborne then (if math.abs(velocity.Y)<=c.ApexVelocity then "Apex" elseif velocity.Y>0 then "Rising" else "Falling")
  elseif self.landingUntil and t<self.landingUntil then "Landing" else "Grounded"
 local vy=math.clamp(velocity.Y,-c.MaxVerticalSpeed,c.MaxVerticalSpeed)
 self.anomaly=false
 if dt and airborne and self.phase==phase and self.rawVelocity then
  local limit=c.MaxVerticalVelocityChange*dt
  if math.abs(vy-self.velocityY)>limit then vy=self.velocityY+math.clamp(vy-self.velocityY,-limit,limit);self.anomaly=true end
 end
 if phase=="Landing" then vy=0 end
 local horizontal=vector(p,velocity.X,0,velocity.Z)
 if self.previousHorizontal and self.previousHorizontal.Magnitude>1 and horizontal.Magnitude>1
  and self.previousHorizontal:Dot(horizontal)/(self.previousHorizontal.Magnitude*horizontal.Magnitude)<c.ReversalDotThreshold then self.reversalAt=t end
 self.previousHorizontal=horizontal;self.time=t;self.position=p;self.rawVelocity=velocity
 self.velocityY=vy;self.phase=phase
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
 out.verticalVelocityUsed=out.velocity.Y;out.verticalLeadLimited=false
 if not c.VerticalControl or self.phase=="Grounded" then return out end
 local horizon=if self.phase=="Rising" then c.RisingHorizon elseif self.phase=="Falling" then c.FallingHorizon elseif self.phase=="Apex" then c.ApexHorizon else 0
 horizon=math.min(out.predictionY,horizon)
 local vy=if c.VelocityPrediction then self.velocityY else 0
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
