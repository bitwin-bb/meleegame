--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local Networker = require(script:FindFirstAncestor("game").Shared.Modules.Networking.Networker)
local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Signal = require(ReplicatedStorage.Packages.Signal)
local Sift = require(ReplicatedStorage.Packages.Sift)
local CameraShaker = require(ReplicatedStorage.Packages.EZCameraShake)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local EyeOfCthulhuPresentation = require(script:FindFirstAncestor("game").Shared.Classes.Boss.EyeOfCthulhu.Presentation)

type BossSnapshot = BossServiceUtils.BossSnapshot
type BossServiceState = BossServiceUtils.BossServiceState

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> RBXScriptConnection,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type CameraShakerObject = {
	Start: (self: CameraShakerObject) -> (),
	Stop: (self: CameraShakerObject) -> (),
	ShakeOnce: (
		self: CameraShakerObject,
		magnitude: number,
		roughness: number,
		fadeInTime: number?,
		fadeOutTime: number?,
		posInfluence: Vector3?,
		rotInfluence: Vector3?
	) -> (),
}

type PresentationModule = {
	createRuntime: (modelRaw: any, snapshot: BossSnapshot, cameraShaker: CameraShakerObject?) -> any,
	applySnapshot: (runtime: any, snapshot: BossSnapshot) -> (),
	step: (runtime: any, dt: number) -> (),
	destroy: (runtime: any) -> (),
}

type BossVisualRuntime = {
	snapshot: BossSnapshot,
	model: Model?,
	presentationModule: PresentationModule?,
	presentationRuntime: any?,
}

local BossServiceClient = {}

local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local CAMERA_SHAKE_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local PRESENTATION_MODULES = {
	EyeOfCthulhu = EyeOfCthulhuPresentation,
}

local function appendUniqueOrderedId(orderedIds: { string }, runtimeId: string): { string }
	if Sift.Array.includes(orderedIds, runtimeId) then
		return orderedIds
	end
	return Sift.Array.append(orderedIds, runtimeId)
end

local function trim(valueRaw: any): string
	return BossServiceUtils.trim(valueRaw)
end

local function pushAnnouncement(textRaw: any)
	local text = trim(textRaw)
	if text == "" then
		return
	end

	local didNotify = false
	pcall(function()
		StarterGui:SetCore("SendNotification", {
			Title = "Boss",
			Text = text,
			Duration = 4,
		})
		didNotify = true
	end)

	if didNotify then
		return
	end

	pcall(function()
		StarterGui:SetCore("ChatMakeSystemMessage", {
			Text = text,
			Color = Color3.fromRGB(219, 88, 88),
		})
	end)
end

function BossServiceClient.ResolvePresentationModule(self: BossServiceClient, snapshot: BossSnapshot): PresentationModule?
	local definition = BossServiceUtils.getRegistryEntryById(snapshot.bossId)
	if definition == nil then
		return nil
	end

	local presentationModule = PRESENTATION_MODULES[definition.presentationId]
	if typeof(presentationModule) == "table" then
		return presentationModule :: PresentationModule
	end
	return nil
end

function BossServiceClient.ResolveRuntimeModel(self: BossServiceClient, runtimeIdRaw: any): Model?
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return nil
	end

	local runtimeFolder = WorkspaceFolders.findFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
	if runtimeFolder == nil then
		return nil
	end

	for _, child in runtimeFolder:GetChildren() do
		if child:IsA("Model") and child:GetAttribute(BossServiceUtils.RUNTIME_ID_ATTRIBUTE) == runtimeId then
			return child
		end
	end

	return nil
end

function BossServiceClient.DestroyVisual(self: BossServiceClient, runtimeIdRaw: any)
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return
	end

	local visual = self.visualsById[runtimeId]
	if visual == nil then
		return
	end

	self.visualsById[runtimeId] = nil
	if visual.presentationRuntime ~= nil and visual.presentationModule ~= nil then
		visual.presentationModule.destroy(visual.presentationRuntime)
	end
end

