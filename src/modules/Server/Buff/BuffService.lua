local require = require(script.Parent.loader).load(script)

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

local BuffConstants = require("BuffConstants")
local BuffShared = require("BuffShared")
local CharacterUtils = require("CharacterUtils")
local Maid = require("Maid")
local Octree = require("Octree")
local Promise = require("Promise")

local function fulfilledPromise(...): any
	local args = table.pack(...)
	return Promise.new(function(fulfill)
		fulfill(table.unpack(args, 1, args.n))
	end)
end
local Rx = require("Rx")
local Signal = require("Signal")
local Table = require("Table")
local buffUtils = require("buffUtils")

local BuffService = {}
BuffService.ServiceName = BuffConstants.SERVER_SERVICE_NAME

export type BuffRecord = buffUtils.BuffRecord

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type MaidClass = {
	GiveTask: (self: MaidClass, task: any) -> number,
	DoCleaning: (self: MaidClass) -> (),
	Destroy: (self: MaidClass) -> (),
	[any]: any,
}

type BuffAreaSource = {
	id: string,
	position: Vector3,
	radius: number,
	record: BuffRecord,
	node: any,
}

local function CoercePlayer(playerRaw: any): Player?
	if typeof(playerRaw) == "Instance" and playerRaw:IsA("Player") then
		return playerRaw
	end
	return nil
end

local function CoerceNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(valueRaw)
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end
	return math.clamp(value, minimum, maximum)
end

local function CoercePosition(valueRaw: any): Vector3?
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	if typeof(valueRaw) == "Instance" and valueRaw:IsA("BasePart") then
		return valueRaw.Position
	end
	if typeof(valueRaw) == "Instance" and valueRaw:IsA("Model") then
		return valueRaw:GetPivot().Position
	end
	return nil
end

local function getDefinitionFolders(): { { folder: Instance?, kind: string } }
	return {
		{
			folder = script.Parent:FindFirstChild(BuffConstants.DEFINITION_FOLDER_BUFFS),
			kind = BuffConstants.KIND_BUFF,
		},
		{
			folder = script.Parent:FindFirstChild(BuffConstants.DEFINITION_FOLDER_DEBUFFS),
			kind = BuffConstants.KIND_DEBUFF,
		},
	}
end

local function getRecordList(definitionRaw: any, kindFallback: string): { BuffRecord }
	if typeof(definitionRaw) ~= "table" then
		return {}
	end

	if typeof(definitionRaw.GetRecords) == "function" then
		return definitionRaw:GetRecords(kindFallback)
	end

	if typeof(definitionRaw.records) == "table" then
		return definitionRaw.records
	end

	if typeof(definitionRaw.name) == "string" or typeof(definitionRaw.id) == "string" then
		return {
			buffUtils.CreateRecord(kindFallback, definitionRaw, nil, nil, nil, nil, nil),
		}
	end

	return {}
end

local function createRejectedPromise(message: string)
	return Promise.rejected(message)
end

local function encodeReplicatedRecords(records: { BuffRecord }): string
	local replicatedRecords = buffUtils.CreateReplicatedRecords(records, os.clock())
	return HttpService:JSONEncode(replicatedRecords)
end

function BuffService.Init(self: BuffService, serviceBag: any)
	assert(not self._serviceBag, "Already initialized")

	self._serviceBag = assert(serviceBag, "No serviceBag")
	self._maid = Maid.new()
	self._playerMaids = {}
	self._runtimeByPlayer = {}
	self._definitions = BuffShared.New({
		definitionOnly = true,
	})
	self._areaOctree = Octree.new()
	self._areaSourcesById = {}
	self._maxAreaRadius = BuffConstants.DEFAULT_AREA_RADIUS

	self.PlayerRecordsChanged = Signal.new()
	self.RecordAdded = Signal.new()
	self.RecordChanged = Signal.new()
	self.RecordRemoved = Signal.new()
	self.AreaSourceAdded = Signal.new()
	self.AreaSourceRemoved = Signal.new()

	self._maid:GiveTask(self._definitions)
	self._maid:GiveTask(self.PlayerRecordsChanged)
	self._maid:GiveTask(self.RecordAdded)
	self._maid:GiveTask(self.RecordChanged)
	self._maid:GiveTask(self.RecordRemoved)
	self._maid:GiveTask(self.AreaSourceAdded)
	self._maid:GiveTask(self.AreaSourceRemoved)
	self._maid:GiveTask(Players.PlayerRemoving:Connect(function(player: Player)
		self:RemovePlayer(player)
	end))

	self:LoadDefinitions()
