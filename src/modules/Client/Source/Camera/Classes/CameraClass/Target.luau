
local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")

local BossServiceClient = require("BossServiceClient")

local Target = {}
Target.__index = Target

export type GotTarget = {
	kind: string,
	position: Vector3,
	velocity: Vector3,
	lookPosition: Vector3?,
	cacheKey: string?,
	instance: Instance?,
	model: Model?,
	basePart: BasePart?,
	subject: any?,
	source: any?,
	metadata: { [string]: any }?,
}

export type Target = typeof(setmetatable(
	{} :: {
		localPlayer: Player?,
		character: Model?,
		explicitTarget: any?,
		GetCharacterTarget: ((character: Model?) -> BasePart?)?,
		temporaryOverride: any?,
		temporaryOverrideExpiresAt: number?,
	},
	Target
))

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function getInstanceCacheKey(instance: Instance): string
	local ok, debugIdOrError = (pcall :: any)(function()
		return (instance :: any):GetDebugId(0)
	end)
	if ok and typeof(debugIdOrError) == "string" and debugIdOrError ~= "" then
		return debugIdOrError
	end

	local okFullName, fullNameOrError = pcall(function()
		return instance:GetFullName()
	end)
	if okFullName and typeof(fullNameOrError) == "string" and fullNameOrError ~= "" then
		return fullNameOrError
	end

	return tostring(instance)
end