function BossServiceClient.EnsureVisual(self: BossServiceClient, snapshot: BossSnapshot): BossVisualRuntime?
	local runtimeId = snapshot.id
	local visual = self.visualsById[runtimeId]
	if visual == nil then
		visual = {
			snapshot = snapshot,
			model = nil,
			presentationModule = self:resolvePresentationModule(snapshot),
			presentationRuntime = nil,
		}
		self.visualsById[runtimeId] = visual
	else
		visual.snapshot = snapshot
		if visual.presentationModule == nil then
			visual.presentationModule = self:resolvePresentationModule(snapshot)
		end
	end

	if visual.presentationModule == nil then
		return visual
	end

	local model = self:resolveRuntimeModel(runtimeId)
	if model ~= visual.model then
		if visual.presentationRuntime ~= nil then
			visual.presentationModule.destroy(visual.presentationRuntime)
			visual.presentationRuntime = nil
		end
		visual.model = model
	end

	if visual.presentationRuntime == nil and visual.model ~= nil then
		visual.presentationRuntime = visual.presentationModule.createRuntime(visual.model, snapshot, self.cameraShaker)
	end

	if visual.presentationRuntime ~= nil then
		visual.presentationModule.applySnapshot(visual.presentationRuntime, snapshot)
	end

	return visual
end

function BossServiceClient.PushStateChanged(self: BossServiceClient)
	self.stateChanged:Fire(self:getState())
end

function BossServiceClient.ApplyState(self: BossServiceClient, stateRaw: any)
	local nextState = BossServiceUtils.sanitizeState(stateRaw, self.state)
	local previousIds = Sift.Array.copy(self.state.orderedIds)
	self.state = nextState
	self.isReadyFlag = true

	local nextLookup = Sift.Set.fromArray(nextState.orderedIds)

	for _, runtimeId in previousIds do
		if nextLookup[runtimeId] ~= true then
			self:destroyVisual(runtimeId)
		end
	end

	for _, runtimeId in nextState.orderedIds do
		local snapshot = nextState.byId[runtimeId]
		if snapshot ~= nil then
			self:ensureVisual(snapshot)
		end
	end

	self:pushStateChanged()
end

function BossServiceClient.UpsertSnapshot(self: BossServiceClient, snapshotRaw: any)
	local existingSnapshot = nil :: BossSnapshot?
	local runtimeId = if typeof(snapshotRaw) == "table" then (snapshotRaw :: any).id else nil
	if typeof(runtimeId) == "string" then
		existingSnapshot = self.state.byId[runtimeId]
	end

	local snapshot = BossServiceUtils.sanitizeSnapshot(snapshotRaw, existingSnapshot)
	if snapshot == nil then
		return
	end

	self.state = {
		byId = Sift.Dictionary.set(self.state.byId, snapshot.id, snapshot),
		orderedIds = appendUniqueOrderedId(self.state.orderedIds, snapshot.id),
		updatedAt = os.clock(),
	}
	self.isReadyFlag = true
	self:ensureVisual(snapshot)
	self:pushStateChanged()
end

function BossServiceClient.OnBossAdded(self: BossServiceClient, snapshotRaw: any)
	self:upsertSnapshot(snapshotRaw)
end

function BossServiceClient.OnBossUpdated(self: BossServiceClient, snapshotRaw: any)
	self:upsertSnapshot(snapshotRaw)
end

function BossServiceClient.OnBossRemoved(self: BossServiceClient, runtimeIdRaw: any)
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return
	end

	self.state = {
		byId = Sift.Dictionary.removeKey(self.state.byId, runtimeId),
		orderedIds = Sift.Array.filter(self.state.orderedIds, function(existingId: string): boolean
			return existingId ~= runtimeId
		end),
		updatedAt = os.clock(),
	}
	self:destroyVisual(runtimeId)
	self:pushStateChanged()
end

function BossServiceClient.OnAnnouncement(self: BossServiceClient, payloadRaw: any)
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {}
	local text = trim((payload :: any).text)
	if text == "" then
		return
	end

	pushAnnouncement(text)
	self.announcementReceived:Fire(payload)
end

