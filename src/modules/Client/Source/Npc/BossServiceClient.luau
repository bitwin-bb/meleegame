local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")
local Workspace = game:GetService("Workspace")

local GameRoot = script:FindFirstAncestor("game")
local SharedRealmRoot = if GameRoot ~= nil then GameRoot:FindFirstChild("Shared") else nil
local SharedRoot = if SharedRealmRoot ~= nil then SharedRealmRoot:FindFirstChild("Source") else nil

local BossServiceUtils = require("BossServiceUtils")
local CameraShaker = require("EZCameraShake")
local Janitor: any = require(ReplicatedStorage.Packages.Janitor)
local PacketPayload = require("PacketPayload")
local ServiceBag = require("ServiceBag")
local BossServicePackets = require("NetPacketsShared").BossService

local function sendPacket(methodName: string, ...: any)
	local packet = BossServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BossService`)
		return
	end

	packet.send(PacketPayload.Pack(...))
end

local function bindPacket(self: any, methodName: string)
	local packet = BossServicePackets[methodName]
	if packet == nil then
		warn(`missing ByteNet packet {methodName} for BossService`)
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
	bindPacket(self, "applyState")
	bindPacket(self, "onAnnouncement")
	bindPacket(self, "onBossAdded")
	bindPacket(self, "onBossRemoved")
	bindPacket(self, "onBossUpdated")
	bindPacket(self, "requestManualSummon")
	bindPacket(self, "requestSync")
end

local Sift: any = require(ReplicatedStorage.Packages.Sift)
local Signal = require("Signal")
local WorkspaceFolders = require("WorkspaceFolders")

type BossSnapshot = BossServiceUtils.BossSnapshot
type BossServiceState = BossServiceUtils.BossServiceState

type SignalObject = Signal.Signal<...any>

type JanitorClass = any

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
	CreateRuntime: (modelRaw: any, snapshot: BossSnapshot, cameraShaker: CameraShakerObject?) -> any,
	ApplySnapshot: (runtime: any, snapshot: BossSnapshot) -> (),
	Step: (runtime: any, dt: number) -> (),
	Destroy: (runtime: any) -> (),
}

type PresentationGetter = () -> PresentationModule?

type BossVisualRuntime = {
	snapshot: BossSnapshot,
	model: Model?,
	presentationModule: PresentationModule?,
	presentationRuntime: any?,
}

local BossServiceClient = {}
BossServiceClient.ServiceName = "BossServiceClient"

local BOSS_RUNTIME_FOLDER_NAME = "BossRuntime"
local CAMERA_SHAKE_RENDER_PRIORITY = Enum.RenderPriority.Camera.Value + 1

local presentationModulesById: { [string]: PresentationModule } = {}
local warnedPresentationModuleFailures: { [string]: boolean } = {}

local function warnPresentationModuleFailure(presentationId: string, message: string)
	if warnedPresentationModuleFailures[presentationId] == true then
		return
	end

	warnedPresentationModuleFailures[presentationId] = true
	warn(`[BossServiceClient] {message}`)
end

local function getNestedModule(root: Instance?, path: { string }): ModuleScript?
	if root == nil then
		return nil
	end

	local current = root
	for _, childName in path do
		local child = current:FindFirstChild(childName)
		if child == nil then
			return nil
		end
		current = child
	end

	if current:IsA("ModuleScript") then
		return current
	end
	return nil
end

local function getEyeOfCthulhuPresentationModule(): PresentationModule?
	local cached = presentationModulesById.EyeOfCthulhu
	if cached ~= nil then
		return cached
	end

	local moduleScript = getNestedModule(SharedRoot, { "EyeOfCthulhuBoss", "Presentation" })
	if moduleScript == nil then
		return nil
	end

	local ok, moduleOrError = pcall(function()
		return require(moduleScript :: any)
	end)
	if not ok then
		warnPresentationModuleFailure(
			"EyeOfCthulhu",
			`failed to load EyeOfCthulhu presentation module: {moduleOrError}`
		)
		return nil
	end
	if typeof(moduleOrError) ~= "table" then
		warnPresentationModuleFailure("EyeOfCthulhu", "EyeOfCthulhu presentation module did not return a table")
		return nil
	end

	presentationModulesById.EyeOfCthulhu = moduleOrError :: PresentationModule
	return presentationModulesById.EyeOfCthulhu
end

local PRESENTATION_MODULES: { [string]: PresentationGetter } = {
	EyeOfCthulhu = getEyeOfCthulhuPresentationModule,
}

local function appendUniqueOrderedId(orderedIds: { string }, runtimeId: string): { string }
	if Sift.Array.includes(orderedIds, runtimeId) then
		return orderedIds
	end
	return Sift.Array.append(orderedIds, runtimeId)
end

local function trim(valueRaw: any): string
	return BossServiceUtils.Trim(valueRaw)
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

function BossServiceClient.GetPresentationModule(_self: BossServiceClient, snapshot: BossSnapshot): PresentationModule?
	local definition = BossServiceUtils.GetRegistryEntryById(snapshot.bossId)
	if definition == nil then
		return nil
	end

	local presentationGetter = PRESENTATION_MODULES[definition.presentationId]
	if typeof(presentationGetter) == "function" then
		return presentationGetter()
	end
	return nil
end

function BossServiceClient.GetRuntimeModel(_self: BossServiceClient, runtimeIdRaw: any): Model?
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return nil
	end

	local runtimeFolder = WorkspaceFolders.FindFolderInGameOrWorkspace(BOSS_RUNTIME_FOLDER_NAME)
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
		visual.presentationModule.Destroy(visual.presentationRuntime)
	end
end

function BossServiceClient.EnsureVisual(self: BossServiceClient, snapshot: BossSnapshot): BossVisualRuntime?
	local runtimeId = snapshot.id
	local visual = self.visualsById[runtimeId]
	if visual == nil then
		visual = {
			snapshot = snapshot,
			model = nil,
			presentationModule = self:GetPresentationModule(snapshot),
			presentationRuntime = nil,
		}
		self.visualsById[runtimeId] = visual
	else
		visual.snapshot = snapshot
		if visual.presentationModule == nil then
			visual.presentationModule = self:GetPresentationModule(snapshot)
		end
	end

	if visual.presentationModule == nil then
		return visual
	end

	local model = self:GetRuntimeModel(runtimeId)
	if model ~= visual.model then
		if visual.presentationRuntime ~= nil then
			visual.presentationModule.Destroy(visual.presentationRuntime)
			visual.presentationRuntime = nil
		end
		visual.model = model
	end

	if visual.presentationRuntime == nil and visual.model ~= nil then
		visual.presentationRuntime = visual.presentationModule.CreateRuntime(visual.model, snapshot, self.cameraShaker)
	end

	if visual.presentationRuntime ~= nil then
		visual.presentationModule.ApplySnapshot(visual.presentationRuntime, snapshot)
	end

	return visual
end

function BossServiceClient.PushStateChanged(self: BossServiceClient)
	self.stateChanged:Fire(self:GetState())
end

function BossServiceClient.ApplyState(self: BossServiceClient, stateRaw: any)
	local nextState = BossServiceUtils.CoerceState(stateRaw, self.state)
	local previousIds = Sift.Array.copy(self.state.orderedIds)
	self.state = nextState
	self.isReadyFlag = true

	local nextLookup = Sift.Set.fromArray(nextState.orderedIds)

	for _, runtimeId in previousIds do
		if nextLookup[runtimeId] ~= true then
			self:DestroyVisual(runtimeId)
		end
	end

	for _, runtimeId in nextState.orderedIds do
		local snapshot = nextState.byId[runtimeId]
		if snapshot ~= nil then
			self:EnsureVisual(snapshot)
		end
	end

	self:PushStateChanged()
end

function BossServiceClient.UpsertSnapshot(self: BossServiceClient, snapshotRaw: any)
	local existingSnapshot = nil :: BossSnapshot?
	local runtimeId = if typeof(snapshotRaw) == "table" then (snapshotRaw :: any).id else nil
	if typeof(runtimeId) == "string" then
		existingSnapshot = self.state.byId[runtimeId]
	end

	local snapshot = BossServiceUtils.CoerceSnapshot(snapshotRaw, existingSnapshot)
	if snapshot == nil then
		return
	end

	self.state = {
		byId = Sift.Dictionary.set(self.state.byId, snapshot.id, snapshot),
		orderedIds = appendUniqueOrderedId(self.state.orderedIds, snapshot.id),
		updatedAt = os.clock(),
	}
	self.isReadyFlag = true
	self:EnsureVisual(snapshot)
	self:PushStateChanged()
end

function BossServiceClient.OnBossAdded(self: BossServiceClient, snapshotRaw: any)
	self:UpsertSnapshot(snapshotRaw)
end

function BossServiceClient.OnBossUpdated(self: BossServiceClient, snapshotRaw: any)
	self:UpsertSnapshot(snapshotRaw)
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
	self:DestroyVisual(runtimeId)
	self:PushStateChanged()
end

function BossServiceClient.OnAnnouncement(self: BossServiceClient, payloadRaw: any)
	local payload = if typeof(payloadRaw) == "table" then payloadRaw else {} :: any
	local text = trim((payload :: any).text)
	if text == "" then
		return
	end

	pushAnnouncement(text)
	self.announcementReceived:Fire(payload)
end

function BossServiceClient.RequestSync(_self: BossServiceClient)
	sendPacket(BossServiceUtils.NETWORK_METHOD_REQUEST_SYNC)
end

function BossServiceClient.RequestManualSummon(_self: BossServiceClient, bossTokenRaw: any, optionsRaw: any?)
	sendPacket(BossServiceUtils.NETWORK_METHOD_REQUEST_MANUAL_SUMMON, bossTokenRaw, optionsRaw)
end

function BossServiceClient.GetState(self: BossServiceClient): BossServiceState
	return BossServiceUtils.CloneState(self.state)
end

function BossServiceClient.IsReady(self: BossServiceClient): boolean
	return self.isReadyFlag == true
end

function BossServiceClient.StepVisuals(self: BossServiceClient, dtRaw: any)
	local dt = BossServiceUtils.CoerceNumber(dtRaw, 1 / 60, 0, 1)
	for runtimeId in self.visualsById do
		local snapshot = self.state.byId[runtimeId]
		if snapshot == nil then
			self:DestroyVisual(runtimeId)
			continue
		end

		local ensuredVisual = self:EnsureVisual(snapshot)
		if
			ensuredVisual ~= nil
			and ensuredVisual.presentationRuntime ~= nil
			and ensuredVisual.presentationModule ~= nil
		then
			ensuredVisual.presentationModule.Step(ensuredVisual.presentationRuntime, dt)
		end
	end
end

function BossServiceClient.Init(self: BossServiceClient, serviceBag: ServiceBag.ServiceBag?)
	if serviceBag ~= nil then
		self._serviceBag = serviceBag
	end
	self.localPlayer = Players.LocalPlayer
	bindPackets(self)
	self.janitor = Janitor.new()
	self.stateChanged = Signal.new()
	self.announcementReceived = Signal.new()
	self.state = BossServiceUtils.CreateDefaultState()
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
		self:StepVisuals(dt)
	end))
	self.janitor:GiveChore(function()
		for runtimeId in pairs(self.visualsById) do
			self:DestroyVisual(runtimeId)
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

	self:RequestSync()
end

function BossServiceClient.Destroy(self: BossServiceClient)
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end
	self._serviceBag = nil
end

type BossServiceClient = typeof(BossServiceClient) & {
	_serviceBag: ServiceBag.ServiceBag?,
	localPlayer: Player,
	janitor: JanitorClass,
	stateChanged: SignalObject,
	announcementReceived: SignalObject,
	state: BossServiceState,
	visualsById: { [string]: BossVisualRuntime },
	cameraShaker: CameraShakerObject?,
	isReadyFlag: boolean,
}

return BossServiceClient :: BossServiceClient
