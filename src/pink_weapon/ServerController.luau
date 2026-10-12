--!nonstrict
-- Authoritative controller for the OWNED Studio Tool. No game-specific hooks.
-- All Roblox accesses live in the injected native wrapper, so this exact
-- controller can also be exercised by deterministic tests.
local WeaponSettings = if script then require(script.Parent.WeaponSettings) else require("./WeaponSettings")
local WeaponProfiles = if script then require(script.Parent.WeaponProfiles) else require("./WeaponProfiles")
local Spread = if script then require(script.Parent.Spread) else require("./Spread")
local ServerController = {}
ServerController.__index = ServerController
local fields = {
	sessionId = true, shotId = true, ticketId = true, mode = true,
	capturedAt = true, origin = true, aimpoint = true, targetUserId = true,
	targetCharacter = true, partName = true, sampleTime = true, weaponId = true,
}
local function finite(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end
local function integer(value)
	return finite(value) and value >= 1 and value <= 1e12 and value % 1 == 0
end
local function finiteVector(value)
	-- Native wiring supplies an isVector predicate requiring real Vector3.
	-- Table vectors are allowed only for the isolated CLI arithmetic adapter.
	if typeof(value) ~= "Vector3" and type(value) ~= "table" then return false end
	return finite(value.X) and finite(value.Y) and finite(value.Z)
end
local function health(humanoid)
	return humanoid and finite(humanoid.Health) and humanoid.Health > 0
end
local function magnitude(vector)
	return math.sqrt(vector.X * vector.X + vector.Y * vector.Y + vector.Z * vector.Z)
end
local function response(request, reason)
	local result = { accepted = false, reason = reason, hit = false, selectedTargetHit = false, damageApplied = 0 }
	if type(request) == "table" and getmetatable(request) == nil then
		if type(request.sessionId) == "string" and #request.sessionId <= 64 then result.sessionId = request.sessionId end
		if integer(request.shotId) then result.shotId = request.shotId end
		if integer(request.ticketId) then result.ticketId = request.ticketId end
		if request.mode == "Normal" or request.mode == "Locked" then result.mode = request.mode end
		if WeaponProfiles.validId(request.weaponId) then result.weaponId=request.weaponId end
	end
	return result
end

function ServerController.new(options)
	assert(type(options) == "table", "Server controller options required")
	for _, name in { "clock", "getEquippedWeapon", "getTarget", "raycast", "describeHit", "applyDamage" } do
		assert(type(options[name]) == "function", name .. " callback required")
	end
	assert(options.isVector == nil or type(options.isVector) == "function", "isVector must be a function")
	local profiles
	if options.profiles then
		profiles={}
		for id,profile in options.profiles do profiles[id]=WeaponProfiles.normalize(id,profile) end
		for _,profile in profiles do
			if profile.Kind=="Projectile" then
				assert(type(options.launchProjectile)=="function" and type(options.onResult)=="function","Native projectile launch/result callbacks required")
			end
		end
	end
	return setmetatable({ settings = WeaponSettings.new(options.settings), callbacks = options, profiles=profiles,
		states = {}, jobs={},nextJob=0,jobCount=0,destroyed = false }, ServerController)
end

function ServerController:_result(context,entries,reason,endPosition)
	local callbacks,request,profile=context.callbacks,context.request,context.profile
	local isVector=callbacks.isVector or finiteVector
	local referenceTime=callbacks.clock()
	assert(finite(referenceTime),"Reference clock unavailable after collision query")
	local actualPosition
	if context.target then
		local ok,value=pcall(function() return context.target.part.Position end)
		if ok and isVector(value) and finiteVector(value) then actualPosition=value end
	end
	local result={sessionId=request.sessionId,shotId=request.shotId,ticketId=request.ticketId,weaponId=request.weaponId,
		accepted=true,mode=request.mode,referenceTime=referenceTime,serverTime=referenceTime,
		hit=false,selectedTargetHit=false,damageApplied=0,origin=context.origin,
		impactPosition=endPosition,physicsKind=profile.Kind,pelletCount=#entries,pelletHits=0,pellets={},reason=reason or "miss"}
	for _,entry in entries do
		local pellet={hit=entry.result~=nil,impactPosition=entry.endPosition,selectedTargetHit=false,damageApplied=0}
		if entry.result then
			local description=callbacks.describeHit(entry.result,context.player)
			assert(type(description)=="table" and isVector(description.position) and finiteVector(description.position),"Invalid actual impact description")
			pellet.impactPosition=description.position;pellet.hitName=description.name
			pellet.selectedTargetHit=context.target~=nil and description.character==context.target.character
			if not result.hit then result.impactPosition=description.position;result.hitName=description.name;result.hitPlayerUserId=description.playerUserId end
			result.hit=true;result.pelletHits+=1
			if pellet.selectedTargetHit then result.selectedTargetHit=true end
			if description.humanoid and description.character~=context.weapon.character and health(description.humanoid) then
				local damage=callbacks.applyDamage(description.humanoid,profile.Damage)
				assert(type(damage)=="table" and finite(damage.before) and finite(damage.after),"Damage callback must return measured health")
				pellet.damageApplied=math.max(0,damage.before-damage.after)
				result.damageApplied+=pellet.damageApplied
			end
		end
		table.insert(result.pellets,pellet)
	end
	if result.selectedTargetHit then result.reason="selected-target-hit" elseif result.hit then result.reason="surface-impact" end
	if context.target then
		result.targetUserId=context.target.player.UserId;result.character=context.target.character;result.actualPosition=actualPosition
	end
	return result
end

function ServerController:_launch(context,direction)
	if self.jobCount>=self.settings.MaxProjectiles then return response(context.request,"projectile-capacity") end
	local count=0;for _,job in self.jobs do if job.context.player==context.player then count+=1 end end
	if count>=self.settings.MaxProjectilesPerPlayer then return response(context.request,"player-projectile-capacity") end
	self.nextJob+=1
	local id=self.nextJob
	local job={context=context,done=false,published=false}
	self.jobs[id]=job;self.jobCount+=1
	local function complete(hit,reason,position)
		if job.done or self.destroyed then return end
		job.done=true;self.jobs[id]=nil;self.jobCount-=1
		local ok,result=pcall(function()
			local isVector=context.callbacks.isVector or finiteVector
			if not isVector(position) or not finiteVector(position) then return response(context.request,"invalid-projectile-reference") end
			if reason~="impact" and reason~="range-expired" and reason~="lifetime-expired" then
				return response(context.request,"projectile-error: "..tostring(reason))
			end
			return self:_result(context,{{result=hit,endPosition=position}},reason,position)
		end)
		if not ok then local detail=result;result=response(context.request,"server-error");result.error=tostring(detail) end
		if job.published then context.callbacks.onResult(context.player,result) else job.result=result end
	end
	local launched,cancel=pcall(context.callbacks.launchProjectile,context.origin,direction*context.profile.Speed,
		context.profile,context.weapon.character,complete)
	if not launched or type(cancel)~="function" then
		if not job.done then self.jobs[id]=nil;self.jobCount-=1;job.done=true end
		error("Physical projectile launch failed: "..tostring(cancel))
	end
	job.cancel=cancel
	if job.result then return job.result end
	job.published=true
	return {sessionId=context.request.sessionId,shotId=context.request.shotId,ticketId=context.request.ticketId,
		weaponId=context.request.weaponId,accepted=true,pending=true,stage="Launched",mode=context.request.mode}
end

function ServerController:_process(player, request)
	local rejected = response(request, "invalid-request")
	if self.destroyed then rejected.reason = "destroyed"; return rejected end
	if type(request) ~= "table" or getmetatable(request) ~= nil then return rejected end
	for key in request do if not fields[key] then rejected.reason = "unknown-field"; return rejected end end
	if type(request.sessionId) ~= "string" or #request.sessionId < 1 or #request.sessionId > 64 or not integer(request.shotId) then return rejected end
	if request.mode ~= "Normal" and request.mode ~= "Locked" then rejected.reason = "invalid-mode"; return rejected end
	if request.ticketId ~= nil and not integer(request.ticketId) then rejected.reason = "invalid-ticket"; return rejected end
	local profile
	if self.profiles then
		profile=self.profiles[request.weaponId]
		if not WeaponProfiles.validId(request.weaponId) or not profile then rejected.reason="unsupported-weapon";return rejected end
	elseif request.weaponId~=nil then rejected.reason="unsupported-weapon";return rejected end
	local settings, callbacks = self.settings, self.callbacks
	local now = callbacks.clock()
	if not finite(now) then rejected.reason = "invalid-server-clock"; return rejected end
	if not finite(request.capturedAt) or request.capturedAt > now + settings.ClockTolerance
		or now - request.capturedAt > settings.RequestMaxAge then rejected.reason = "stale-request"; return rejected end
	local isVector = callbacks.isVector or finiteVector
	if not isVector(request.origin) or not finiteVector(request.origin) or not isVector(request.aimpoint) or not finiteVector(request.aimpoint) then
		rejected.reason = "invalid-vectors"; return rejected
	end
	if not player or not finite(player.UserId) or player.UserId % 1 ~= 0 then rejected.reason = "invalid-player"; return rejected end
	if request.mode == "Locked" then
		if not finite(request.targetUserId) or request.targetUserId % 1 ~= 0 or request.targetUserId == player.UserId
			or not settings.AllowedParts[request.partName] or request.targetCharacter == nil then rejected.reason = "invalid-target"; return rejected end
		if not finite(request.sampleTime) or request.sampleTime > now + settings.ClockTolerance
			or now - request.sampleTime > settings.RequestMaxAge then rejected.reason = "stale-sample"; return rejected end
	elseif request.targetUserId ~= nil or request.targetCharacter ~= nil or request.partName ~= nil
		or request.sampleTime ~= nil or request.ticketId ~= nil then
		rejected.reason = "unexpected-target-fields"; return rejected
	end
	local state = self.states[player]
	if not state then
		state = { nextFire = -math.huge, sessions = {}, order = {} }
		self.states[player] = state
	end
	local prior = state.sessions[request.sessionId]
	if prior and request.shotId <= prior then rejected.reason = "duplicate-shot"; return rejected end
	if not prior then
		table.insert(state.order, request.sessionId)
		if #state.order > settings.MaxSessionsPerPlayer then state.sessions[table.remove(state.order, 1)] = nil end
	end
	state.sessions[request.sessionId] = request.shotId
	if now < state.nextFire then rejected.reason = "cooldown"; return rejected end
	local weapon = callbacks.getEquippedWeapon(player)
	if type(weapon) ~= "table" or not weapon.tool or not weapon.character or not health(weapon.humanoid)
		or not isVector(weapon.origin) or not finiteVector(weapon.origin) then rejected.reason = "weapon-not-equipped"; return rejected end
	local authoritativeOrigin = weapon.origin
	if profile and weapon.profileId~=request.weaponId then rejected.reason="weapon-profile-mismatch";return rejected end
	profile=profile or {Kind="Hitscan",Range=settings.Range,Cooldown=settings.Cooldown,Damage=settings.Damage,Pellets=1,SpreadDegrees=0}
	if magnitude(request.origin - authoritativeOrigin) > settings.MaxOriginDistance then rejected.reason = "invalid-origin"; return rejected end
	local delta = request.aimpoint - authoritativeOrigin
	local distance = magnitude(delta)
	if not finite(distance) or distance <= 0.001 then rejected.reason = "degenerate-aimpoint"; return rejected end
	if distance > settings.MaxAimDistance then rejected.reason = "aimpoint-out-of-range"; return rejected end
	local target
	if request.mode == "Locked" then
		target = callbacks.getTarget(request.targetUserId, request.partName, request.targetCharacter)
		if type(target) ~= "table" or not target.player or target.player.UserId ~= request.targetUserId
			or target.character ~= request.targetCharacter or not target.part or not health(target.humanoid)
			or not isVector(target.position) or not finiteVector(target.position) then rejected.reason = "target-lost"; return rejected end
		if magnitude(target.position - authoritativeOrigin) > profile.Range then rejected.reason = "target-out-of-range"; return rejected end
	end
	-- Rate is consumed before any raycast/damage callback, including a failed
	-- callback. Retrying cannot cause duplicated physical damage.
	state.nextFire = now + profile.Cooldown
	local directions=Spread.directions(delta,profile.Pellets,profile.SpreadDegrees,callbacks.random,callbacks.makeVector)
	local context={callbacks=callbacks,player=player,request=request,profile=profile,target=target,weapon=weapon,origin=authoritativeOrigin}
	if profile.Kind=="Projectile" then return self:_launch(context,directions[1]) end
	local entries={}
	for _,direction in directions do
		local rayDirection=direction*profile.Range
		table.insert(entries,{result=callbacks.raycast(authoritativeOrigin,rayDirection,weapon.character,profile),endPosition=authoritativeOrigin+rayDirection})
	end
	return self:_result(context,entries,nil,entries[1].endPosition)
end

function ServerController:process(player, request)
	local ok, result = pcall(self._process, self, player, request)
	if ok then return result end
	local rejected = response(request, "server-error")
	local stringifyOK, detail = pcall(tostring, result)
	rejected.error = if stringifyOK then detail else "Server callback failed"
	return rejected
end
function ServerController:removePlayer(player)
	self.states[player] = nil
	for id,job in self.jobs do
		if job.context.player==player then
			job.done=true;self.jobs[id]=nil;self.jobCount-=1
			if job.cancel then pcall(job.cancel) end
		end
	end
end
function ServerController:destroy()
	if self.destroyed then return end
	self.destroyed = true
	for _,job in self.jobs do job.done=true;if job.cancel then pcall(job.cancel) end end
	table.clear(self.jobs);self.jobCount=0
	table.clear(self.states)
	self.callbacks = nil
end
return ServerController