end

function BuffService.Start(self: BuffService)
	for _, player in Players:GetPlayers() do
		self:EnsurePlayerRuntime(player)
	end

	self._maid:GiveTask(Players.PlayerAdded:Connect(function(player: Player)
		self:EnsurePlayerRuntime(player)
	end))

	self._maid:GiveTask(Rx.timer(0, BuffConstants.AREA_SCAN_INTERVAL_SECONDS):Subscribe(function()
		self:ScanAreaSources()
	end))
end

function BuffService.LoadDefinitions(self: BuffService)
	for _, definitionFolder in getDefinitionFolders() do
		local folder = definitionFolder.folder
		if folder == nil then
			continue
		end

		for _, child in folder:GetChildren() do
			if child:IsA("ModuleScript") then
				self:LoadDefinitionModule(child, definitionFolder.kind)
			end
		end
	end
end

function BuffService.LoadDefinitionModule(self: BuffService, moduleScript: ModuleScript, kindFallback: string)
	local ok, definitionOrError = pcall(function()
		return require(moduleScript)
	end)

	if not ok then
		warn(`failed to load buff definition {moduleScript.Name}: {tostring(definitionOrError)}`)
		return
	end

	self:RegisterDefinition(definitionOrError, kindFallback)
end

function BuffService.RegisterDefinition(self: BuffService, definitionRaw: any, kindFallbackRaw: any?): number
	local kindFallback = buffUtils.CoerceKind(kindFallbackRaw)
	local records = getRecordList(definitionRaw, kindFallback)
	local registered = 0

	for _, record in records do
		self._definitions:AddRecord(record, kindFallback)
		registered += 1
	end

	return registered
end

function BuffService.EnsurePlayerRuntime(self: BuffService, playerRaw: any): any?
	local player = CoercePlayer(playerRaw)
	if player == nil then
		return nil
	end

	local existing = self._runtimeByPlayer[player]
	if existing ~= nil then
		return existing
	end

	local playerMaid = Maid.new()
	local runtime = BuffShared.New(self._serviceBag)
	self._playerMaids[player] = playerMaid
	self._runtimeByPlayer[player] = runtime

	playerMaid:GiveTask(runtime)
	playerMaid:GiveTask(runtime.RecordsChanged:Connect(function(records: { BuffRecord }, context: string)
		self:ReplicatePlayerRecords(player, records)
		self.PlayerRecordsChanged:Fire(player, records, context)
	end))
	playerMaid:GiveTask(runtime.RecordAdded:Connect(function(record: BuffRecord)
		self.RecordAdded:Fire(player, record)
	end))
	playerMaid:GiveTask(runtime.RecordChanged:Connect(function(record: BuffRecord)
		self.RecordChanged:Fire(player, record)
	end))
	playerMaid:GiveTask(runtime.RecordRemoved:Connect(function(record: BuffRecord, reason: string)
		self.RecordRemoved:Fire(player, record, reason)
	end))

	self:ReplicatePlayerRecords(player, runtime:GetRecords())

	return runtime
end

function BuffService.ReplicatePlayerRecords(self: BuffService, playerRaw: any, recordsRaw: any?)
	local player = CoercePlayer(playerRaw)
	if player == nil then
		return
	end

	local records = if typeof(recordsRaw) == "table" then recordsRaw :: { BuffRecord } else self:GetActive(player)
	local ok, encoded = pcall(encodeReplicatedRecords, records)
	if not ok then
		warn(`failed to replicate buff records for {player.Name}: {tostring(encoded)}`)
		return
	end

	player:SetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE, encoded)
end

function BuffService.RemovePlayer(self: BuffService, playerRaw: any)
	local player = CoercePlayer(playerRaw)
	if player == nil then
		return
	end

	local playerMaid = self._playerMaids[player]
	if playerMaid ~= nil then
		playerMaid:Destroy()
	end

	self._playerMaids[player] = nil
	self._runtimeByPlayer[player] = nil
	player:SetAttribute(BuffConstants.PLAYER_ACTIVE_RECORDS_ATTRIBUTE, nil)
