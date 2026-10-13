--!nonstrict
-- Actual SedwareCamLock.lua bundle with native API/event doubles. This verifies
-- callbacks, prediction/camera writes, render ordering and lifecycle ownership;
-- it does not claim Roblox rendering, physics or third-party compatibility.
return function(reloadBundle)
	local Mock = require("./CamV2Mock")
	local tests, assertions, failures = 0, 0, 0
	local function check(condition, message)
		assertions += 1
		assert(condition, message or ("assertion failed at line " .. tostring(debug.info(2, "l"))))
	end
	local function near(actual, expected, tolerance)
		check(type(actual) == "number" and actual == actual and math.abs(actual-expected) <= (tolerance or 1e-8),
			"expected " .. tostring(expected) .. ", got " .. tostring(actual))
	end
	local function vectorNear(actual, expected, tolerance)
		check(actual ~= nil and expected ~= nil)
		near(actual.X, expected.X, tolerance); near(actual.Y, expected.Y, tolerance); near(actual.Z, expected.Z, tolerance)
	end
	local function size(map)
		local count = 0
		for _ in pairs(map) do count += 1 end
		return count
	end
	local function test(name, body)
		tests += 1
		local mock = Mock.new()
		local sessions = {}
		local function create(config, api)
			api = api or reloadBundle(mock.env)
			local current = api.init(config)
			check(current ~= nil and not current.destroyed, "session initialization failed")
			table.insert(sessions, current)
			return current, api
		end
		local ok, problem = pcall(body, mock, create)
		if not ok then failures += 1; print("FAIL CAM GUI " .. name .. ": " .. tostring(problem)) end
		for _, current in ipairs(sessions) do current:destroy() end
		local cleaned = mock:countConnections() == 0 and mock:countRenderBindings() == 0
		if not cleaned then
			failures += 1
			print("FAIL CAM GUI cleanup " .. name .. ": live connections or render binding")
		end
	end
	local function edit(session, field, value)
		local control = session.ui.controls[field]
		check(control ~= nil and control:IsA("TextBox"))
		control.Text = tostring(value)
		control.FocusLost:Fire(true)
	end
	local function enable(session) session.ui.controls.Enabled.Activated:Fire() end
	local function choose(session, part)
		session.ui.controls.HitPart.Activated:Fire()
		check(session.ui.dropdown.Visible)
		session.ui.hitPartOptions[part].Activated:Fire()
		check(session.ui.popupField==nil)
	end
	local function notices(session)
		local received, original = {}, session.notifications.notify
		session.notifications.notify = function(self, subtitle, ...)
			table.insert(received, subtitle)
			return original(self, subtitle, ...)
		end
		return received
	end
	local function has(list, value) return table.find(list, value) ~= nil end
	local function pressC(mock, processed)
		mock.services.UserInputService.InputBegan:Fire(mock:input("Keyboard", 0, 0, "C"), processed == true)
	end
	local function angle(actual, desired)
		return math.acos(math.clamp(actual.Unit:Dot(desired.Unit), -1, 1))
	end
	local function leveled(frame)
		for _, vector in ipairs({frame.Position, frame.LookVector, frame.RightVector, frame.UpVector}) do
			for _, component in ipairs({vector.X, vector.Y, vector.Z}) do
				check(component == component and math.abs(component) < math.huge, "nonfinite camera component")
			end
		end
		-- With yaw/pitch only, right is horizontal and up stays on the upright
		-- hemisphere, including near either vertical pole. This inspects the
		-- actual camera frame rather than trusting a diagnostic's roll field.
		near(frame.RightVector.Y, 0, 1e-8)
		check(frame.UpVector.Y >= -1e-8, "camera inverted its upright reference")
		near(frame.LookVector.Magnitude, 1, 1e-8)
		near(frame.RightVector.Magnitude, 1, 1e-8)
		near(frame.UpVector.Magnitude, 1, 1e-8)
		near(frame.LookVector:Dot(frame.RightVector), 0, 1e-8)
		near(frame.LookVector:Dot(frame.UpVector), 0, 1e-8)
		near(frame.RightVector:Dot(frame.UpVector), 0, 1e-8)
	end

	test("executing the actual standalone bundle autostarts the disabled GUI and welcome", function(mock)
		mock.env.SEDWARE_CAM_NO_AUTOSTART=false
		mock.env.CAM_LOCK_NO_AUTOSTART=false
		local api=reloadBundle(mock.env)
		check(api.session ~= nil and not api.session.destroyed)
		check(api.session.gui.Parent == mock.playerGui and not api.session.config.Enabled)
		check(api.session.notifications.body.Text == "Successfully Loaded")
		near(mock:countRenderBindings(),1);near(mock.counters.cameraWrites,0)
		api.Unload()
		near(mock:countConnections(),0);near(mock:countRenderBindings(),0)
	end)

	test("default disabled V3.1 has six MAIN fields plus MISC and Sedware branding", function(mock, create)
		local session = create()
		local ui = session.ui
		check(session.gui == ui.gui and ui.gui.Name == "SedwareCamLock_UI")
		check(ui.gui.Parent == mock.playerGui)
		near(size(ui.controls), 17); near(size(ui.hitPartOptions), 3)
		local expected = {Enabled=false, HitPart="UpperTorso",
			PredictionX=13.15, PredictionY=13.15, Smoothness=0.405, Radius=180}
		for field, value in pairs(expected) do
			check(session.config[field] == value, "incorrect default " .. field)
			check(ui.values[field] == value)
		end
		check(ui.controls.Enabled.Text == "OFF" and not ui.dropdown.Visible)
		check(ui.controls.HitPart.Text:find("UpperTorso", 1, true) ~= nil)
		for _, field in ipairs({"PredictionX", "PredictionY", "Smoothness", "Radius"}) do
			near(tonumber(ui.controls[field].Text), expected[field])
		end
		check(ui.title.Text == "SEDWARE V3.1" and ui.subtitle.Text == "CAM LOCK · PINK EDITION" and ui.version.Text == "v3.1")
		near(ui.panel.Size.X.Offset, 420); near(ui.panel.Size.Y.Offset, 520)
		near(ui.panel.BackgroundColor3.R, 10/255)
		check(ui.logo.Name == "SedwareLogo")
		check(ui.logo:FindFirstChild("OriginalLogoImage") ~= nil)
		near(#ui.logo:FindFirstChild("TemporaryFallback"):GetChildren(), 5)
		for _, bar in ipairs(ui.logo:FindFirstChild("TemporaryFallback"):GetChildren()) do
			near(bar.BackgroundColor3.R, 1); near(bar.BackgroundColor3.G, 20/255); near(bar.BackgroundColor3.B, 147/255)
		end
		local mainButtons, boxes, choiceButtons = 0, 0, 0
		for _, node in ipairs(ui.gui:GetDescendants()) do
			if node:IsA("TextBox") then boxes += 1 end
			if node:IsA("TextButton") then
				if node.Parent == ui.dropdown then choiceButtons += 1 else mainButtons += 1 end
			end
		end
		near(mainButtons, 15); near(boxes, 7); near(choiceButtons, 3)
		mock:resetCounters(); mock:advance(0.1)
		near(mock.counters.candidateScans, 0); near(mock.counters.cameraWrites, 0)
		near(mock.counters.mouseWrites, 0)
		check(session:GetLockedTarget() == nil and not session.destroyed)
	end)

	test("native Enable acquires center target and OFF stops all camera writes", function(mock, create)
		local target = mock:addPlayer("EnabledTarget", mock.env.Vector3.new(12, 0, -50))
		local session = create()
		local received = notices(session)
		mock:resetCounters(); enable(session)
		check(session.config.Enabled and session.ui.controls.Enabled.Text == "ON")
		check(session:GetLockedTarget() == target)
		check(has(received, "Lock Enabled") and has(received, "Target Locked"))
		mock:advance(1/60)
		check(session:GetPrediction() ~= nil and session:GetPredictedPosition() ~= nil)
		check(mock:cameraWritesFor(mock.camera, "CFrame") > 0)
		near(mock:cameraWritesFor(mock.camera, "Focus"), 0)
		near(mock:cameraWritesFor(mock.camera, "CameraType"), 0)
		near(mock:cameraWritesFor(mock.camera, "CameraSubject"), 0)
		near(mock.counters.mouseWrites, 0)
		enable(session)
		check(not session.config.Enabled and session:GetLockedTarget() == nil)
		check(session:GetPrediction() == nil and session.controller.lastFrame == nil)
		check(has(received, "Lock Disabled"))
		mock:resetCounters()
		for _ = 1, 60 do mock:advance(1/60) end
		near(mock.counters.cameraWrites, 0); near(mock.counters.candidateScans, 0)
		check(not session.destroyed and session.gui.Parent == mock.playerGui)
	end)

	test("first-person center and third-person pointer select their closest target", function(mock, create)
		local central = mock:addPlayer("Central", mock.env.Vector3.new(3, 0, -50))
		local atPointer=mock:addPlayer("AtPointer", mock.env.Vector3.new(40, 0, -50))
		mock:setPointer(680, 360)
		for _, mode in ipairs({"Classic", "LockFirstPerson"}) do
			mock.services.Players.LocalPlayer.CameraMode = mock.env.Enum.CameraMode[mode]
			local session = create()
			mock:resetCounters(); enable(session)
			check(session:GetLockedTarget() == (if mode=="Classic" then atPointer else central))
			near(mock.counters.candidateScans, 0)
			session:destroy()
		end
	end)

	test("radius textbox changes acquisition and retains a valid existing player", function(mock, create)
		local target = mock:addPlayer("OutsideInitialRadius", mock.env.Vector3.new(60, 0, -50))
		local session = create({Radius=50})
		enable(session); check(session:GetLockedTarget() == nil)
		edit(session, "Radius", "70")
		near(session.config.Radius, 70)
		mock:advance(0.26)
		check(session:GetLockedTarget() == target)
		edit(session, "Radius", "1")
		mock:resetCounters()
		for _ = 1, 10 do mock:advance(1/60) end
		check(session:GetLockedTarget() == target)
		near(mock.counters.candidateScans, 0)
	end)

	test("valid player persists despite mouse movement closer candidates and screen exit", function(mock, create)
		local target = mock:addPlayer("Persistent", mock.env.Vector3.new(10, 0, -50))
		local session = create({Enabled=true, MaxDistance=2000})
		check(session:GetLockedTarget() == target)
		mock:addPlayer("NewCloser", mock.env.Vector3.new(0, 0, -50))
		mock:setPointer(0, 0)
		mock:move(target, mock.env.Vector3.new(700, 0, -50))
		mock:resetCounters()
		for _ = 1, 30 do mock:advance(1/60) end
		check(session:GetLockedTarget() == target)
		near(mock.counters.candidateScans, 0)
		check(mock.counters.cameraWrites > 0)
	end)

	test("acquisition rejects local dead malformed distant invisible and out-of-radius players", function(mock, create)
		local V = mock.env.Vector3
		local dead = mock:addPlayer("Dead", V.new(0,0,-50)); mock:kill(dead)
		local malformed = mock:addPlayer("MissingPart", V.new(1,0,-50))
		malformed.Character:FindFirstChild("UpperTorso"):Destroy()
		mock:addPlayer("TooFar", V.new(0,0,-900))
		mock:addPlayer("OutsideRadius", V.new(200,0,-50))
		local hidden = mock:addPlayer("Invisible", V.new(2,0,-50))
		mock:setOccluded(hidden, true)
		local session = create({Enabled=true})
		check(session:GetLockedTarget() == nil)
		mock:setOccluded(hidden, false); mock:advance(0.26)
		check(session:GetLockedTarget() == hidden)
	end)

	test("visibility accepts hits on target parts and excludes the local character", function(mock, create)
		local target=mock:addPlayer("VisiblePartHit",mock.env.Vector3.new(2,0,-50))
		local part=target.Character:FindFirstChild("UpperTorso")
		local observed=false
		mock.world.Raycast=function(_world,origin,direction,params)
			mock.counters.raycasts+=1;observed=true
			check(params.FilterType == mock.env.Enum.RaycastFilterType.Exclude)
			check(table.find(params.FilterDescendantsInstances,mock.services.Players.LocalPlayer.Character) ~= nil)
			vectorNear(origin+direction,part.Position)
			return {Instance=part,Position=part.Position,Distance=direction.Magnitude}
		end
		local session=create({Enabled=true})
		check(observed and session:GetLockedTarget() == target)
	end)

	test("dropdown selects actual R15 parts and resets memory without changing player", function(mock, create)
		local V = mock.env.Vector3
		local target = mock:addPlayer("PartTransition", V.new(0,0,-50))
		local session = create({Enabled=true, PredictionSmoothing=0})
		for index = 1, 8 do mock:move(target,V.new(index,0,-50)); mock:advance(0.05) end
		local previousHistory = session.prediction.history
		check(previousHistory.velocity.X > 0)
		mock:resetCounters(); choose(session,"Head")
		check(session:GetLockedTarget() == target and session.config.HitPart == "Head")
		check(session.prediction.history ~= previousHistory)
		mock:advance(0.04)
		vectorNear(session:GetPrediction().currentPosition,target.Character:FindFirstChild("Head").Position)
		near(session:GetPrediction().velocity.Magnitude,0)
		near(mock.counters.candidateScans,0)
		choose(session,"HumanoidRootPart"); mock:advance(0.04)
		check(session:GetLockedTarget() == target)
		vectorNear(session:GetPrediction().currentPosition,target.Character:FindFirstChild("HumanoidRootPart").Position)
		near(session:GetPrediction().velocity.Magnitude,0)
		choose(session,"UpperTorso"); mock:advance(0.04)
		vectorNear(session:GetPrediction().currentPosition,target.Character:FindFirstChild("UpperTorso").Position)
		near(session:GetPrediction().velocity.Magnitude,0)
	end)

	test("UpperTorso uses R6 Torso fallback and a missing R15 part loses target", function(mock, create)
		local r6 = mock:addPlayer("R6Fallback",mock.env.Vector3.new(0,0,-50),"R6")
		local session = create({Enabled=true})
		check(session:GetLockedTarget() == r6)
		mock:advance(0.04)
		vectorNear(session:GetPrediction().currentPosition,r6.Character:FindFirstChild("Torso").Position)
		choose(session,"Head"); mock:advance(0.04)
		vectorNear(session:GetPrediction().currentPosition,r6.Character:FindFirstChild("Head").Position)
		session:destroy(); mock:removePlayer(r6)
		local r15 = mock:addPlayer("R15NoUpperTorso",mock.env.Vector3.new(0,0,-50))
		local second = create({Enabled=true,TargetPartGraceSeconds=0})
		check(second:GetLockedTarget() == r15)
		r15.Character:FindFirstChild("UpperTorso"):Destroy(); mock:advance(0.04)
		check(second:GetLockedTarget() == nil and second:GetPrediction() == nil)
	end)

	test("direct X/Y text edits change actual axis lead while preserving motion memory", function(mock, create)
		local V = mock.env.Vector3
		local target = mock:addPlayer("PredictionControls",V.new(0,0,-50))
		local session = create({Enabled=true,PredictionSmoothing=0,VerticalControl=false,ReversalDamping=false})
		for index=1,8 do mock:move(target,V.new(index,index*0.5,-50-index*0.2));mock:advance(0.05) end
		local history, before = session.prediction.history, session:GetPrediction()
		check(before.velocity.X > 0 and before.velocity.Y > 0 and before.velocity.Z < 0)
		edit(session,"PredictionX",tostring(0.2*13.15/0.1205));mock:advance(0.001)
		local x = session:GetPrediction()
		near(x.predictionX,0.2);near(x.predictionY,0.08)
		check(x.position.X > before.position.X and x.position.Z < before.position.Z)
		check(session.prediction.history == history)
		edit(session,"PredictionY",tostring(0.15*13.15/0.08));mock:advance(0.001)
		local y = session:GetPrediction()
		near(y.predictionX,0.2);near(y.predictionY,0.15)
		check(y.position.Y > x.position.Y and session.prediction.history == history)
		edit(session,"PredictionX",tostring(0.24*13.15/0.1205));edit(session,"PredictionY",tostring(0.10*13.15/0.08));mock:advance(0.001)
		local gain = session:GetPrediction()
		check(gain.camGain==nil);near(gain.predictionX,0.24);near(gain.predictionY,0.10)
		check(gain.position.X > y.position.X and gain.position.Y < y.position.Y)
		near(gain.rawPosition.X,gain.currentPosition.X+gain.velocity.X*(gain.predictionX+gain.ageSeconds),1e-7)
		near(gain.rawPosition.Y,gain.currentPosition.Y+gain.velocity.Y*(gain.predictionY+gain.ageSeconds),1e-7)
		near(gain.rawPosition.Z,gain.currentPosition.Z+gain.velocity.Z*(gain.predictionX+gain.ageSeconds),1e-7)
		check(session.prediction.history == history)
	end)

	test("Smoothness textbox changes angular response and camera position is preserved", function(mock, create)
		mock:addPlayer("SmoothnessControls",mock.env.Vector3.new(30,0,-50))
		local session = create({PredictionX=0,PredictionY=0})
		local errors = {}
		for _, value in ipairs({0.9,0.1}) do
			edit(session,"Smoothness",value)
			enable(session);mock:advance(1/60)
			local desired = session:GetPredictedPosition()-mock.camera.CFrame.Position
			table.insert(errors,angle(mock.camera.CFrame.LookVector,desired))
			vectorNear(mock.camera.CFrame.Position,mock.env.Vector3.new(0,2,20))
			enable(session)
		end
		check(errors[1] > errors[2]*10,"Smoothness did not change actual orientation response")
	end)

	test("invalid finite ranges and nonnumeric edits restore fields without corrupting lock", function(mock, create)
		local target=mock:addPlayer("InvalidEdits",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true})
		for field, values in pairs({PredictionX={"nan","-0.1","1001"},
			PredictionY={"","1e309","1001"},Smoothness={"-1","2","nan"},Radius={"0","2001","abc"}}) do
			local previous,text=session.config[field],session.ui.controls[field].Text
			for _,value in ipairs(values) do
				edit(session,field,value)
				check(session.config[field] == previous and session.ui.controls[field].Text == text)
				check(session:GetLockedTarget() == target and not session.destroyed)
			end
		end
		check(session:SetHitPart("Torso") == false)
		check(session.config.HitPart == "UpperTorso")
		mock:advance(0.04);check(session:GetPrediction() ~= nil)
	end)

	test("enabled targetless retries are bounded by .25 seconds rather than render frequency", function(mock, create)
		local session=create()
		mock:resetCounters();enable(session)
		near(mock.counters.candidateScans,0)
		for _=1,144*2 do mock:advance(1/144) end
		check(session.selector.acquisitionCount>=7 and session.selector.acquisitionCount<=10,"acquisition cadence is unbounded")
		near(mock.counters.candidateScans,0)
		near(mock.counters.cameraWrites,0)
	end)

	test("target death clears memory and notifies before bounded replacement acquisition", function(mock, create)
		local V=mock.env.Vector3
		local selected=mock:addPlayer("Lost",V.new(0,0,-50))
		local replacement=mock:addPlayer("Replacement",V.new(5,0,-50))
		local session=create({Enabled=true,ReacquireOnLoss=true})
		local received=notices(session)
		for index=1,5 do mock:move(selected,V.new(index,0,-50));mock:advance(0.04) end
		local previous=session.prediction.history
		check(previous.velocity.X > 0)
		mock:kill(selected)
		check(session:GetLockedTarget() == nil and session:GetPrediction() == nil)
		check(session.prediction.history ~= previous)
		near(#session.prediction.history.samples,0)
		check(has(received,"Target Lost"))
		mock:resetCounters();mock:advance(0.1)
		check(session:GetLockedTarget() == nil);near(mock.counters.cameraWrites,0)
		mock:advance(0.16)
		check(session:GetLockedTarget() == replacement)
		near(session:GetPrediction().velocity.Magnitude,0)
		near(mock.counters.candidateScans,0)
	end)

	test("target respawn never estimates motion across old and new characters", function(mock, create)
		local target=mock:addPlayer("Respawn",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true,ReacquireOnLoss=true})
		for index=1,6 do mock:move(target,mock.env.Vector3.new(index,0,-50));mock:advance(0.04) end
		local previous=session.prediction.history
		mock:respawn(target,mock.env.Vector3.new(20,0,-50));mock:advance(0.26)
		check(session:GetLockedTarget() == target and session.prediction.history ~= previous)
		near(session:GetPrediction().velocity.Magnitude,0)
		vectorNear(session:GetPrediction().currentPosition,target.Character:FindFirstChild("UpperTorso").Position)
	end)

	test("welcome notification fades with Sedware title pink logo and requested subtitle", function(mock, create)
		local session=create()
		local notification=session.notifications
		check(notification.gui.Name == "SedwareCamLock_Notifications")
		check(notification.title.Text == "SEDWARE" and notification.body.Text == "Successfully Loaded")
		check(notification.toast.Visible and notification.logo.Name == "SedwareLogo")
		near(#notification.logo:FindFirstChild("TemporaryFallback"):GetChildren(),5)
		near(notification.toast.BackgroundColor3.R,10/255)
		mock:advance(0.18);near(notification.toast.GroupTransparency,0)
		mock:advance(3.2);check(not notification.toast.Visible)
	end)

	test("welcome then Lock Enabled and Target Locked remain visibly ordered", function(mock, create)
		mock:addPlayer("NoticeOrder",mock.env.Vector3.new(0,0,-50))
		local session=create()
		local notification=session.notifications
		enable(session)
		check(notification.body.Text == "Successfully Loaded","Enable interrupted the welcome toast")
		mock:advance(0.18)
		check(notification.body.Text == "Successfully Loaded" and notification.toast.Visible)
		near(notification.toast.GroupTransparency,0)
		mock:advance(2.7)
		check(notification.body.Text == "Successfully Loaded")
		mock:advance(0.13)
		check(notification.body.Text == "Lock Enabled" and notification.toast.Visible)
		mock:advance(0.18)
		check(notification.body.Text == "Lock Enabled")
		near(notification.toast.GroupTransparency,0)
		mock:advance(0.6)
		check(notification.body.Text == "Lock Enabled","Enabled toast did not remain readable")
		mock:advance(0.19)
		check(notification.body.Text == "Target Locked" and notification.toast.Visible)
		mock:advance(0.18)
		near(notification.toast.GroupTransparency,0)
		check(notification.title.Text == "SEDWARE")
	end)

	test("Lock Disabled immediately flushes pending enabled and target notifications", function(mock, create)
		mock:addPlayer("NoticeOffFlush",mock.env.Vector3.new(0,0,-50))
		for _,welcome in ipairs({true,false}) do
			local session=create({WelcomeNotification=welcome})
			enable(session)
			mock:advance(0.18)
			enable(session)
			check(session.notifications.body.Text == "Lock Disabled" and session.notifications.toast.Visible)
			check(session:GetLockedTarget() == nil and not session.config.Enabled)
			mock:resetCounters()
			for _=1,30 do
				mock:advance(0.1)
				check(session.notifications.body.Text == "Lock Disabled","obsolete target toast resurfaced after OFF")
			end
			near(mock.counters.candidateScans,0);near(mock.counters.cameraWrites,0)
			session:destroy()
		end
	end)

	test("C obeys enabled state processed input and focused numeric textboxes", function(mock, create)
		local target=mock:addPlayer("KeyTarget",mock.env.Vector3.new(0,0,-50))
		local session=create()
		mock:resetCounters();pressC(mock)
		check(session:GetLockedTarget() == nil);near(mock.counters.candidateScans,0)
		enable(session);check(session:GetLockedTarget() == target)
		pressC(mock,true);check(session:GetLockedTarget() == target)
		session.ui.controls.PredictionX:CaptureFocus();pressC(mock)
		check(session:GetLockedTarget() == target)
		session.ui.controls.PredictionX:ReleaseFocus();pressC(mock)
		check(session:GetLockedTarget() == nil)
		mock:resetCounters();mock:advance(0.4)
		check(session:GetLockedTarget() == nil and session.config.Enabled,
			"C release automatically reacquired the target while Enable stayed ON")
		near(mock.counters.candidateScans,0);near(mock.counters.cameraWrites,0)
		pressC(mock);check(session:GetLockedTarget() == target)
	end)

	test("Enable OFF and ON restores automatic acquisition after a manual C release", function(mock, create)
		local target=mock:addPlayer("ReauthorizedLock",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true})
		pressC(mock);mock:advance(0.4)
		check(session:GetLockedTarget() == nil and session.config.Enabled)
		enable(session);check(not session.config.Enabled)
		enable(session)
		check(session.config.Enabled and session:GetLockedTarget() == target)
	end)

	test("render callback commits after the default camera and converges despite its resets", function(mock, create)
		mock:addPlayer("RenderOrder",mock.env.Vector3.new(30,0,-50))
		local session=create({Enabled=true,Smoothness=0.9,PredictionX=0,PredictionY=0})
		mock:resetCounters();mock:advance(1/60)
		check(mock.renderOrder[1].name == "RobloxDefaultCamera")
		check(#mock.renderOrder == 2 and mock.renderOrder[2].priority == 201)
		near(mock:countRenderBindings(),1)
		local first=angle(mock.camera.CFrame.LookVector,session:GetPredictedPosition()-mock.camera.CFrame.Position)
		for _=1,30 do mock:advance(1/60) end
		local last=angle(mock.camera.CFrame.LookVector,session:GetPredictedPosition()-mock.camera.CFrame.Position)
		check(last < first/20,"default camera resets prevented convergence")
		check(session.controller.lastFrame == mock.camera.CFrame)
	end)

	test("first active frame removes inherited camera roll without changing GUI or prediction settings", function(mock, create)
		local V, F = mock.env.Vector3, mock.env.CFrame
		local position = V.new(0,2,20)
		local rolled = F.lookAt(position, position+V.new(0.1,0.2,-1), V.new(0.8,1,0.2))
		check(math.abs(rolled.RightVector.Y) > 0.3, "fixture must contain camera roll")
		mock:setDefaultCamera(mock.camera, rolled)
		mock.camera._props.CFrame = rolled
		local target = mock:addPlayer("InheritedRoll", V.new(15,0,-50))
		local session = create({Enabled=true,Smoothness=0.9})
		local expected = {HitPart="UpperTorso",PredictionX=13.15,
			PredictionY=13.15,Smoothness=0.9,Radius=180}
		local subject = mock.camera.CameraSubject
		mock:resetCounters()
		for _=1,60 do
			mock:advance(1/60)
			leveled(mock.camera.CFrame)
			vectorNear(mock.camera.CFrame.Position,position)
			check(session:GetLockedTarget() == target)
		end
		for field,value in pairs(expected) do
			check(session.config[field] == value and session.ui.values[field] == value,
				"roll correction changed existing field "..field)
		end
		near(size(session.ui.controls),17)
		near(session.ui.panel.Size.X.Offset,420);near(session.ui.panel.Size.Y.Offset,520)
		check(session.ui.title.Text == "SEDWARE V3.1" and session.ui.subtitle.Text == "CAM LOCK · PINK EDITION")
		check(mock.camera.CameraSubject == subject)
		near(mock:cameraWritesFor(mock.camera,"CameraSubject"),0)
		near(mock:cameraWritesFor(mock.camera,"CameraType"),0)
		near(mock:cameraWritesFor(mock.camera,"Focus"),0)
		check(session.prediction.history ~= nil and session:GetPrediction() ~= nil)
	end)

	test("circles with jumping falling and passage behind never accumulate roll in the actual bundle", function(mock, create)
		local V = mock.env.Vector3
		local position = V.new(0,2,20)
		local target = mock:addPlayer("CircleJumpFall",V.new(0,1,-30))
		local session = create({Enabled=true,MaxDistance=1000})
		local sawBehind,sawRising,sawFalling = false,false,false
		mock:resetCounters()
		for index=1,720 do
			local phase = index*2*math.pi/240
			local nextPosition = position+V.new(math.sin(phase)*50,math.sin(phase*2)*12-1,-math.cos(phase)*50)
			mock:move(target,nextPosition)
			mock:advance(1/60)
			leveled(mock.camera.CFrame)
			vectorNear(mock.camera.CFrame.Position,position)
			check(session:GetLockedTarget() == target and not session.destroyed)
			local prediction = session:GetPrediction()
			check(prediction ~= nil)
			if nextPosition.Z > position.Z then sawBehind=true end
			if prediction.velocity.Y > 1 then sawRising=true end
			if prediction.velocity.Y < -1 then sawFalling=true end
		end
		check(sawBehind and sawRising and sawFalling,"motion fixture omitted a required direction")
		near(mock.counters.candidateScans,0)
		near(mock:cameraWritesFor(mock.camera,"CFrame"),720)
		near(mock:cameraWritesFor(mock.camera,"CameraSubject"),0)
		near(mock.counters.mouseWrites,0)
	end)

	test("exact targets above and below remain finite upright and converge through 180 degrees", function(mock, create)
		local V = mock.env.Vector3
		local position = V.new(0,2,20)
		local target = mock:addPlayer("VerticalPoles",V.new(5,0,-50))
		local session = create({Enabled=true,PredictionX=0,PredictionY=0})
		mock:advance(0.04)
		for _, height in ipairs({60,-60,60,-60}) do
			mock:move(target,position+V.new(0,height-1,0))
			for _=1,40 do
				mock:advance(0.04)
				leveled(mock.camera.CFrame)
				vectorNear(mock.camera.CFrame.Position,position)
				check(session:GetLockedTarget() == target and not session.destroyed)
			end
			local desired = if height > 0 then V.yAxis else -V.yAxis
			check(angle(mock.camera.CFrame.LookVector,desired) < 1e-5,"camera failed to converge at a vertical pole")
		end
	end)

	test("repeated Enable cycles and target changes discard tilted interpolation state", function(mock, create)
		local V,F = mock.env.Vector3,mock.env.CFrame
		local first = mock:addPlayer("CycleFirst",V.new(0,0,-50))
		local second = mock:addPlayer("CycleSecond",V.new(15,0,-50))
		local session = create()
		for index=1,20 do
			local position = V.new(index*0.1,2,20)
			local rolled = F.lookAt(position,position+V.new(0.2,0.1,-1),V.new(-0.7,1,0.1))
			mock:setDefaultCamera(mock.camera,rolled)
			mock.camera._props.CFrame=rolled
			enable(session)
			check(session:GetLockedTarget() == first)
			mock:advance(1/60);leveled(mock.camera.CFrame)
			session:UnlockTarget()
			check(session.controller.lastFrame == nil)
			check(session:LockTarget(second))
			mock:advance(1/60);leveled(mock.camera.CFrame)
			check(session:GetLockedTarget() == second)
			enable(session)
			check(session.controller.lastFrame == nil and session.controller.camera == nil)
			check(session:GetPrediction() == nil and session:GetLockedTarget() == nil)
			mock:resetCounters();mock:advance(1/60)
			near(mock.counters.cameraWrites,0)
			near(mock:countRenderBindings(),1)
		end
	end)

	test("first and third person transitions use each live camera position and preserve target and subject", function(mock, create)
		local V,F = mock.env.Vector3,mock.env.CFrame
		local target = mock:addPlayer("PerspectiveTransition",V.new(15,0,-50))
		local session = create({Enabled=true})
		local subject = mock.camera.CameraSubject
		for index=1,12 do
			local firstPerson = index%2==1
			mock.services.Players.LocalPlayer.CameraMode = mock.env.Enum.CameraMode[if firstPerson then "LockFirstPerson" else "Classic"]
			local position = V.new(index*0.3,2+index*0.1,if firstPerson then 0.2 else 20)
			local rolled = F.lookAt(position,position+V.new(0.1,0.1,-1),V.new(0.6,1,0.2))
			mock:setDefaultCamera(mock.camera,rolled)
			mock:resetCounters();mock:advance(1/60)
			leveled(mock.camera.CFrame)
			vectorNear(mock.camera.CFrame.Position,position)
			check(session:GetLockedTarget() == target and mock.camera.CameraSubject == subject)
			near(mock:cameraWritesFor(mock.camera,"Focus"),0)
			near(mock:cameraWritesFor(mock.camera,"CameraSubject"),0)
			near(mock:cameraWritesFor(mock.camera,"CameraType"),0)
		end
	end)

	test("actual bundle roll removal and angular response agree at 30 60 120 and 144 FPS", function(mock, create)
		local V,F = mock.env.Vector3,mock.env.CFrame
		local position = V.new(0,2,20)
		local rolled = F.lookAt(position,position+V.new(-0.4,0.25,-1),V.new(0.8,1,0.3))
		mock:addPlayer("FPSComparison",V.new(20,15,-50))
		local responses={}
		for _,fps in ipairs({30,60,120,144}) do
			mock:setDefaultCamera(mock.camera,rolled)
			mock.camera._props.CFrame=rolled
			local session=create({Enabled=true,Smoothness=0.9,PredictionX=0,PredictionY=0})
			for _=1,fps/2 do
				mock:advance(1/fps)
				leveled(mock.camera.CFrame)
				vectorNear(mock.camera.CFrame.Position,position)
			end
			table.insert(responses,mock.camera.CFrame.LookVector)
			session:destroy()
		end
		for _,response in ipairs(responses) do vectorNear(response,responses[1],1e-7) end
	end)

	test("optional internal camera diagnostics are finite throttled and add no GUI controls", function(mock, create)
		mock:addPlayer("CameraDebug",mock.env.Vector3.new(10,0,-50))
		local session=create({Enabled=true})
		check(session.config.CameraDebugMode == false)
		for _=1,60 do mock:advance(1/60) end
		check(not mock:hasLog("[CamCamera]"),"camera debug logs were enabled by default")
		check(session:configure("CameraDebugMode",true))
		check(session:configure("CameraDebugInterval",0.5))
		for _=1,120 do mock:advance(1/60) end
		local count=0
		for _,entry in ipairs(mock.logs) do
			if entry.text:find("[CamCamera]",1,true) then count+=1 end
		end
		check(count>=3 and count<=5,"camera diagnostics flooded console or failed to log: "..tostring(count))
		local diagnostic=session.controller:GetDiagnostics()
		check(type(diagnostic)=="table" and type(diagnostic.state)=="string" and #diagnostic.state>0)
		for _,field in ipairs({"yaw","pitch","roll","targetAngle","deltaTime","angularError"}) do
			local value=diagnostic[field]
			check(type(value)=="number" and value==value and math.abs(value)<math.huge,"invalid camera diagnostic "..field)
		end
		near(diagnostic.roll,0,1e-6)
		near(diagnostic.deltaTime,1/60,1e-8)
		near(size(session.ui.controls),17)
		check(session.ui.controls.CameraDebugMode==nil and session.ui.controls.CameraDebugInterval==nil)
		check(session:configure("CameraDebugMode",false))
		for _=1,60 do mock:advance(1/60) end
		local finalCount=0
		for _,entry in ipairs(mock.logs) do if entry.text:find("[CamCamera]",1,true) then finalCount+=1 end end
		near(finalCount,count)
	end)

	test("replacement CurrentCamera uses its live position and old camera receives no writes", function(mock, create)
		local V=mock.env.Vector3
		mock:addPlayer("CameraReplacement",V.new(20,0,-50))
		local session=create({Enabled=true})
		mock:advance(0.04)
		local replacement=mock:newCamera(V.new(5,3,25))
		mock.world.CurrentCamera=replacement
		mock:resetCounters();mock:advance(0.04)
		check(session:GetLockedTarget() ~= nil and session.controller.camera == replacement)
		near(mock:cameraWritesFor(mock.camera),0)
		near(mock:cameraWritesFor(replacement,"CFrame"),1)
		vectorNear(replacement.CFrame.Position,V.new(5,3,25))
		mock:setDefaultCamera(replacement,mock.env.CFrame.new(V.new(6,4,24)))
		mock:advance(0.04)
		vectorNear(replacement.CFrame.Position,V.new(6,4,24))
	end)

	test("Scriptable cameras and temporary camera gaps pause safely then resume", function(mock, create)
		local target=mock:addPlayer("CutscenePause",mock.env.Vector3.new(20,0,-50))
		local session=create({Enabled=true})
		mock:advance(0.04)
		mock.camera.CameraType=mock.env.Enum.CameraType.Scriptable
		mock:resetCounters();mock:advance(0.04)
		near(mock.counters.cameraWrites,0)
		check(session:GetLockedTarget() == target and not session.destroyed)
		mock.world.CurrentCamera=nil;mock:advance(0.04)
		near(mock.counters.cameraWrites,0)
		check(session:GetLockedTarget() == target and session.controller.lastFrame == nil)
		mock.world.CurrentCamera=mock.camera
		mock.camera.CameraType=mock.env.Enum.CameraType.Custom
		mock:resetCounters();mock:advance(0.04)
		near(mock:cameraWritesFor(mock.camera,"CFrame"),1)
		check(session:GetLockedTarget() == target)
	end)

	test("duplicate actual bundle execution has one UI owner and render binding", function(mock, create)
		mock:addPlayer("Rerun",mock.env.Vector3.new(0,0,-50))
		local first=create({Enabled=true})
		mock:advance(0.04)
		local firstInputs=mock:countSignalConnections(mock.services.UserInputService.InputBegan)
		local second=create({Enabled=true})
		check(first.destroyed and first.ui.destroyed and first.notifications.destroyed)
		near(#first.cleanup.tasks,0);near(#first.targetCleanup.tasks,0)
		near(mock:countRenderBindings(),1)
		near(mock:countSignalConnections(mock.services.RunService.RenderStepped),0)
		near(mock:countSignalConnections(mock.services.UserInputService.InputBegan),firstInputs)
		local uiCount,notificationCount=0,0
		for _,node in ipairs(mock.playerGui:GetChildren()) do
			if node.Name == "SedwareCamLock_UI" then uiCount+=1 end
			if node.Name == "SedwareCamLock_Notifications" then notificationCount+=1 end
		end
		near(uiCount,1);near(notificationCount,1)
		mock:resetCounters();mock:advance(0.04)
		near(mock:cameraWritesFor(mock.camera,"CFrame"),1)
		second:Unload();check(second.destroyed)
		near(mock:countConnections(),0);near(mock:countRenderBindings(),0)
		mock:resetCounters();mock:advance(0.5);pressC(mock)
		near(mock.counters.cameraWrites,0);near(mock.counters.candidateScans,0)
	end)

	test("GUI destruction releases all native input target and frame ownership", function(mock, create)
		mock:addPlayer("GuiDestroyed",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true})
		session.gui:Destroy()
		check(session.destroyed and session:GetLockedTarget() == nil)
		near(mock:countConnections(),0);near(mock:countRenderBindings(),0)
		mock:resetCounters();mock:advance(0.5)
		near(mock.counters.cameraWrites,0)
	end)

	test("native LocalScript destruction unloads the actual standalone session", function(mock, create)
		mock.env.script=mock.env.Instance.new("LocalScript")
		mock:addPlayer("ScriptLifetime",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true})
		mock.env.script:Destroy()
		check(session.destroyed and session:GetLockedTarget() == nil)
		near(mock:countConnections(),0);near(mock:countRenderBindings(),0)
	end)

	test("startup waits for delayed PlayerGui and CurrentCamera before binding or writing", function(mock, create)
		local camera=mock.world.CurrentCamera
		mock.playerGui.Parent=nil;mock.world.CurrentCamera=nil
		mock:schedule(0.1,function()
			check(mock:countRenderBindings() == 0 and mock.counters.cameraWrites == 0)
			mock.playerGui.Parent=mock.services.Players.LocalPlayer
		end)
		mock:schedule(0.2,function() mock.world.CurrentCamera=camera end)
		local session=create({InitializationTimeout=0.5,InitializationPollInterval=0.05})
		check(mock:getTime() >= 1.2 and session.gui.Parent == mock.playerGui)
		check(mock:hasLog("[PlayerGui][WAIT]") and mock:hasLog("[CurrentCamera][WAIT]"))
		check(mock:hasLog("[PlayerGui][READY]") and mock:hasLog("[CurrentCamera][READY]"))
		local modules,configuration=false,false
		for _,event in ipairs(session.report.events) do
			if event.phase == "CamModules" and event.status == "READY" then modules=true end
			if event.phase == "CamConfiguration" and event.status == "READY" then configuration=true end
		end
		check(modules and configuration,"readiness discarded earlier startup diagnostic phases")
		near(mock:countRenderBindings(),1);near(mock.counters.cameraWrites,0)
	end)

	test("false startup options fail configuration instead of silently using defaults", function(mock)
		local api=reloadBundle(mock.env)
		local session,report=api.tryInit(false)
		check(session == nil and report.ready == false)
		check(report.failurePhase == "Configuration")
		check(mock:hasLog("[Configuration][FAIL]"))
		check(mock.playerGui:FindFirstChild("SedwareCamLock_UI") == nil)
		near(mock:countRenderBindings(),0);near(mock.counters.cameraWrites,0)
	end)

	test("Unload during readiness cancels the pending startup before GUI creation", function(mock)
		local api=reloadBundle(mock.env)
		mock.world.CurrentCamera=nil
		mock:schedule(0.1,function() api.Unload() end)
		mock:schedule(0.2,function() mock.world.CurrentCamera=mock.camera end)
		local started=mock:getTime()
		local session,report=api.tryInit({InitializationTimeout=0.5,InitializationPollInterval=0.05})
		check(session == nil and report.ready == false and report.cancelled == true)
		check(mock:getTime()-started <= 0.151,"Unload did not stop the bounded wait promptly")
		check(mock.playerGui:FindFirstChild("SedwareCamLock_UI") == nil)
		check(mock:find("Successfully Loaded") == nil)
		near(mock:countRenderBindings(),0);near(mock.counters.cameraWrites,0)
	end)

	test("readiness timeout remains bounded and emits a failure without success", function(mock)
		mock.world.CurrentCamera=nil
		local api=reloadBundle(mock.env)
		local started=mock:getTime()
		local session,report=api.tryInit({InitializationTimeout=0.2,InitializationPollInterval=0.05})
		check(session == nil and report.ready == false and report.timedOut)
		check(mock:getTime()-started <= 0.251)
		check(mock:hasLog("CurrentCamera") and mock:hasLog("[Load Failed]"))
		near(mock:countRenderBindings(),0);near(mock.counters.cameraWrites,0)
		check(mock.playerGui:FindFirstChild("SedwareCamLock_UI") == nil)
	end)

	test("GUI construction failure cleans partially allocated objects and never writes camera", function(mock)
		local api=reloadBundle(mock.env)
		local original=mock.env.Instance.new
		mock.env.Instance.new=function(className)
			if className == "TextBox" then error("controlled Cam GUI construction failure") end
			return original(className)
		end
		local ok,session,report=pcall(api.tryInit,{Enabled=true})
		mock.env.Instance.new=original
		check(ok and session == nil and report.ready == false)
		check(mock:hasLog("controlled Cam GUI construction failure"))
		check(mock:hasLog("[Load Failed]"))
		check(mock.playerGui:FindFirstChild("SedwareCamLock_UI") == nil)
		near(mock.counters.cameraWrites,0);near(mock:countRenderBindings(),0)
		near(mock:countConnections(),0)
	end)

	test("render registration that binds then throws still unbinds all partial ownership", function(mock)
		local api=reloadBundle(mock.env)
		local run=mock.services.RunService
		local original=run.BindToRenderStep
		run.BindToRenderStep=function(self,name,priority,callback)
			original(self,name,priority,callback)
			error("controlled partially registered render binding failure")
		end
		local ok,session,report=pcall(api.tryInit,{Enabled=true})
		run.BindToRenderStep=original
		check(ok and session == nil and report.ready == false)
		check(mock:hasLog("controlled partially registered render binding failure"))
		near(mock:countRenderBindings(),0);near(mock:countConnections(),0)
		near(mock.counters.cameraWrites,0)
		check(mock.playerGui:FindFirstChild("SedwareCamLock_UI") == nil)
		check(mock.playerGui:FindFirstChild("SedwareCamLock_Notifications") == nil)
	end)

	test("failed GUI replacement preserves the working owner's UI binding and target", function(mock, create)
		local target=mock:addPlayer("PreservedOwner",mock.env.Vector3.new(0,0,-50))
		local first=create({Enabled=true})
		local api=reloadBundle(mock.env)
		local original=mock.env.Instance.new
		mock.env.Instance.new=function(className)
			if className == "TextBox" then error("controlled replacement UI failure") end
			return original(className)
		end
		mock:resetCounters()
		local ok,failed,report=pcall(api.tryInit,{Enabled=true})
		mock.env.Instance.new=original
		check(ok and failed == nil and report.ready == false)
		check(not first.destroyed and first.gui.Parent == mock.playerGui and first:GetLockedTarget() == target)
		near(mock:countRenderBindings(),1);near(mock.counters.cameraWrites,0)
		mock:advance(0.04);near(mock:cameraWritesFor(mock.camera,"CFrame"),1)
	end)

	test("critical render errors unload and expose native failure diagnostics", function(mock, create)
		mock:addPlayer("RenderError",mock.env.Vector3.new(0,0,-50))
		local session=create({Enabled=true})
		local original=mock.world.GetServerTimeNow
		mock.world.GetServerTimeNow=function() error("controlled Cam render clock failure") end
		mock:resetCounters();mock:advance(0.04)
		mock.world.GetServerTimeNow=original
		check(session.destroyed and session:GetLockedTarget() == nil)
		near(mock:countConnections(),0);near(mock:countRenderBindings(),0)
		near(mock.counters.cameraWrites,0)
		check(mock:hasLog("controlled Cam render clock failure") and mock:hasLog("[Load Failed]"))
		check(mock:find("SEDWARE | Load Failed") ~= nil)
	end)

	test("invalid startup config exposes one native failure toast and console diagnostics", function(mock)
		local api=reloadBundle(mock.env)
		local session,report=api.tryInit({Smoothness=math.huge})
		check(session == nil and report.ready == false)
		check(mock:hasLog("[Configuration][FAIL]") and mock:hasLog("[Load Failed]"))
		local title=mock:find("SEDWARE | Load Failed")
		check(title ~= nil,"startup failure toast was not visible")
		for _,node in ipairs(mock.playerGui:GetDescendants()) do
			check(node.Text ~= "Successfully Loaded","failure emitted a success notification")
		end
		near(mock.counters.cameraWrites,0);near(mock:countRenderBindings(),0)
		mock:advance(2.1)
		check(mock:find("SEDWARE | Load Failed") == nil)
	end)

	print(string.format("Cam actual-bundle native doubles: %d tests, %d assertions, %d failures",tests,assertions,failures))
	assert(failures == 0,"Cam GUI/runtime tests failed")
	return {tests=tests,checks=assertions}
end
