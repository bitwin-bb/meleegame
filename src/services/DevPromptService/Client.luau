--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterGui = game:GetService("StarterGui")
local TextChatService = game:GetService("TextChatService")
local UserInputService = game:GetService("UserInputService")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Networker = require(ReplicatedStorage.Packages.Networker)
local React = require(ReplicatedStorage.Packages.React)
local Signal = require(ReplicatedStorage.Packages.Signal)
local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)
local Role = require(ReplicatedStorage.Shared.Services.DevPromptService.Role)

type ConsoleEntry = DevPromptServiceUtils.ConsoleEntry
type DevPromptState = DevPromptServiceUtils.DevPromptState
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

function DevPromptServiceClient.pushStateChanged(self: DevPromptServiceClient)
	self.stateChanged:Fire(self:getState())
end

function DevPromptServiceClient.syncChatAvailability(self: DevPromptServiceClient)
	setChatCoreGuiEnabled(self.state.isOpen)
end

function DevPromptServiceClient.mergeState(self: DevPromptServiceClient, serverStateRaw: any)
	local fallback = self.state or DevPromptServiceUtils.createDefaultState()
	local nextState = DevPromptServiceUtils.sanitizeState(serverStateRaw, fallback)
	nextState.entries = DevPromptServiceUtils.limitEntries(fallback.entries, nextState.maxEntries)
	nextState.isOpen = fallback.isOpen
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
		properties.Text = Role.decorateChatMessageText(roleId, message.Text, phase)
		return properties
	end

	self._incomingMessageCallback = incomingMessageCallback
	TextChatService.OnIncomingMessage = incomingMessageCallback
end

function DevPromptServiceClient.init(self: DevPromptServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.state = DevPromptServiceUtils.createDefaultState()
	self.isStateReady = false
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

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function()
		task.defer(function()
			self:syncChatAvailability()
		end)
	end))

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
}

return DevPromptServiceClient :: DevPromptServiceClient