local function coerceVelocity(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	return Vector3.zero
end

local function getModelRootPart(model: Model?): BasePart?
	if model == nil then
		return nil
	end

	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if model.PrimaryPart ~= nil then
		return model.PrimaryPart
	end

	return model:FindFirstChildWhichIsA("BasePart", true)
end

local function getPlayerCharacterRoot(player: Player?): BasePart?
	if player == nil then
		return nil
	end
	return getModelRootPart(player.Character)
end

local function cloneMetadata(metadataRaw: any): { [string]: any }?
	if typeof(metadataRaw) ~= "table" then
		return nil
	end

	return table.clone(metadataRaw)
end

local function createGotTarget(
	kindRaw: any,
	position: Vector3,
	velocityRaw: any,
	lookPositionRaw: any,
	cacheKeyRaw: any,
	instanceRaw: any,
	modelRaw: any,
	basePartRaw: any,
	subjectRaw: any,
	sourceRaw: any,
	metadataRaw: any
): GotTarget
	local basePart = if typeof(basePartRaw) == "Instance" and basePartRaw:IsA("BasePart") then basePartRaw else nil
	local model = if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then modelRaw else nil
	local instance = if typeof(instanceRaw) == "Instance" then instanceRaw else nil

	return {
		kind = if trim(kindRaw) ~= "" then trim(kindRaw) else "Target",
		position = position,
		velocity = coerceVelocity(velocityRaw),
		lookPosition = if typeof(lookPositionRaw) == "Vector3" then lookPositionRaw else nil,
		cacheKey = if trim(cacheKeyRaw) ~= "" then trim(cacheKeyRaw) else nil,
		instance = instance,
		model = model,
		basePart = basePart,
		subject = subjectRaw,
		source = sourceRaw,
		metadata = cloneMetadata(metadataRaw),
	}
end

local function getBossState(): any
	local bossClient = BossServiceClient :: any
	if typeof(bossClient) ~= "table" then
		return nil
	end
	return bossClient.state
end

local function getBossSnapshotByRuntimeId(runtimeIdRaw: any): any?
	local runtimeId = trim(runtimeIdRaw)
	if runtimeId == "" then
		return nil
	end

	local state = getBossState()
	if typeof(state) ~= "table" or typeof((state :: any).byId) ~= "table" then
		return nil
	end
	return (state :: any).byId[runtimeId]
end

local function getBossSnapshotByFilters(filtersRaw: any): any?
	local filters = if typeof(filtersRaw) == "table" then filtersRaw else {} :: any
	local state = getBossState()
	if
		typeof(state) ~= "table"
		or typeof((state :: any).orderedIds) ~= "table"
		or typeof((state :: any).byId) ~= "table"
	then
		return nil
	end

	local bossId = trim((filters :: any).bossId)
	local encounterChannel = trim((filters :: any).encounterChannel)
	local orderedIds = (state :: any).orderedIds :: { string }
	local byId = (state :: any).byId :: { [string]: any }

	for _, runtimeId in orderedIds do
		local snapshot = byId[runtimeId]
		if typeof(snapshot) ~= "table" then
			continue
		end

		if bossId ~= "" and trim((snapshot :: any).bossId) ~= bossId then
			continue
		end
		if encounterChannel ~= "" and trim((snapshot :: any).encounterChannel) ~= encounterChannel then
			continue
		end
		if (snapshot :: any).isAlive == false then
			continue
		end
		return snapshot
	end

	return nil
end

local function getBossSnapshot(sourceRaw: any): any?
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {} :: any
	local runtimeId = trim((source :: any).runtimeId)
	if runtimeId ~= "" then
		return getBossSnapshotByRuntimeId(runtimeId)
	end
	return getBossSnapshotByFilters(source)
end

local function createBossTarget(sourceRaw: any, snapshotRaw: any): GotTarget?
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw else nil
	if snapshot == nil then
		return nil
	end

	local motion = if typeof((snapshot :: any).motion) == "table" then (snapshot :: any).motion else {} :: any
	local position = if typeof((motion :: any).position) == "Vector3"
		then (motion :: any).position
		else (snapshot :: any).position
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local velocity = if typeof((motion :: any).velocity) == "Vector3"
		then (motion :: any).velocity
		else coerceVelocity((snapshot :: any).velocity)
	local lookPosition = if typeof((snapshot :: any).facing) == "Vector3"
		then position + (snapshot :: any).facing
		else nil

	return createGotTarget(
		(sourceRaw :: any).kind or "Boss",
		position,
		velocity,
		lookPosition,
		"boss:" .. trim((snapshot :: any).id),
		nil,
		nil,
		nil,
		snapshot,
		sourceRaw,
		{
			runtimeId = trim((snapshot :: any).id),
			bossId = trim((snapshot :: any).bossId),
			encounterChannel = trim((snapshot :: any).encounterChannel),
		}
	)
end

function Target.New(optionsRaw: any?): Target
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any

	return setmetatable({
		localPlayer = if typeof((options :: any).localPlayer) == "Instance"
				and (options :: any).localPlayer:IsA("Player")
			then (options :: any).localPlayer
			else Players.LocalPlayer,
		character = if typeof((options :: any).character) == "Instance"
				and (options :: any).character:IsA("Model")
			then (options :: any).character
			else nil,
		explicitTarget = (options :: any).target,
		GetCharacterTarget = if typeof((options :: any).GetCharacterTarget) == "function"
			then (options :: any).GetCharacterTarget
			else nil,
		temporaryOverride = nil,
		temporaryOverrideExpiresAt = nil,
	}, Target)
end

function Target.SetCharacter(self: Target, characterRaw: any)
	if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model") then
		self.character = characterRaw
		return
	end
	self.character = nil
end

function Target.SetExplicitTarget(self: Target, targetRaw: any?)
	self.explicitTarget = targetRaw
end

function Target.SetTemporaryOverride(self: Target, targetRaw: any?, durationSecondsRaw: any?)
	self.temporaryOverride = targetRaw

	if typeof(durationSecondsRaw) == "number" and durationSecondsRaw >= 0 then
		self.temporaryOverrideExpiresAt = os.clock() + durationSecondsRaw
		return
	end

	if typeof(targetRaw) == "table" and typeof((targetRaw :: any).durationSeconds) == "number" then
		self.temporaryOverrideExpiresAt = os.clock() + math.max((targetRaw :: any).durationSeconds, 0)
		return
	end
	if typeof(targetRaw) == "table" and typeof((targetRaw :: any).expiresAt) == "number" then
		self.temporaryOverrideExpiresAt = (targetRaw :: any).expiresAt
		return
	end

	self.temporaryOverrideExpiresAt = nil
end

function Target.ClearTemporaryOverride(self: Target)
	self.temporaryOverride = nil
	self.temporaryOverrideExpiresAt = nil
end

function Target.HasTemporaryOverride(self: Target): boolean
	if self.temporaryOverride == nil then
		return false
	end
	if self.temporaryOverrideExpiresAt ~= nil and os.clock() >= self.temporaryOverrideExpiresAt then
		self:ClearTemporaryOverride()
		return false
	end
	return true
end

function Target.GetAny(self: Target, sourceRaw: any, kindFallback: string?): GotTarget?
	if sourceRaw == nil then
		return nil
	end

	if typeof(sourceRaw) == "Instance" then
		if sourceRaw:IsA("BasePart") then
			if sourceRaw.Parent == nil then
				return nil
			end
			return createGotTarget(
				kindFallback or "BasePart",
				sourceRaw.Position,
				sourceRaw.AssemblyLinearVelocity,
				nil,
				getInstanceCacheKey(sourceRaw),
				sourceRaw,
				sourceRaw.Parent,
				sourceRaw,
				sourceRaw,
				sourceRaw,
				nil
			)
		end

		if sourceRaw:IsA("Attachment") then
			local attachmentParent = sourceRaw.Parent :: Instance?
			if attachmentParent == nil then
				return nil
			end
			local parentPart = if attachmentParent:IsA("BasePart") then attachmentParent else nil
			return createGotTarget(
				kindFallback or "Attachment",
				sourceRaw.WorldPosition,
				if parentPart ~= nil then parentPart.AssemblyLinearVelocity else Vector3.zero,
				nil,
				getInstanceCacheKey(sourceRaw),
				sourceRaw,
				if attachmentParent:IsA("Model") then attachmentParent else nil,
				parentPart,
				sourceRaw,
				sourceRaw,
				nil
			)
		end

		if sourceRaw:IsA("Model") then
			if sourceRaw.Parent == nil then
				return nil
			end
			local rootPart = getModelRootPart(sourceRaw)
			if rootPart == nil then
				return nil
			end

			return createGotTarget(
				kindFallback or "Model",
				rootPart.Position,
				rootPart.AssemblyLinearVelocity,
				nil,
				getInstanceCacheKey(sourceRaw),
				sourceRaw,
				sourceRaw,
				rootPart,
				sourceRaw,
				sourceRaw,
				nil
			)
		end

		if sourceRaw:IsA("Player") then
			local rootPart = getPlayerCharacterRoot(sourceRaw)
			if rootPart == nil then
				return nil
			end

			return createGotTarget(
				kindFallback or "Player",
				rootPart.Position,
				rootPart.AssemblyLinearVelocity,
				nil,
				"player:" .. tostring(sourceRaw.UserId),
				sourceRaw,
				sourceRaw.Character,
				rootPart,
				sourceRaw,
				sourceRaw,
				{
					userId = sourceRaw.UserId,
				}
			)
		end
	end

	if typeof(sourceRaw) ~= "table" then
		return nil
	end

	local source = sourceRaw :: any
	local nestedTarget = source.target
		or source.subject
		or source.instance
		or source.basePart
		or source.rootPart
		or source.model
	if nestedTarget ~= nil and nestedTarget ~= sourceRaw then
		local nestedGot = self:GetAny(nestedTarget, source.kind or kindFallback)
		if nestedGot ~= nil then
			if typeof(source.lookPosition) == "Vector3" then
				nestedGot.lookPosition = source.lookPosition
			end
			if typeof(source.velocity) == "Vector3" then
				nestedGot.velocity = source.velocity
			end
			if trim(source.cacheKey) ~= "" then
				nestedGot.cacheKey = trim(source.cacheKey)
			end
			nestedGot.source = sourceRaw
			if source.metadata ~= nil then
				nestedGot.metadata = cloneMetadata(source.metadata)
			end
			return nestedGot
		end
	end

	if source.player ~= nil then
		local playerGot = self:GetAny(source.player, source.kind or kindFallback or "Player")
		if playerGot ~= nil then
			playerGot.source = sourceRaw
			return playerGot
		end
	end

	if source.character ~= nil then
		local characterGot = self:GetAny(source.character, source.kind or kindFallback or "Character")
		if characterGot ~= nil then
			characterGot.source = sourceRaw
			return characterGot
		end
	end

	local bossSnapshot = getBossSnapshot(sourceRaw)
	if bossSnapshot ~= nil then
		local bossTarget = createBossTarget(sourceRaw, bossSnapshot)
		if bossTarget ~= nil then
			return bossTarget
		end
	end

	if typeof(source.position) == "Vector3" then
		return createGotTarget(
			source.kind or kindFallback or "Point",
			source.position,
			source.velocity,
			source.lookPosition,
			source.cacheKey,
			nil,
			nil,
			nil,
			source.subject,
			sourceRaw,
			source.metadata
		)
	end

	return nil
end

function Target.GetCharacterTarget(self: Target, characterRaw: any?): GotTarget?
	local character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model")
		then characterRaw
		else self.character
	if character == nil then
		return nil
	end

	if self.GetCharacterTarget ~= nil then
		local ok, basePart = pcall(self.GetCharacterTarget, character)
		if ok and typeof(basePart) == "Instance" and basePart:IsA("BasePart") then
			return self:GetAny(basePart, "Character")
		end
	end

	return self:GetAny(character, "Character")
end

function Target.Get(self: Target, optionsRaw: any?): GotTarget?
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {} :: any
	if self.temporaryOverrideExpiresAt ~= nil and os.clock() >= self.temporaryOverrideExpiresAt then
		self:ClearTemporaryOverride()
	end

	local override = if typeof((options :: any).override) == "table" then (options :: any).override else nil
	if override ~= nil then
		local overrideTarget = self:GetAny(override, (override :: any).kind or "Override")
		if overrideTarget ~= nil then
			return overrideTarget
		end
	end

	if self:HasTemporaryOverride() then
		local temporaryTarget = self:GetAny(self.temporaryOverride, "TemporaryOverride")
		if temporaryTarget ~= nil then
			temporaryTarget.kind = "TemporaryOverride"
			return temporaryTarget
		end
	end

	local explicitTarget = self:GetAny(self.explicitTarget, "ExplicitTarget")
	if explicitTarget ~= nil then
		return explicitTarget
	end

	local characterTarget = Target.GetCharacterTarget(self, (options :: any).character)
	if characterTarget ~= nil then
		return characterTarget
	end

	local localPlayer = if typeof((options :: any).localPlayer) == "Instance"
			and (options :: any).localPlayer:IsA("Player")
		then (options :: any).localPlayer
		else self.localPlayer
	if localPlayer ~= nil then
		return self:GetAny(localPlayer, "Player")
	end

	return nil
end

return Target
