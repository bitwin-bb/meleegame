--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Networker = require(ReplicatedStorage.Packages.Networker)
local React = require(ReplicatedStorage.Packages.React)
local Signal = require(ReplicatedStorage.Packages.Signal)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)
local PlayerServiceUtils = require(ReplicatedStorage.Shared.Services.PlayerService.PlayerServiceUtils)
local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)

type ConsoleEntry = DevPromptServiceUtils.ConsoleEntry
type DevPromptState = DevPromptServiceUtils.DevPromptState
type CharacterRig = PlayerServiceUtils.CharacterRig
type PlayerRoleSnapshot = Role.PlayerRoleSnapshot
type RoleId = Role.RoleId

type SignalObject = {
	Connect: (self: SignalObject, callback: (state: DevPromptState) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, state: DevPromptState) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local DevPromptServiceClient = {}

local DEFAULT_TOGGLE_KEYCODE = Enum.KeyCode.F2
local CHAT_CORE_GUI_MAX_ATTEMPTS = 8
local CHAT_CORE_GUI_RETRY_DELAY = 0.2
local FLY_RENDERSTEP_NAME = "DevPromptService_Fly"
local FLY_HORIZONTAL_NEGATIVE_KEYS = { Enum.KeyCode.A, Enum.KeyCode.Left }
local FLY_HORIZONTAL_POSITIVE_KEYS = { Enum.KeyCode.D, Enum.KeyCode.Right }
local FLY_ASCEND_KEYS = { Enum.KeyCode.W, Enum.KeyCode.Up, Enum.KeyCode.Space }
local FLY_DESCEND_KEYS = {
	Enum.KeyCode.S,
	Enum.KeyCode.Down,
	Enum.KeyCode.LeftShift,
	Enum.KeyCode.RightShift,
	Enum.KeyCode.LeftControl,
	Enum.KeyCode.RightControl,
}

local function cloneState(stateRaw: any): DevPromptState
	return DevPromptServiceUtils.cloneState(stateRaw)
end

local function setChatCoreGuiEnabled(enabledRaw: any)
	local enabled = enabledRaw == true
	local attempts = 0

	local function apply()
		attempts += 1

		pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Chat, enabled)
		end)

		if attempts >= CHAT_CORE_GUI_MAX_ATTEMPTS then
			return
		end

		local getSuccess, isEnabled = pcall(function()
			return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
		end)
		if (not getSuccess) or isEnabled ~= enabled then
			task.delay(CHAT_CORE_GUI_RETRY_DELAY, apply)
		end
	end

	apply()
end

local function isAnyKeyDown(keyCodes: { Enum.KeyCode }): boolean
	for _, keyCode in keyCodes do
		if UserInputService:IsKeyDown(keyCode) then
			return true
		end
	end
	return false
end

function DevPromptServiceClient.pushStateChanged(self: DevPromptServiceClient)
	self.stateChanged:Fire(self:getState())
end

function DevPromptServiceClient.canOpenConsole(self: DevPromptServiceClient): boolean
	return self.isStateReady == true and self.state.canUseCommands == true
end

function DevPromptServiceClient.syncChatAvailability(self: DevPromptServiceClient)
	setChatCoreGuiEnabled(self.state.isOpen)
end

function DevPromptServiceClient.mergeState(self: DevPromptServiceClient, serverStateRaw: any)
	local fallback = self.state or DevPromptServiceUtils.createDefaultState()
	local nextState = DevPromptServiceUtils.sanitizeState(serverStateRaw, fallback)
	nextState.entries = DevPromptServiceUtils.limitEntries(fallback.entries, nextState.maxEntries)
	nextState.isOpen = fallback.isOpen
	if nextState.canUseCommands ~= true then
		nextState.isOpen = false
	end
	self.state = nextState
	self.isStateReady = true
	self:syncChatAvailability()
	self:pushStateChanged()
end

function DevPromptServiceClient.applyState(self: DevPromptServiceClient, stateRaw: any)
	self:mergeState(stateRaw)
end

