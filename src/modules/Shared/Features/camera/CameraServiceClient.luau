--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Camera = require(script:FindFirstAncestor("game").Shared.Features.camera.classes.Camera)
local CameraServiceUtils = require(script:FindFirstAncestor("game").Shared.Features.camera.CameraServiceUtils)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require(script:FindFirstAncestor("game").Shared.NetShared.PacketPayload)
local CameraServicePackets = (require :: any)(script:FindFirstAncestor("game").Client.NetClient.Packets).CameraService

local function sendPacket(methodName: string, ...: any)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
		return
	end

	packet.send(PacketPayload.pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = CameraServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for CameraService`)
		return
	end

	packet.listen(function(payload: any)
		local handler = self[methodName]
		if typeof(handler) ~= "function" then
			return
		end

		local count, arguments = PacketPayload.unpack(payload)
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

	local defaultState = CameraServiceUtils.createDefaultState()
	self.currentMode = defaultState.mode
	self.sideViewConfig = defaultState.sideViewConfig
	self.snapSideViewOnNextTarget = true
	self.cameraController = Camera.new({
		SideView = {
			config = self.sideViewConfig,
			autoEnable = false,
		},
	})

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(character)
	end))

	if self.localPlayer.Character then
		self:onCharacterAdded(self.localPlayer.Character)
	end

	sendPacket("requestSync")
end

function CameraServiceClient.OnCharacterAdded(self: CameraServiceClient, character: Model)
	self.character = character
	self.snapSideViewOnNextTarget = true
	self.characterJanitor:Clean()
	self.cameraController:setSideViewCharacter(character)

	local childAddedConnection: RBXScriptConnection?
	childAddedConnection = character.ChildAdded:Connect(function()
		if self.currentMode ~= "SideView" then
			return
		end

		local target = CameraServiceUtils.resolveCharacterTarget(character)
		if target then
			self:applySideView()

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
		self:applySideView()
	end
end

function CameraServiceClient.ApplySideView(self: CameraServiceClient)
	self.cameraController:setSideViewCharacter(self.character)

	local target = CameraServiceUtils.resolveCharacterTarget(self.character)
	local snapToTarget = self.snapSideViewOnNextTarget == true and target ~= nil
	self.cameraController:useSideView(target, self.sideViewConfig, snapToTarget)

	if snapToTarget then
		self.snapSideViewOnNextTarget = false
	end
end

function CameraServiceClient.ApplyMode(self: CameraServiceClient, mode: any, sideViewConfig: any)
	local nextState: CameraState
	if sideViewConfig then
		nextState = CameraServiceUtils.createCameraState(mode, sideViewConfig)
	else
		local mergedSideViewConfig = CameraServiceUtils.mergeSideViewConfig(self.sideViewConfig, nil)
		nextState = CameraServiceUtils.createCameraState(mode, mergedSideViewConfig)
	end

	self.currentMode = nextState.mode
	self.sideViewConfig = nextState.sideViewConfig

	if nextState.mode == "SideView" then
		self.cameraController:configureSideView(nextState.sideViewConfig)
		self:applySideView()
		return
	end

	self.cameraController:disableSideView()

	local currentCamera = Workspace.CurrentCamera
	if currentCamera then
		currentCamera.CameraType = Enum.CameraType.Custom
	end
end

function CameraServiceClient.SetMode(self: CameraServiceClient, mode: CameraMode, sideViewConfig: SideViewConfig?)
	local configForRequest = CameraServiceUtils.mergeSideViewConfig(self.sideViewConfig, sideViewConfig)
	sendPacket("setMode", mode, configForRequest)
end

function CameraServiceClient.UseSideView(self: CameraServiceClient, sideViewConfig: SideViewConfig?)
	self:setMode("SideView", sideViewConfig)
end

function CameraServiceClient.UseFirstPerson(self: CameraServiceClient)
	self:setMode("FirstPerson")
end

function CameraServiceClient.UseIsometric(self: CameraServiceClient)
	self:setMode("Isometric")
end

function CameraServiceClient.RequestSync(self: CameraServiceClient)
	sendPacket("requestSync")
end

function CameraServiceClient.Destroy(self: CameraServiceClient)
	if self.cameraController then
		self.cameraController:destroy()
	end

	if self.characterJanitor then
		self.characterJanitor:Destroy()
	end

	if self.janitor then
		self.janitor:Destroy()
	end
end

CameraServiceClient.init = CameraServiceClient.Init
CameraServiceClient.onCharacterAdded = CameraServiceClient.OnCharacterAdded
CameraServiceClient.applySideView = CameraServiceClient.ApplySideView
CameraServiceClient.applyMode = CameraServiceClient.ApplyMode
CameraServiceClient.setMode = CameraServiceClient.SetMode
CameraServiceClient.useSideView = CameraServiceClient.UseSideView
CameraServiceClient.useFirstPerson = CameraServiceClient.UseFirstPerson
CameraServiceClient.useIsometric = CameraServiceClient.UseIsometric
CameraServiceClient.requestSync = CameraServiceClient.RequestSync
CameraServiceClient.destroy = CameraServiceClient.Destroy

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