end

function BuffService.GetDefinition(self: BuffService, nameRaw: any, kindRaw: any?): BuffRecord?
	return self._definitions:GetRecord(nameRaw, kindRaw)
end

function BuffService.GetDefinitions(self: BuffService, kindRaw: any?): { BuffRecord }
	return self._definitions:GetRecords(kindRaw)
end

function BuffService.ApplyDefinition(
	self: BuffService,
	playerRaw: any,
	nameRaw: any,
	kindRaw: any?,
	overridesRaw: any?
): BuffRecord?
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return nil
	end

	local definition = self:GetDefinition(nameRaw, kindRaw)
	if definition == nil then
		return nil
	end

	local overrides = {}
	if typeof(overridesRaw) == "table" then
		for key, value in overridesRaw :: { [string]: any } do
			overrides[key] = value
		end
	end
	if overrides.appliedAt == nil then
		overrides.appliedAt = os.clock()
	end

	return runtime:AddRecord(definition, kindRaw, overrides)
end

function BuffService.ApplyRecord(self: BuffService, playerRaw: any, recordRaw: any, overridesRaw: any?): BuffRecord?
	if typeof(recordRaw) ~= "table" then
		return nil
	end

	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return nil
	end

	local overrides = {}
	if typeof(overridesRaw) == "table" then
		for key, value in overridesRaw :: { [string]: any } do
			overrides[key] = value
		end
	end
	if overrides.appliedAt == nil then
		overrides.appliedAt = os.clock()
	end

	return runtime:AddRecord(recordRaw, nil, overrides)
end

