--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Networker = require(ReplicatedStorage.Packages.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Camera = require(ReplicatedStorage.Shared.Classes.Camera)
local CameraServiceUtils = require(ReplicatedStorage.Shared.Services.CameraService.CameraServiceUtils)

type CameraMode = CameraServiceUtils.CameraMode
type SideViewConfig = CameraServiceUtils.SideViewConfig
type CameraState = CameraServiceUtils.CameraState

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

local CameraServiceClient = {}

function CameraServiceClient.init(self: CameraServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("CameraService", self)
	self.janitor = Janitor.new()
	self.characterJanitor = Janitor.new()
	self.janitor:GiveChore(self.characterJanitor)

	local defaultState = CameraServiceUtils.createDefaultState()
	self.currentMode = defaultState.mode
	self.sideViewConfig = defaultState.sideViewConfig
	self.cameraController = Camera.new({
		SideView = {
			config = self.sideViewConfig,
			autoEnable = false,
		},
	})

	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)

	self.janitor:GiveChore(self.localPlayer.CharacterAdded:Connect(function(character)
		self:onCharacterAdded(character)
	end))

	if self.localPlayer.Character then
		self:onCharacterAdded(self.localPlayer.Character)
	end

	self.networker:fire("requestSync")
end

function CameraServiceClient.onCharacterAdded(self: CameraServiceClient, character: Model)
	self.character = character
	self.characterJanitor:Clean()

	local childAddedConnection: RBXScriptConnection?
	childAddedConnection = character.ChildAdded:Connect(function()
		if self.currentMode ~= "SideView" then
			return
		end

		local target = CameraServiceUtils.resolveCharacterTarget(character)
		if target then
			self.cameraController:useSideView(target, self.sideViewConfig)

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

function CameraServiceClient.applySideView(self: CameraServiceClient)
	local target = CameraServiceUtils.resolveCharacterTarget(self.character)
	if not target then
		return
	end

	self.cameraController:useSideView(target, self.sideViewConfig)
end

function CameraServiceClient.applyMode(self: CameraServiceClient, mode: any, sideViewConfig: any)
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

function CameraServiceClient.setMode(self: CameraServiceClient, mode: CameraMode, sideViewConfig: SideViewConfig?)
	local configForRequest = CameraServiceUtils.mergeSideViewConfig(self.sideViewConfig, sideViewConfig)
	self.networker:fire("setMode", mode, configForRequest)
end

function CameraServiceClient.useSideView(self: CameraServiceClient, sideViewConfig: SideViewConfig?)
	self:setMode("SideView", sideViewConfig)
end

function CameraServiceClient.useFirstPerson(self: CameraServiceClient)
	self:setMode("FirstPerson")
end

function CameraServiceClient.useIsometric(self: CameraServiceClient)
	self:setMode("Isometric")
end

function CameraServiceClient.requestSync(self: CameraServiceClient)
	self.networker:fire("requestSync")
end

function CameraServiceClient.destroy(self: CameraServiceClient)
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

type CameraServiceClient = typeof(CameraServiceClient) & {
	networker: Networker.Client,
	localPlayer: Player,
	cameraController: Camera.Camera,
	janitor: JanitorClass,
	characterJanitor: JanitorClass,
	currentMode: CameraMode,
	sideViewConfig: SideViewConfig,
	character: Model?,
}

return CameraServiceClient :: CameraServiceClient