function DevPromptServiceClient.receiveEntries(self: DevPromptServiceClient, entriesRaw: any, clearBeforeRaw: any)
	local nextEntries = if clearBeforeRaw == true then {} else DevPromptServiceUtils.cloneEntries(self.state.entries)
	local incomingEntries = DevPromptServiceUtils.cloneEntries(entriesRaw)
	for _, entry in incomingEntries do
		nextEntries[#nextEntries + 1] = entry
	end
	self.state.entries = DevPromptServiceUtils.limitEntries(nextEntries, self.state.maxEntries)
	self:pushStateChanged()
end

function DevPromptServiceClient.requestSync(self: DevPromptServiceClient)
	self.networker:fire(DevPromptServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function DevPromptServiceClient.resolveFlyRig(self: DevPromptServiceClient): CharacterRig?
	local character = self.localPlayer.Character
	if character == nil then
		return nil
	end
	return PlayerServiceUtils.resolveCharacterRig(character)
end

function DevPromptServiceClient.setCharacterFlyCollision(
	self: DevPromptServiceClient,
	characterRaw: Model?,
	enabledRaw: any
)
	local enabled = enabledRaw == true
	if not enabled then
		for part, previousCanCollide in self.flyCollisionSnapshots do
			if part.Parent ~= nil then
				part.CanCollide = previousCanCollide
			end
		end
		self.flyCollisionSnapshots = {}
		self.flyCollisionCharacter = nil
		return
	end

	local character = characterRaw
	if character == nil then
		return
	end

	if self.flyCollisionCharacter ~= nil and self.flyCollisionCharacter ~= character then
		self:setCharacterFlyCollision(nil, false)
	end

	self.flyCollisionCharacter = character
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			if self.flyCollisionSnapshots[descendant] == nil then
				self.flyCollisionSnapshots[descendant] = descendant.CanCollide
			end
			descendant.CanCollide = false
		end
	end
end

function DevPromptServiceClient.setFlyEnabledLocally(
	self: DevPromptServiceClient,
	enabledRaw: any,
	speedRaw: any?
)
	local nextEnabled = enabledRaw == true
	local nextSpeed = DevPromptServiceUtils.DEFAULT_FLY_SPEED
	if typeof(speedRaw) == "number" and speedRaw == speedRaw then
		nextSpeed = math.clamp(
			speedRaw,
			DevPromptServiceUtils.MIN_FLY_SPEED,
			DevPromptServiceUtils.MAX_FLY_SPEED
		)
	elseif typeof(self.flySpeed) == "number" and self.flySpeed == self.flySpeed then
		nextSpeed = math.clamp(
			self.flySpeed,
			DevPromptServiceUtils.MIN_FLY_SPEED,
			DevPromptServiceUtils.MAX_FLY_SPEED
		)
	end

	self.flyEnabled = nextEnabled
	self.flySpeed = nextSpeed

	local rig = self:resolveFlyRig()
	if nextEnabled then
		if rig ~= nil then
			self.flyLockedDepthX = rig.rootPart.Position.X
			self.flyTargetPosition = Vector3.new(self.flyLockedDepthX, rig.rootPart.Position.Y, rig.rootPart.Position.Z)
			self.flyFacingSign = PlayerServiceUtils.getFacingFromLookVector(rig.rootPart.CFrame.LookVector, self.flyFacingSign)
			self:setCharacterFlyCollision(rig.character, true)
			rig.humanoid.PlatformStand = true
			if PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
				rig.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
			end
		end
		return
	end

	self.flyLockedDepthX = nil
	self.flyTargetPosition = nil
	self:setCharacterFlyCollision(nil, false)
	if rig ~= nil then
		rig.humanoid.PlatformStand = false
		rig.rootPart.AssemblyLinearVelocity = Vector3.zero
		rig.rootPart.AssemblyAngularVelocity = Vector3.zero
		if PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
			rig.humanoid:ChangeState(Enum.HumanoidStateType.GettingUp)
		end
		PlayerServiceUtils.ensureRootPartUpright(
			rig.rootPart,
			self.flyFacingSign,
			PlayerServiceUtils.DEFAULT_ROOT_UPRIGHT_TOLERANCE_DEGREES
		)
	end
end

function DevPromptServiceClient.applyFlyStateFromAttributes(self: DevPromptServiceClient)
	local flyEnabled = self.localPlayer:GetAttribute(DevPromptServiceUtils.FLY_ATTRIBUTE) == true
	local flySpeedAttribute = self.localPlayer:GetAttribute(DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE)
	self:setFlyEnabledLocally(flyEnabled, flySpeedAttribute)
end

function DevPromptServiceClient.stepFly(self: DevPromptServiceClient, deltaTime: number)
	if not self.flyEnabled then
		return
	end

	local rig = self:resolveFlyRig()
	if rig == nil then
		return
	end
	if not PlayerServiceUtils.isHumanoidAlive(rig.humanoid) then
		return
	end

	if self.flyCollisionCharacter ~= rig.character then
		self:setCharacterFlyCollision(rig.character, true)
	end

	if self.flyLockedDepthX == nil then
		self.flyLockedDepthX = rig.rootPart.Position.X
	end
	if self.flyTargetPosition == nil then
		self.flyTargetPosition = Vector3.new(self.flyLockedDepthX, rig.rootPart.Position.Y, rig.rootPart.Position.Z)
	end

	rig.humanoid.PlatformStand = true
	rig.humanoid:Move(Vector3.zero, false)
	if rig.humanoid:GetState() ~= Enum.HumanoidStateType.Physics then
		rig.humanoid:ChangeState(Enum.HumanoidStateType.Physics)
	end

	local horizontalAxis = 0
	local verticalAxis = 0
	if UserInputService:GetFocusedTextBox() == nil then
		if isAnyKeyDown(FLY_HORIZONTAL_POSITIVE_KEYS) then
			horizontalAxis += 1
		end
		if isAnyKeyDown(FLY_HORIZONTAL_NEGATIVE_KEYS) then
			horizontalAxis -= 1
		end
		if isAnyKeyDown(FLY_ASCEND_KEYS) then
			verticalAxis += 1
		end
		if isAnyKeyDown(FLY_DESCEND_KEYS) then
			verticalAxis -= 1
		end
	end

	if horizontalAxis ~= 0 then
		self.flyFacingSign = PlayerServiceUtils.sanitizeFacingSign(horizontalAxis, self.flyFacingSign)
	end

	local moveVector = PlayerServiceUtils.getSidewaysMoveVector(horizontalAxis, 1) + Vector3.new(0, verticalAxis, 0)
	if moveVector.Magnitude > 1 then
		moveVector = moveVector.Unit
	end

	local nextPosition = (self.flyTargetPosition :: Vector3) + moveVector * self.flySpeed * deltaTime
	nextPosition = Vector3.new(self.flyLockedDepthX :: number, nextPosition.Y, nextPosition.Z)
	self.flyTargetPosition = nextPosition
	local nextLookTarget = nextPosition + Vector3.new(0, 0, -self.flyFacingSign)
	rig.character:PivotTo(CFrame.lookAt(nextPosition, nextLookTarget, Vector3.yAxis))
	rig.rootPart.AssemblyLinearVelocity = Vector3.zero
	rig.rootPart.AssemblyAngularVelocity = Vector3.zero
end

function DevPromptServiceClient.submitCommand(self: DevPromptServiceClient, commandTextRaw: any): boolean
	local commandText = DevPromptServiceUtils.trim(commandTextRaw)
	if commandText == "" then
		return false
	end
	self.networker:fire(DevPromptServiceUtils.NETWORK_METHOD_SUBMIT_COMMAND, commandText)
	return true
end

function DevPromptServiceClient.clearEntries(self: DevPromptServiceClient)
	self.state.entries = {}
	self:pushStateChanged()
end

function DevPromptServiceClient.setOpen(self: DevPromptServiceClient, isOpenRaw: any)
	local nextOpen = if typeof(isOpenRaw) == "boolean" then isOpenRaw else false
	if nextOpen and not self:canOpenConsole() then
		return
	end
	if self.state.isOpen == nextOpen then
		return
	end
	self.state.isOpen = nextOpen
	self:syncChatAvailability()
	self:pushStateChanged()
end

function DevPromptServiceClient.toggle(self: DevPromptServiceClient)
	self:setOpen(not self.state.isOpen)
end

function DevPromptServiceClient.getState(self: DevPromptServiceClient): DevPromptState
	return cloneState(self.state)
end

function DevPromptServiceClient.getPlayerRoleSnapshot(self: DevPromptServiceClient, userIdRaw: any): PlayerRoleSnapshot?
	local userId = DevPromptServiceUtils.sanitizeUserId(userIdRaw)
	if userId == nil then
		return nil
	end

	local snapshot = self.state.playerRoles[tostring(userId)]
	if snapshot == nil then
		return nil
	end
	return DevPromptServiceUtils.clonePlayerRoleSnapshot(snapshot)
end

function DevPromptServiceClient.getRoleIdForUserId(self: DevPromptServiceClient, userIdRaw: any): RoleId
	local snapshot = self:getPlayerRoleSnapshot(userIdRaw)
	if snapshot ~= nil then
		return snapshot.roleId
	end

	local userId = DevPromptServiceUtils.sanitizeUserId(userIdRaw)
	if userId ~= nil then
		local player = Players:GetPlayerByUserId(userId)
		if player ~= nil then
			local attributeRole = player:GetAttribute(DevPromptServiceUtils.ROLE_ATTRIBUTE)
			return Role.getDefinition(attributeRole).id
		end
	end

	return "Member"
end

function DevPromptServiceClient.getReactTextStyle(self: DevPromptServiceClient, roleOrUserIdRaw: any, surfaceRaw: any): Role.TextLabelStyle
	local roleId = if roleOrUserIdRaw == "Owner"
		or roleOrUserIdRaw == "Admin"
		or roleOrUserIdRaw == "Moderator"
		or roleOrUserIdRaw == "Member"
		then roleOrUserIdRaw
		else self:getRoleIdForUserId(roleOrUserIdRaw)
	return Role.getReactTextStyle(roleId, surfaceRaw)
end

function DevPromptServiceClient.useConsoleState(self: DevPromptServiceClient): DevPromptState
	local state, setState = React.useState(function()
		return self:getState()
	end)

	React.useEffect(function()
		local connection = self.stateChanged:Connect(function(nextState: DevPromptState)
			setState(nextState)
		end)
		return function()
			connection:Disconnect()
		end
	end, {})

	return state
end

function DevPromptServiceClient.bindToggleInput(self: DevPromptServiceClient)
	self.janitor:GiveChore(UserInputService.InputBegan:Connect(function(inputObject: InputObject, processed: boolean)
		if inputObject.KeyCode ~= DEFAULT_TOGGLE_KEYCODE then
			return
		end
		if self.state.isOpen then
			self:setOpen(false)
			return
		end
		if not self:canOpenConsole() then
			return
		end
		if processed then
			return
		end
		if UserInputService:GetFocusedTextBox() ~= nil then
			return
		end
		self:setOpen(true)
	end))
end

function DevPromptServiceClient.bindChatDecoration(self: DevPromptServiceClient)
	local incomingMessageCallback = function(message: TextChatMessage)
		local textSource = message.TextSource
		if textSource == nil then
			return nil
		end

		local roleId = self:getRoleIdForUserId(textSource.UserId)
		if roleId == "Member" then
			return nil
		end

		local properties = Instance.new("TextChatMessageProperties")
		local phase = (os.clock() * 0.15) % 1
		local basePrefixText = message.PrefixText
		properties.PrefixText = Role.buildChatPrefixText(roleId, basePrefixText, phase)
		return properties
	end

	self._incomingMessageCallback = incomingMessageCallback
	TextChatService.OnIncomingMessage = incomingMessageCallback
end

function DevPromptServiceClient.init(self: DevPromptServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.state = DevPromptServiceUtils.createDefaultState()
	self.isStateReady = false
	self.flyEnabled = false
	self.flySpeed = DevPromptServiceUtils.DEFAULT_FLY_SPEED
	self.flyLockedDepthX = nil
	self.flyTargetPosition = nil
	self.flyCollisionSnapshots = {}
	self.flyCollisionCharacter = nil
	self.flyFacingSign = PlayerServiceUtils.DEFAULT_FACING_SIGN
	self.networker = Networker.client.new("DevPromptService", self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.previousChatCoreGuiEnabled = true

	local getChatEnabledSuccess, previousChatCoreGuiEnabled = pcall(function()
		return StarterGui:GetCoreGuiEnabled(Enum.CoreGuiType.Chat)
	end)
	if getChatEnabledSuccess then
		self.previousChatCoreGuiEnabled = previousChatCoreGuiEnabled == true
	end

	self:bindToggleInput()
	self:bindChatDecoration()
	self:syncChatAvailability()

	RunService:BindToRenderStep(FLY_RENDERSTEP_NAME, Enum.RenderPriority.Input.Value + 25, function(deltaTime: number)
		self:stepFly(deltaTime)
	end)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character: Model)
		task.defer(function()
			self:syncChatAvailability()
			if self.flyCollisionCharacter ~= nil and self.flyCollisionCharacter ~= character then
				self:setCharacterFlyCollision(nil, false)
			end
			self.flyLockedDepthX = nil
			self.flyTargetPosition = nil
			self:applyFlyStateFromAttributes()
		end)
	end))
	self.janitor:GiveChore(
		self.localPlayer:GetAttributeChangedSignal(DevPromptServiceUtils.FLY_ATTRIBUTE):Connect(function()
			self:applyFlyStateFromAttributes()
		end)
	)
	self.janitor:GiveChore(
		self.localPlayer:GetAttributeChangedSignal(DevPromptServiceUtils.FLY_SPEED_ATTRIBUTE):Connect(function()
			self:applyFlyStateFromAttributes()
		end)
	)

	self.janitor:GiveChore(function()
		RunService:UnbindFromRenderStep(FLY_RENDERSTEP_NAME)
		self:setFlyEnabledLocally(false)
	end)
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(function()
		TextChatService.OnIncomingMessage = nil
	end)
	self.janitor:GiveChore(function()
		setChatCoreGuiEnabled(self.previousChatCoreGuiEnabled)
	end)

	self:applyFlyStateFromAttributes()
	self:requestSync()
end

function DevPromptServiceClient.destroy(self: DevPromptServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

function DevPromptServiceClient.isReady(self: DevPromptServiceClient): boolean
	return self.isStateReady == true
end

type DevPromptServiceClient = typeof(DevPromptServiceClient) & {
	localPlayer: Player,
	state: DevPromptState,
	isStateReady: boolean,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	_incomingMessageCallback: ((message: TextChatMessage) -> TextChatMessageProperties?)?,
	previousChatCoreGuiEnabled: boolean,
	flyEnabled: boolean,
	flySpeed: number,
	flyLockedDepthX: number?,
	flyTargetPosition: Vector3?,
	flyCollisionSnapshots: { [BasePart]: boolean },
	flyCollisionCharacter: Model?,
	flyFacingSign: number,
	canOpenConsole: (self: DevPromptServiceClient) -> boolean,
	resolveFlyRig: (self: DevPromptServiceClient) -> CharacterRig?,
	setCharacterFlyCollision: (self: DevPromptServiceClient, characterRaw: Model?, enabledRaw: any) -> (),
	setFlyEnabledLocally: (self: DevPromptServiceClient, enabledRaw: any, speedRaw: any?) -> (),
	applyFlyStateFromAttributes: (self: DevPromptServiceClient) -> (),
	stepFly: (self: DevPromptServiceClient, deltaTime: number) -> (),
}

return DevPromptServiceClient :: DevPromptServiceClient
