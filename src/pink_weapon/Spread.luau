--!nonstrict
-- Server-selected uniform cone spread. The aim point remains the cone axis;
-- neither a target nor prediction proximity is used to decide a pellet hit.
local Spread = {}
function Spread.directions(direction,count,degrees,sample,makeVector)
 assert(type(count)=="number" and count%1==0 and count>=1 and count<=32,"Invalid pellet count")
 assert(type(degrees)=="number" and degrees==degrees and degrees>=0 and degrees<=20,"Invalid spread angle")
 local length=direction.Magnitude
 assert(length>0 and length<math.huge,"Invalid spread direction")
 local forward=direction/length
 if degrees==0 then
  local results={}
  for _=1,count do table.insert(results,forward) end
  return results
 end
 assert(type(sample)=="function" and type(makeVector)=="function","Server random/vector callbacks required for spread")
 local ax,ay,az=if math.abs(forward.Y)<0.99 then 0 else 1,if math.abs(forward.Y)<0.99 then 1 else 0,0
 local right=makeVector(forward.Y*az-forward.Z*ay,forward.Z*ax-forward.X*az,forward.X*ay-forward.Y*ax)
 right=right/right.Magnitude
 local up=makeVector(right.Y*forward.Z-right.Z*forward.Y,right.Z*forward.X-right.X*forward.Z,right.X*forward.Y-right.Y*forward.X)
 local results={}
 local minimumCos=math.cos(math.rad(degrees))
 for _=1,count do
  local u,v=sample(),sample()
  assert(type(u)=="number" and type(v)=="number" and u>=0 and u<=1 and v>=0 and v<=1,"Invalid server random sample")
  local cosine=1-u*(1-minimumCos)
  local sine=math.sqrt(math.max(0,1-cosine*cosine))
  local angle=2*math.pi*v
  table.insert(results,forward*cosine+(right*math.cos(angle)+up*math.sin(angle))*sine)
 end
 return results
end
return Spread
