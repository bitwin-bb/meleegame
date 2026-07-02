local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BuffConstants = require("BuffConstants")
local BuffShared = require("BuffShared")
local CharacterUtils = require("CharacterUtils")
local Maid = require("Maid")
local Signal = require("Signal")
local buffUtils = require("BuffUtils")

local BuffHandlerClient = {}
BuffHandlerClient.__index = BuffHandlerClient

export type BuffRecord = buffUtils.BuffRecord

type SignalObject = {
	Connect: (self: SignalObject, callback: (...any) -> ()) -> any,
	Fire: (self: SignalObject, ...any) -> (),
	Destroy: (self: SignalObject) -> (),
}

type MaidClass = {
	GiveTask: (self: MaidClass, chore: any) -> number,
	Destroy: (self: MaidClass) -> (),
}

local function getDefinitionFolders(): { { folder: Instance?, kind: string } }
	local buffRoot = script.Parent.Parent
	return {
		{
			folder = buffRoot:FindFirstChild(BuffConstants.DEFINITION_FOLDER_BUFFS),
			kind = BuffConstants.KIND_BUFF,
		},
		{
			folder = buffRoot:FindFirstChild(BuffConstants.DEFINITION_FOLDER_DEBUFFS),
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

local function runEffectCallback(callbackRaw: any, context: { [string]: any }, record: BuffRecord, self: any)
	if typeof(callbackRaw) ~= "function" then
		return
	end

	local ok, err = pcall(callbackRaw, context, record, self)
	if not ok then
		warn(`buff effect callback failed: {tostring(err)}`)
	end
end

function BuffHandlerClient.new(): BuffHandlerClient
	local self = setmetatable({}, BuffHandlerClient)
	self:Init()
	return self
end

function BuffHandlerClient.Init(self: BuffHandlerClient)
	if self.maid ~= nil then
		return
	end

	self.localPlayer = Players.LocalPlayer
	self.maid = Maid.new()
	self.definitions = BuffShared.New({
		definitionOnly = true,
	})
	self.active = BuffShared.New()
	self.definitionChanged = Signal.new()
	self.activeChanged = Signal.new()
	self.buffAdded = Signal.new()
	self.buffChanged = Signal.new()
	self.buffRemoved = Signal.new()

	self.maid:GiveTask(self.definitions)
	self.maid:GiveTask(self.active)
	self.maid:GiveTask(self.definitionChanged)
	self.maid:GiveTask(self.activeChanged)
	self.maid:GiveTask(self.buffAdded)
	self.maid:GiveTask(self.buffChanged)
	self.maid:GiveTask(self.buffRemoved)

	self.maid:GiveTask(self.active.RecordAdded:Connect(function(record: BuffRecord)
		self:HandleRecordAdded(record)
	end))
	self.maid:GiveTask(self.active.RecordChanged:Connect(function(record: BuffRecord)
		self:HandleRecordChanged(record)
	end))
	self.maid:GiveTask(self.active.RecordRemoved:Connect(function(record: BuffRecord, reason: string)
		self:HandleRecordRemoved(record, reason)
	end))
	self.maid:GiveTask(self.active.RecordsChanged:Connect(function(records: { BuffRecord }, context: string)
		self.activeChanged:Fire(records, context)
	end))
	self.maid:GiveTask(self.definitions.RecordsChanged:Connect(function(records: { BuffRecord }, context: string)
		self.definitionChanged:Fire(records, context)
	end))

	self:LoadDefinitions()
end

function BuffHandlerClient.LoadDefinitions(self: BuffHandlerClient)
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

function BuffHandlerClient.LoadDefinitionModule(
	self: BuffHandlerClient,
	moduleScript: ModuleScript,
	kindFallback: string
)
	local ok, definitionOrError = pcall(function()
		return require(moduleScript)
	end)

	if not ok then
		warn(`failed to load buff definition {moduleScript.Name}: {tostring(definitionOrError)}`)
		return
	end

	self:RegisterDefinition(definitionOrError, kindFallback)
end

function BuffHandlerClient.RegisterDefinition(
	self: BuffHandlerClient,
	definitionRaw: any,
	kindFallbackRaw: any?
): number
	local kindFallback = buffUtils.CoerceKind(kindFallbackRaw)
	local records = getRecordList(definitionRaw, kindFallback)
	local registered = 0

	for _, record in records do
		self.definitions:AddRecord(record, kindFallback)
		registered += 1
	end

	return registered
end

function BuffHandlerClient.CreateContext(self: BuffHandlerClient): { [string]: any }
	local player = self.localPlayer or Players.LocalPlayer
	local character = if player ~= nil then player.Character else nil
	local humanoid = if player ~= nil then CharacterUtils.getPlayerHumanoid(player) else nil

	return {
		player = player,
		character = character,
		humanoid = humanoid,
		handler = self,
	}
end

function BuffHandlerClient.HandleRecordAdded(self: BuffHandlerClient, record: BuffRecord)
	local context = self:CreateContext()
	runEffectCallback(record.effects.onAdded or record.effects.OnAdded, context, record, self)
	self.buffAdded:Fire(record)
end

function BuffHandlerClient.HandleRecordChanged(self: BuffHandlerClient, record: BuffRecord)
	local context = self:CreateContext()
	runEffectCallback(record.effects.onChanged or record.effects.OnChanged, context, record, self)
	self.buffChanged:Fire(record)
end

function BuffHandlerClient.HandleRecordRemoved(self: BuffHandlerClient, record: BuffRecord, reason: string)
	local context = self:CreateContext()
	context.reason = reason
	runEffectCallback(record.effects.onRemoved or record.effects.OnRemoved, context, record, self)
	self.buffRemoved:Fire(record, reason)
end

function BuffHandlerClient.GetDefinition(self: BuffHandlerClient, nameRaw: any, kindRaw: any?): BuffRecord?
	return self.definitions:GetRecord(nameRaw, kindRaw)
end

function BuffHandlerClient.ApplyDefinition(
	self: BuffHandlerClient,
	nameRaw: any,
	kindRaw: any?,
	overridesRaw: any?
): BuffRecord?
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

	return self.active:AddRecord(definition, kindRaw, overrides)
end

function BuffHandlerClient.ApplyBuff(self: BuffHandlerClient, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self:ApplyDefinition(nameRaw, BuffConstants.KIND_BUFF, overridesRaw)
end

function BuffHandlerClient.ApplyDebuff(self: BuffHandlerClient, nameRaw: any, overridesRaw: any?): BuffRecord?
	return self:ApplyDefinition(nameRaw, BuffConstants.KIND_DEBUFF, overridesRaw)
end

function BuffHandlerClient.AddBuff(
	self: BuffHandlerClient,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	return self.active:AddBuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffHandlerClient.AddDebuff(
	self: BuffHandlerClient,
	nameRaw: any,
	durationRaw: any?,
	effectsRaw: any?,
	descriptionRaw: any?,
	affectsRaw: any?,
	optionsRaw: any?
): BuffRecord
	return self.active:AddDebuff(nameRaw, durationRaw, effectsRaw, descriptionRaw, affectsRaw, optionsRaw)
end

function BuffHandlerClient.Remove(self: BuffHandlerClient, idOrNameRaw: any, reasonRaw: any?, kindRaw: any?): boolean
	return self.active:Remove(idOrNameRaw, reasonRaw, kindRaw)
end

function BuffHandlerClient.Clear(self: BuffHandlerClient, kindRaw: any?): number
	return self.active:Clear(kindRaw)
end

function BuffHandlerClient.GetActive(self: BuffHandlerClient, kindRaw: any?): { BuffRecord }
	return self.active:GetRecords(kindRaw)
end

function BuffHandlerClient.GetDefinitions(self: BuffHandlerClient, kindRaw: any?): { BuffRecord }
	return self.definitions:GetRecords(kindRaw)
end

function BuffHandlerClient.GetRemainingSeconds(self: BuffHandlerClient, idOrNameRaw: any, kindRaw: any?): number?
	return self.active:GetRemainingSeconds(idOrNameRaw, kindRaw)
end

function BuffHandlerClient.Destroy(self: BuffHandlerClient)
	if self.maid ~= nil then
		self.maid:Destroy()
		self.maid = nil
	end
end
BuffHandlerClient.New = BuffHandlerClient.new
type BuffHandlerClient = typeof(BuffHandlerClient) & {
	localPlayer: Player,
	maid: MaidClass?,
	definitions: any,
	active: any,
	definitionChanged: SignalObject,
	activeChanged: SignalObject,
	buffAdded: SignalObject,
	buffChanged: SignalObject,
	buffRemoved: SignalObject,
}

return BuffHandlerClient :: BuffHandlerClient
