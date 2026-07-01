local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Camera = require("CameraClass")
local CameraServiceUtils = require("CameraServiceUtils")
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local CameraServicePackets = require("NetPacketsShared").CameraService

local function sendPacket(methodName: string, ...: any)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
		return
	end

	local handlerName = string.upper(string.sub(methodName, 1, 1)) .. string.sub(methodName, 2)
	packet.listen(function(payload: any)
		local handler = self[handlerName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.Unpack(payload)
		handler(self, table.unpack(arguments, 1, count))
	end)
end

local function bindPackets(self: any)
	if self.packetsBound == true then
		return
	end

	self.packetsBound = true
	bindPacket(self, "applyMode")
	bindPacket(self, "requestSync")
	bindPacket(self, "setMode")
end

type CameraMode = CameraServiceUtils.CameraMode
type SideViewConfig = CameraServiceUtils.SideViewConfig
type CameraState = CameraServiceUtils.CameraState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local CameraServiceClient = {}

function CameraServiceClient.Init(self: CameraServiceClient)
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)

	local defaultState = CameraServiceUtils.CreateDefaultState()
	self.currentMode = defaultState.mode
	self.sideViewConfig = defaultState.sideViewConfig
	self.snapSideViewOnNextTarget = true
	self.cameraController = Camera.New({
		SideView = {
			config = self.sideViewConfig,
			autoEnable = false,
		},
	})

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character)
		self:OnCharacterAdded(character)
	end))

	if self.localPlayer.Character then
		self:OnCharacterAdded(self.localPlayer.Character)
	end

	sendPacket("requestSync")
end

function CameraServiceClient.OnCharacterAdded(self: CameraServiceClient, character: Model)
	self.character = character
	self.snapSideViewOnNextTarget = true
	self.characterJanitor:Clean()
	self.cameraController:SetSideViewCharacter(character)

	local childAddedConnection: RBXScriptConnection?
	childAddedConnection = character.ChildAdded:Connect(function()
		if self.currentMode ~= "SideView" then
			return
		end

		local target = CameraServiceUtils.GetCharacterTarget(character)
		if target then
			self:ApplySideView()

			if childAddedConnection then
				childAddedConnection:Disconnect()
				childAddedConnection = nil
			end
		end
	end)
	self.characterJanitor:GiveChore(function()
		if childAddedConnection then
			childAddedConnection:Disconnect()
			childAddedConnection = nil
		end
	end)

	if self.currentMode == "SideView" then
		self:ApplySideView()
	end
end

function CameraServiceClient.ApplySideView(self: CameraServiceClient)
	self.cameraController:SetSideViewCharacter(self.character)

	local target = CameraServiceUtils.GetCharacterTarget(self.character)
	local snapToTarget = self.snapSideViewOnNextTarget == true and target ~= nil
	self.cameraController:UseSideView(target, self.sideViewConfig, snapToTarget)

	if snapToTarget then
		self.snapSideViewOnNextTarget = false
	end
end

function CameraServiceClient.ApplyMode(self: CameraServiceClient, mode: any, sideViewConfig: any)
	local nextState: CameraState
	if sideViewConfig then
		nextState = CameraServiceUtils.CreateCameraState(mode, sideViewConfig)
	else
		local mergedSideViewConfig = CameraServiceUtils.MergeSideViewConfig(self.sideViewConfig, nil)
		nextState = CameraServiceUtils.CreateCameraState(mode, mergedSideViewConfig)
	end

	self.currentMode = nextState.mode
	self.sideViewConfig = nextState.sideViewConfig

	if nextState.mode == "SideView" then
		self.cameraController:ConfigureSideView(nextState.sideViewConfig)
		self:ApplySideView()
		return
	end

	self.cameraController:DisableSideView()

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

function CameraServiceClient.SetMode(self: CameraServiceClient, mode: CameraMode, sideViewConfig: SideViewConfig?)
	local configForRequest = CameraServiceUtils.MergeSideViewConfig(self.sideViewConfig, sideViewConfig)
	sendPacket("setMode", mode, configForRequest)
end

function CameraServiceClient.UseSideView(self: CameraServiceClient, sideViewConfig: SideViewConfig?)
	self:SetMode("SideView", sideViewConfig)
end

function CameraServiceClient.UseFirstPerson(self: CameraServiceClient)
	self:SetMode("FirstPerson")
end

function CameraServiceClient.UseIsometric(self: CameraServiceClient)
	self:SetMode("Isometric")
end

function CameraServiceClient.RequestSync(self: CameraServiceClient)
	sendPacket("requestSync")
end

function CameraServiceClient.Destroy(self: CameraServiceClient)
	if self.cameraController then
		self.cameraController:Destroy()
	end

	if self.characterJanitor then
		self.characterJanitor:Destroy()
	end

	if self.janitor then
		self.janitor:Destroy()
	end
end
type CameraServiceClient = typeof(CameraServiceClient) & {
	localPlayer: Player,
	cameraController: Camera.Camera,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	currentMode: CameraMode,
	sideViewConfig: SideViewConfig,
	character: Model?,
	snapSideViewOnNextTarget: boolean,
}

return CameraServiceClient :: CameraServiceClient
