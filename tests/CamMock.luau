--!nonstrict
-- Composition over PinkMock keeps the previous variants' doubles unchanged.
-- These doubles exercise the ACTUAL Cam bundle's native API calls and event
-- ownership. Supplied projection coordinates, orientation interpolation and
-- render priority ordering are deterministic fixtures, not a Roblox renderer.
local PinkMock = require("./PinkMock")
local CamMock = {}

function CamMock.new()
	local mock = PinkMock.new()
	local env, V = mock.env, mock.env.Vector3
	local Frame, frameMeta = {}, {}
	local function safeUnit(value, fallback)
		return if value.Magnitude > 1e-10 then value.Unit else fallback
	end
	local function frame(position, look, up)
		look = safeUnit(look or V.new(0, 0, -1), V.new(0, 0, -1))
		up = up or V.yAxis
		local right = look:Cross(up)
		if right.Magnitude < 1e-8 then right = look:Cross(V.xAxis) end
		right = safeUnit(right, V.xAxis)
		return setmetatable({Position = position, LookVector = look,
			RightVector = right, UpVector = right:Cross(look), _mockType = "CFrame"}, frameMeta)
	end
	local function quaternion(value)
		-- Columns are right, up, backwards, as in Roblox CFrame components.
		local r, u, b = value.RightVector, value.UpVector, -value.LookVector
		local trace = r.X + u.Y + b.Z
		local x, y, z, w
		if trace > 0 then
			local s = math.sqrt(trace + 1) * 2
			w, x, y, z = s / 4, (u.Z - b.Y) / s, (b.X - r.Z) / s, (r.Y - u.X) / s
		elseif r.X > u.Y and r.X > b.Z then
			local s = math.sqrt(1 + r.X - u.Y - b.Z) * 2
			w, x, y, z = (u.Z - b.Y) / s, s / 4, (u.X + r.Y) / s, (b.X + r.Z) / s
		elseif u.Y > b.Z then
			local s = math.sqrt(1 + u.Y - r.X - b.Z) * 2
			w, x, y, z = (b.X - r.Z) / s, (u.X + r.Y) / s, s / 4, (b.Y + u.Z) / s
		else
			local s = math.sqrt(1 + b.Z - r.X - u.Y) * 2
			w, x, y, z = (r.Y - u.X) / s, (b.X + r.Z) / s, (b.Y + u.Z) / s, s / 4
		end
		return {x, y, z, w}
	end
	local function fromQuaternion(position, q)
		local x, y, z, w = q[1], q[2], q[3], q[4]
		local length = math.sqrt(x*x + y*y + z*z + w*w)
		x, y, z, w = x/length, y/length, z/length, w/length
		local up = V.new(2*(x*y-z*w), 1-2*(x*x+z*z), 2*(y*z+x*w))
		local back = V.new(2*(x*z+y*w), 2*(y*z-x*w), 1-2*(x*x+y*y))
		return frame(position, -back, up)
	end
	function Frame.lookAt(position, target, up)
		local direction = target-position
		if up and direction.Magnitude > 1e-10 then
			assert(direction.Unit:Cross(up.Unit).Magnitude > 1e-8, "mock lookAt received parallel up vector")
		end
		return frame(position, direction, up)
	end
	function Frame.new(x, y, z)
		if type(x) == "table" then
			return if type(y) == "table" then Frame.lookAt(x, y) else frame(x)
		end
		return frame(V.new(x or 0, y or 0, z or 0))
	end
	function Frame.fromMatrix(position, right, up, back)
		back = back or right:Cross(up)
		return frame(position, -back, up)
	end
	function Frame:Lerp(other, alpha)
		local a, b = quaternion(self), quaternion(other)
		local dot = 0
		for index = 1, 4 do dot += a[index] * b[index] end
		if dot < 0 then
			dot = -dot
			for index = 1, 4 do b[index] = -b[index] end
		end
		local left, right = 1-alpha, alpha
		if dot < 0.9995 then
			local angle = math.acos(math.clamp(dot, -1, 1))
			left, right = math.sin((1-alpha)*angle)/math.sin(angle), math.sin(alpha*angle)/math.sin(angle)
		end
		local result = {}
		for index = 1, 4 do result[index] = a[index]*left + b[index]*right end
		return fromQuaternion(self.Position:Lerp(other.Position, alpha), result)
	end
	function Frame:VectorToWorldSpace(value)
		return self.RightVector*value.X + self.UpVector*value.Y - self.LookVector*value.Z
	end
	function Frame:PointToWorldSpace(value) return self.Position + self:VectorToWorldSpace(value) end
	function Frame:GetComponents()
		local p, r, u, b = self.Position, self.RightVector, self.UpVector, -self.LookVector
		return p.X, p.Y, p.Z, r.X, u.X, b.X, r.Y, u.Y, b.Y, r.Z, u.Z, b.Z
	end
	frameMeta.__index = function(value, key)
		if key == "Rotation" then return frame(V.zero, value.LookVector, value.UpVector) end
		if key == "p" then return value.Position end
		return Frame[key]
	end
	frameMeta.__add = function(value, offset) return frame(value.Position+offset, value.LookVector, value.UpVector) end
	frameMeta.__sub = function(value, offset) return frame(value.Position-offset, value.LookVector, value.UpVector) end
	frameMeta.__mul = function(a, b)
		if b._mockType == "CFrame" then
			return frame(a:PointToWorldSpace(b.Position), a:VectorToWorldSpace(b.LookVector), a:VectorToWorldSpace(b.UpVector))
		end
		return a:PointToWorldSpace(b)
	end
	env.CFrame = Frame
	env.SEDWARE_CAM_NO_AUTOSTART = true
	env.CAM_LOCK_NO_AUTOSTART = true
	env.Enum.RenderPriority.Camera.Value = 200
	local originalTypeof = env.typeof
	env.typeof = function(value)
		return if type(value) == "table" and value._mockType == "CFrame" then "CFrame" else originalTypeof(value)
	end

	mock.cameraWriteRecords, mock.renderOrder, mock.defaultCameraFrames = {}, {}, {}
	local function prepareCamera(camera, position)
		local originalMeta = getmetatable(camera)
		local wrapped = table.clone(originalMeta)
		wrapped.__newindex = function(node, key, value)
			if key == "CFrame" or key == "Focus" or key == "CameraType" or key == "CameraSubject" then
				table.insert(mock.cameraWriteRecords, {camera = node, property = key, value = value, time = mock:getTime()})
			end
			originalMeta.__newindex(node, key, value)
		end
		setmetatable(camera, wrapped)
		camera._props.CFrame = Frame.new(position or V.new(0, 2, 20))
		camera._props.Focus = Frame.new(V.new(0, 2, 0))
		camera._props.CameraType = env.Enum.CameraType.Custom
		camera._props.ViewportSize = env.Vector2.new(1280, 720)
		camera._props.CameraSubject = mock.services.Players.LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
		mock.defaultCameraFrames[camera] = {CFrame = camera.CFrame, Focus = camera.Focus}
		function camera:WorldToViewportPoint(positionToProject)
			mock.counters.projections += 1
			if self.Projection then return self.Projection(positionToProject) end
			local point = V.new(self.ViewportSize.X/2+positionToProject.X,
				self.ViewportSize.Y/2-positionToProject.Y, self.CFrame.Position.Z-positionToProject.Z)
			return point, point.X >= 0 and point.X <= self.ViewportSize.X and point.Y >= 0 and point.Y <= self.ViewportSize.Y and point.Z > 0
		end
		return camera
	end
	prepareCamera(mock.camera)
	function mock:newCamera(position)
		return prepareCamera(env.Instance.new("Camera"), position)
	end
	function mock:setDefaultCamera(camera, cframe, focus)
		camera = camera or self.world.CurrentCamera
		self.defaultCameraFrames[camera] = {CFrame = cframe, Focus = focus or Frame.new(cframe.Position+cframe.LookVector*20)}
	end
	function mock:setCameraDistance(distance)
		self.camera._props.CFrame = Frame.new(0, 2, distance)
		self.camera._props.Focus = Frame.new(0, 2, 0)
		self:setDefaultCamera(self.camera, self.camera.CFrame, self.camera.Focus)
	end
	function mock:cameraWritesFor(camera, property)
		local count = 0
		for _, entry in ipairs(self.cameraWriteRecords) do
			if entry.camera == camera and (not property or entry.property == property) then count += 1 end
		end
		return count
	end
	local baseReset = mock.resetCounters
	function mock:resetCounters()
		baseReset(self)
		table.clear(self.cameraWriteRecords)
		table.clear(self.renderOrder)
	end

	local run = mock.services.RunService
	mock.renderBindings = {}
	function run:BindToRenderStep(name, priority, callback)
		assert(type(name) == "string" and type(priority) == "number" and type(callback) == "function", "invalid render binding")
		mock.renderBindings[name] = {name = name, priority = priority, callback = callback}
	end
	function run:UnbindFromRenderStep(name) mock.renderBindings[name] = nil end
	function mock:countRenderBindings()
		local count = 0
		for _ in pairs(self.renderBindings) do count += 1 end
		return count
	end
	local originalFire = run.RenderStepped.Fire
	function run.RenderStepped:Fire(dt)
		local ordered = {}
		for _, binding in pairs(mock.renderBindings) do table.insert(ordered, binding) end
		table.sort(ordered, function(a, b)
			return if a.priority == b.priority then a.name < b.name else a.priority < b.priority
		end)
		local reset = false
		local function defaultCameraStep()
			reset = true
			table.insert(mock.renderOrder, {name = "RobloxDefaultCamera", priority = 200})
			local camera = mock.world.CurrentCamera
			local defaults = camera and mock.defaultCameraFrames[camera]
			if defaults then
				-- Engine camera writes are fixture inputs; only script writes count.
				camera._props.CFrame, camera._props.Focus = defaults.CFrame, defaults.Focus
			end
		end
		for _, binding in ipairs(ordered) do
			if not reset and binding.priority > 200 then defaultCameraStep() end
			if mock.renderBindings[binding.name] == binding then
				table.insert(mock.renderOrder, {name = binding.name, priority = binding.priority})
				binding.callback(dt)
			end
		end
		if not reset then defaultCameraStep() end
		originalFire(self, dt)
	end

	local rigs = {}
	local function addTorso(target, rig)
		rigs[target] = rig or "R15"
		local root = target.Character:FindFirstChild("HumanoidRootPart")
		local torso = env.Instance.new("Part")
		torso.Name = if rigs[target] == "R6" then "Torso" else "UpperTorso"
		torso.Position = root.Position + V.new(0, 1, 0)
		torso.Parent = target.Character
		target.Character:FindFirstChildOfClass("Humanoid").RigType = env.Enum.HumanoidRigType[rigs[target]]
		return torso
	end
	addTorso(mock.services.Players.LocalPlayer, "R15")
	local baseAdd, baseMove, baseRespawn = mock.addPlayer, mock.move, mock.respawn
	function mock:addPlayer(name, position, rig)
		local event = self.services.Players.PlayerAdded
		local original = event.Fire
		event.Fire = function() end
		local target = baseAdd(self, name, position)
		event.Fire = original
		addTorso(target, rig)
		event:Fire(target)
		return target
	end
	function mock:move(target, position, state)
		baseMove(self, target, position, state)
		local torso = target.Character:FindFirstChild("UpperTorso") or target.Character:FindFirstChild("Torso")
		if torso then torso.Position = position+V.new(0, 1, 0) end
	end
	function mock:respawn(target, position)
		local event = target.CharacterAdded
		local original = event.Fire
		event.Fire = function() end
		local character = baseRespawn(self, target, position)
		event.Fire = original
		addTorso(target, rigs[target])
		event:Fire(character)
		return character
	end
	function mock:setVelocity(target, velocity)
		for _, child in ipairs(target.Character:GetChildren()) do
			if child:IsA("BasePart") then child.AssemblyLinearVelocity = velocity end
		end
	end
	local blockedTargets = {}
	function mock:setOccluded(target, blocked) blockedTargets[target] = blocked == true end
	function mock.world:Raycast(origin, direction, _params)
		mock.counters.raycasts += 1
		local endpoint = origin+direction
		for target, blocked in pairs(blockedTargets) do
			if blocked and target.Character then
				for _, part in ipairs(target.Character:GetChildren()) do
					if part:IsA("BasePart") and (part.Position-endpoint).Magnitude < 0.01 then
						return {Distance=direction.Magnitude/2,Position=origin+direction/2,Instance=mock.world}
					end
				end
			end
		end
		return nil
	end
	mock:resetCounters()
	return mock
end

return CamMock