function BossServiceClient.RequestSync(self: BossServiceClient)
	self.networker:fire(BossServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function BossServiceClient.RequestManualSummon(self: BossServiceClient, bossTokenRaw: any, optionsRaw: any?)
	self.networker:fire(BossServiceUtils.NETWORK_METHOD_REQUEST_MANUAL_SUMMON, bossTokenRaw, optionsRaw)
end

function BossServiceClient.GetState(self: BossServiceClient): BossServiceState
	return BossServiceUtils.cloneState(self.state)
end

function BossServiceClient.IsReady(self: BossServiceClient): boolean
	return self.isReadyFlag == true
end

function BossServiceClient.StepVisuals(self: BossServiceClient, dtRaw: any)
	local dt = BossServiceUtils.sanitizeNumber(dtRaw, 1 / 60, 0, 1)
	for runtimeId, visual in self.visualsById do
		local snapshot = self.state.byId[runtimeId]
		if snapshot == nil then
			self:destroyVisual(runtimeId)
			continue
		end

		local ensuredVisual = self:ensureVisual(snapshot)
		if ensuredVisual ~= nil and ensuredVisual.presentationRuntime ~= nil and ensuredVisual.presentationModule ~= nil then
			ensuredVisual.presentationModule.step(ensuredVisual.presentationRuntime, dt)
		end
	end
end

function BossServiceClient.Init(self: BossServiceClient)
	self.localPlayer = Players.LocalPlayer
	self.networker = Networker.client.new("BossService", self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.announcementReceived = Signal.new()
	self.state = BossServiceUtils.createDefaultState()
	self.visualsById = {}
	self.isReadyFlag = false

	local cameraShakerOk, cameraShakerOrError = pcall(function()
		local cameraShaker = CameraShaker.new(CAMERA_SHAKE_RENDER_PRIORITY, function(shakeCFrame: CFrame)
			local camera = Workspace.CurrentCamera
			if camera ~= nil then
				camera.CFrame = camera.CFrame * shakeCFrame
			end
		end) :: any
		return cameraShaker :: CameraShakerObject
	end)
	if cameraShakerOk then
		self.cameraShaker = cameraShakerOrError :: CameraShakerObject
		pcall(function()
			(self.cameraShaker :: CameraShakerObject):Start()
		end)
	else
		self.cameraShaker = nil
	end

	self.janitor:GiveChore(RunService.RenderStepped:Connect(function(dt: number)
		self:stepVisuals(dt)
	end))
	self.janitor:GiveChore(function()
		for runtimeId in self.visualsById do
			self:destroyVisual(runtimeId)
		end
	end)
	self.janitor:GiveChore(function()
		if self.cameraShaker ~= nil then
			pcall(function()
				(self.cameraShaker :: CameraShakerObject):Stop()
			end)
			self.cameraShaker = nil
		end
	end)
	self.janitor:GiveChore(function()
		self.stateChanged:Destroy()
	end)
	self.janitor:GiveChore(function()
		self.announcementReceived:Destroy()
	end)
	self.janitor:GiveChore(function()
		self.networker:destroy()
	end)

	self:requestSync()
end

function BossServiceClient.Destroy(self: BossServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
end

BossServiceClient.resolvePresentationModule = BossServiceClient.ResolvePresentationModule
BossServiceClient.resolveRuntimeModel = BossServiceClient.ResolveRuntimeModel
BossServiceClient.destroyVisual = BossServiceClient.DestroyVisual
BossServiceClient.ensureVisual = BossServiceClient.EnsureVisual
BossServiceClient.pushStateChanged = BossServiceClient.PushStateChanged
BossServiceClient.applyState = BossServiceClient.ApplyState
BossServiceClient.upsertSnapshot = BossServiceClient.UpsertSnapshot
BossServiceClient.onBossAdded = BossServiceClient.OnBossAdded
BossServiceClient.onBossUpdated = BossServiceClient.OnBossUpdated
BossServiceClient.onBossRemoved = BossServiceClient.OnBossRemoved
BossServiceClient.onAnnouncement = BossServiceClient.OnAnnouncement
BossServiceClient.requestSync = BossServiceClient.RequestSync
BossServiceClient.requestManualSummon = BossServiceClient.RequestManualSummon
BossServiceClient.getState = BossServiceClient.GetState
BossServiceClient.isReady = BossServiceClient.IsReady
BossServiceClient.stepVisuals = BossServiceClient.StepVisuals
BossServiceClient.init = BossServiceClient.Init
BossServiceClient.destroy = BossServiceClient.Destroy

type BossServiceClient = typeof(BossServiceClient) & {
	localPlayer: Player,
	networker: Networker.Client,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	announcementReceived: SignalObject,
	state: BossServiceState,
	visualsById: { [string]: BossVisualRuntime },
	cameraShaker: CameraShakerObject?,
	isReadyFlag: boolean,
}

return BossServiceClient :: BossServiceClient

