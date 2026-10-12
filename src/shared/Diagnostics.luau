--!nonstrict
-- Bounded records. Shot misses and prediction error have different denominators.
local Diagnostics={}
Diagnostics.__index=Diagnostics
function Diagnostics.new(capacity)
 return setmetatable({capacity=math.max(1,capacity or 256),shots={},predictions={}},Diagnostics)
end
local function append(list,value,capacity)
 table.insert(list,value)
 if #list>capacity then table.remove(list,1) end
end
function Diagnostics:recordShot(record)
 if type(record)~="table" or type(record.hit)~="boolean" or record.accepted==false then return false end
 append(self.shots,table.clone(record),self.capacity);return true
end
function Diagnostics:recordPrediction(record)
 local e=record and record.errorStuds
 if type(e)~="number" or e~=e or e<0 or e==math.huge then return false end
 append(self.predictions,table.clone(record),self.capacity);return true
end
function Diagnostics:clear() table.clear(self.shots);table.clear(self.predictions) end
function Diagnostics:summary()
 local hits,missSum,missCount=0,0,0
 local byWeapon={}
 for _, shot in self.shots do
  local hit=if type(shot.intendedHit)=="boolean" then shot.intendedHit else shot.hit
  hits+=if hit then 1 else 0
  local key=shot.weapon or "unknown"
  local bucket=byWeapon[key] or {shots=0,hits=0}
  byWeapon[key]=bucket;bucket.shots+=1;bucket.hits+=if hit then 1 else 0
  local miss=shot.missDistanceStuds
  if type(miss)=="number" and miss==miss and miss>=0 and miss<math.huge then missSum+=miss;missCount+=1 end
 end
 local sum=0
 for _, p in self.predictions do
  sum+=p.errorStuds*p.errorStuds
  local key=p.weapon or "unknown"
  local bucket=byWeapon[key] or {shots=0,hits=0}
  byWeapon[key]=bucket
  bucket.predictionCount=(bucket.predictionCount or 0)+1
  bucket.predictionSquareSum=(bucket.predictionSquareSum or 0)+p.errorStuds*p.errorStuds
 end
 local count=#self.predictions
 for _,b in byWeapon do
  b.hitRate=if b.shots>0 then b.hits/b.shots else 0
  b.predictionRMSEStuds=if b.predictionCount then math.sqrt(b.predictionSquareSum/b.predictionCount) else nil
 end
 return {shots=#self.shots,hits=hits,hitRate=if #self.shots>0 then hits/#self.shots else 0,
  predictionCount=count,predictionRMSEStuds=if count>0 then math.sqrt(sum/count) else nil,
  missDistanceMeanStuds=if missCount>0 then missSum/missCount else nil,byWeapon=byWeapon}
end
return Diagnostics