function BuffService.ApplyBuff(self: BuffService, playerRaw: any, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self:ApplyDefinition(playerRaw, nameRaw, BuffConstants.KIND_BUFF, overridesRaw)
end

function BuffService.ApplyDebuff(self: BuffService, playerRaw: any, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self:ApplyDefinition(playerRaw, nameRaw, BuffConstants.KIND_DEBUFF, overridesRaw)
end

function BuffService.PromiseApplyBuff(self: BuffService, playerRaw: any, nameRaw: any, overridesRaw: any?)
	local record = self:ApplyBuff(playerRaw, nameRaw, overridesRaw)
	if record == nil then
		return createRejectedPromise("buff could not be applied")
	end
	return fulfilledPromise(record)
end

function BuffService.PromiseApplyDebuff(self: BuffService, playerRaw: any, nameRaw: any, overridesRaw: any?)
	local record = self:ApplyDebuff(playerRaw, nameRaw, overridesRaw)
	if record == nil then
		return createRejectedPromise("debuff could not be applied")
	end
	return fulfilledPromise(record)
end

function BuffService.AddBuff(
	self: BuffService,
	playerRaw: any,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord?
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return nil
	end

	return runtime:AddBuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffService.AddDebuff(
	self: BuffService,
	playerRaw: any,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord?
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return nil
	end

	return runtime:AddDebuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffService.Remove(
	self: BuffService,
	playerRaw: any,
	idOrNameRaw: any,
	reasonRaw: any?,
	kindRaw: any?
): boolean
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return false
	end

	return runtime:Remove(idOrNameRaw, reasonRaw, kindRaw)
end

function BuffService.PromiseRemove(self: BuffService, playerRaw: any, idOrNameRaw: any, reasonRaw: any?, kindRaw: any?)
	if not self:Remove(playerRaw, idOrNameRaw, reasonRaw, kindRaw) then
		return createRejectedPromise("buff could not be removed")
	end
	return fulfilledPromise(true)
end

function BuffService.Clear(self: BuffService, playerRaw: any, kindRaw: any?): number
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return 0
	end

	return runtime:Clear(kindRaw)
end

function BuffService.GetActive(self: BuffService, playerRaw: any, kindRaw: any?): { BuffRecord }
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return {}
	end

	return runtime:GetRecords(kindRaw)
end

function BuffService.ObservePlayerRecords(self: BuffService, playerRaw: any)
	local runtime = self:EnsurePlayerRuntime(playerRaw)
	if runtime == nil then
		return Rx.of({})
	end

	return runtime:ObserveRecords()
end

function BuffService.RegisterAreaSource(self: BuffService, areaRaw: any): BuffAreaSource?
	if typeof(areaRaw) ~= "table" then
		return nil
	end

	local area = areaRaw :: { [string]: any }
	local position = CoercePosition(area.position or area.instance or area.part or area.model)
	if position == nil then
		return nil
	end

	local radius = CoerceNumber(
		area.radius,
		BuffConstants.DEFAULT_AREA_RADIUS,
		BuffConstants.MIN_AREA_RADIUS,
		BuffConstants.MAX_AREA_RADIUS
	)
	local record = nil
	if area.record ~= nil then
		record = buffUtils.ApplyOverrides(area.record, area.overrides)
	elseif area.name ~= nil then
		record = self:GetDefinition(area.name, area.kind)
	end
	if record == nil then
		return nil
	end

	local id = buffUtils.Trim(area.id)
	if id == "" then
		id = `{record.id}:{math.floor(position.X)}:{math.floor(position.Y)}:{math.floor(position.Z)}`
	end

	self:RemoveAreaSource(id)

	local source = {
		id = id,
		position = position,
		radius = radius,
		record = record,
		node = nil,
	}
	source.node = self._areaOctree:CreateNode(position, source)
	self._areaSourcesById[id] = source
	self._maxAreaRadius = math.max(self._maxAreaRadius, radius)
	self.AreaSourceAdded:Fire(Table.copy(source))
	return source
end

function BuffService.RemoveAreaSource(self: BuffService, idRaw: any): boolean
	local id = buffUtils.Trim(idRaw)
	if id == "" then
		return false
	end

	local source = self._areaSourcesById[id]
	if source == nil then
		return false
	end

	if source.node ~= nil then
		source.node:Destroy()
	end

	self._areaSourcesById[id] = nil
	self.AreaSourceRemoved:Fire(id)
	return true
end

function BuffService.GetAreaSourcesNear(self: BuffService, positionRaw: any, radiusRaw: any?): { BuffAreaSource }
	local position = CoercePosition(positionRaw)
	if position == nil then
		return {}
	end

	local radius =
		CoerceNumber(radiusRaw, self._maxAreaRadius, BuffConstants.MIN_AREA_RADIUS, BuffConstants.MAX_AREA_RADIUS)
	local sources = self._areaOctree:RadiusSearch(position, radius)
	return Table.copy(sources)
end

function BuffService.ScanPlayerAreaSources(self: BuffService, playerRaw: any): number
	local player = CoercePlayer(playerRaw)
	if player == nil then
		return 0
	end

	local root = CharacterUtils.getPlayerRootPart(player)
	if root == nil then
		return 0
	end

	local applied = 0
	local sources = self:GetAreaSourcesNear(root.Position, self._maxAreaRadius)
	for _, source in sources do
		if (source.position - root.Position).Magnitude <= source.radius then
			if self:ApplyRecord(player, source.record) ~= nil then
				applied += 1
			end
		end
	end

	return applied
end

function BuffService.ScanAreaSources(self: BuffService)
	if next(self._areaSourcesById) == nil then
		return
	end

	for _, player in Players:GetPlayers() do
		self:ScanPlayerAreaSources(player)
	end
end

function BuffService.Destroy(self: BuffService)
	local players = {}
	for player in self._playerMaids do
		table.insert(players, player)
	end
	for _, player in players do
		self:RemovePlayer(player)
	end

	local areaSourceIds = {}
	for id in self._areaSourcesById do
		table.insert(areaSourceIds, id)
	end
	for _, id in areaSourceIds do
		self:RemoveAreaSource(id)
	end

	if self._maid ~= nil then
		self._maid:Destroy()
	end

	self._serviceBag = nil
end
type BuffService = typeof(BuffService) & {
	_serviceBag: any,
	_maid: MaidClass,
	_playerMaids: { [Player]: MaidClass },
	_runtimeByPlayer: { [Player]: any },
	_definitions: any,
	_areaOctree: any,
	_areaSourcesById: { [string]: BuffAreaSource },
	_maxAreaRadius: number,
	PlayerRecordsChanged: SignalObject,
	RecordAdded: SignalObject,
	RecordChanged: SignalObject,
	RecordRemoved: SignalObject,
	AreaSourceAdded: SignalObject,
	AreaSourceRemoved: SignalObject,
}

return BuffService :: BuffService
