--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BossServiceClient = require(script:FindFirstAncestor("game").Client.Services.BossServiceClient)

local Target = {}
Target.__index = Target

export type ResolvedTarget = {
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
		resolveCharacterTarget: ((character: Model?) -> BasePart?)?,
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
	local ok, debugIdOrError = pcall(function()
		return instance:GetDebugId(0)
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

local function sanitizeVelocity(valueRaw: any): Vector3
	if typeof(valueRaw) == "Vector3" then
		return valueRaw
	end
	return Vector3.zero
end

local function resolveModelRootPart(model: Model?): BasePart?
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

local function resolvePlayerCharacterRoot(player: Player?): BasePart?
	if player == nil then
		return nil
	end
	return resolveModelRootPart(player.Character)
end

local function cloneMetadata(metadataRaw: any): { [string]: any }?
	if typeof(metadataRaw) ~= "table" then
		return nil
	end

	local metadata = {}
	for key, value in metadataRaw do
		metadata[key] = value
	end
	return metadata
end

local function createResolvedTarget(
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
): ResolvedTarget
	local basePart = if typeof(basePartRaw) == "Instance" and basePartRaw:IsA("BasePart") then basePartRaw else nil
	local model = if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then modelRaw else nil
	local instance = if typeof(instanceRaw) == "Instance" then instanceRaw else nil

	return {
		kind = if trim(kindRaw) ~= "" then trim(kindRaw) else "Target",
		position = position,
		velocity = sanitizeVelocity(velocityRaw),
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

local function resolveBossSnapshotByRuntimeId(runtimeIdRaw: any): any?
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

local function resolveBossSnapshotByFilters(filtersRaw: any): any?
	local filters = if typeof(filtersRaw) == "table" then filtersRaw else {}
	local state = getBossState()
	if typeof(state) ~= "table" or typeof((state :: any).orderedIds) ~= "table" or typeof((state :: any).byId) ~= "table" then
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

local function resolveBossSnapshot(sourceRaw: any): any?
	local source = if typeof(sourceRaw) == "table" then sourceRaw else {}
	local runtimeId = trim((source :: any).runtimeId)
	if runtimeId ~= "" then
		return resolveBossSnapshotByRuntimeId(runtimeId)
	end
	return resolveBossSnapshotByFilters(source)
end

local function createBossTarget(sourceRaw: any, snapshotRaw: any): ResolvedTarget?
	local snapshot = if typeof(snapshotRaw) == "table" then snapshotRaw else nil
	if snapshot == nil then
		return nil
	end

	local motion = if typeof((snapshot :: any).motion) == "table" then (snapshot :: any).motion else {}
	local position = if typeof((motion :: any).position) == "Vector3"
		then (motion :: any).position
		else (snapshot :: any).position
	if typeof(position) ~= "Vector3" then
		return nil
	end

	local velocity = if typeof((motion :: any).velocity) == "Vector3"
		then (motion :: any).velocity
		else sanitizeVelocity((snapshot :: any).velocity)
	local lookPosition = if typeof((snapshot :: any).facing) == "Vector3"
		then position + (snapshot :: any).facing
		else nil

	return createResolvedTarget(
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
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}

	return setmetatable({
		localPlayer = if typeof((options :: any).localPlayer) == "Instance" and (options :: any).localPlayer:IsA("Player")
			then (options :: any).localPlayer
			else Players.LocalPlayer,
		character = if typeof((options :: any).character) == "Instance" and (options :: any).character:IsA("Model")
			then (options :: any).character
			else nil,
		explicitTarget = (options :: any).target,
		resolveCharacterTarget = if typeof((options :: any).resolveCharacterTarget) == "function"
			then (options :: any).resolveCharacterTarget
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
		self:clearTemporaryOverride()
		return false
	end
	return true
end

function Target.ResolveAny(self: Target, sourceRaw: any, kindFallback: string?): ResolvedTarget?
	if sourceRaw == nil then
		return nil
	end

	if typeof(sourceRaw) == "Instance" then
		if sourceRaw:IsA("BasePart") then
			if sourceRaw.Parent == nil then
				return nil
			end
			return createResolvedTarget(
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
			if sourceRaw.Parent == nil then
				return nil
			end
			local parentPart = if sourceRaw.Parent ~= nil and sourceRaw.Parent:IsA("BasePart") then sourceRaw.Parent else nil
			return createResolvedTarget(
				kindFallback or "Attachment",
				sourceRaw.WorldPosition,
				if parentPart ~= nil then parentPart.AssemblyLinearVelocity else Vector3.zero,
				nil,
				getInstanceCacheKey(sourceRaw),
				sourceRaw,
				if sourceRaw.Parent ~= nil and sourceRaw.Parent:IsA("Model") then sourceRaw.Parent else nil,
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
			local rootPart = resolveModelRootPart(sourceRaw)
			if rootPart == nil then
				return nil
			end

			return createResolvedTarget(
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
			local rootPart = resolvePlayerCharacterRoot(sourceRaw)
			if rootPart == nil then
				return nil
			end

			return createResolvedTarget(
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
	local nestedTarget = source.target or source.subject or source.instance or source.basePart or source.rootPart or source.model
	if nestedTarget ~= nil and nestedTarget ~= sourceRaw then
		local nestedResolved = self:resolveAny(nestedTarget, source.kind or kindFallback)
		if nestedResolved ~= nil then
			if typeof(source.lookPosition) == "Vector3" then
				nestedResolved.lookPosition = source.lookPosition
			end
			if typeof(source.velocity) == "Vector3" then
				nestedResolved.velocity = source.velocity
			end
			if trim(source.cacheKey) ~= "" then
				nestedResolved.cacheKey = trim(source.cacheKey)
			end
			nestedResolved.source = sourceRaw
			if source.metadata ~= nil then
				nestedResolved.metadata = cloneMetadata(source.metadata)
			end
			return nestedResolved
		end
	end

	if source.player ~= nil then
		local playerResolved = self:resolveAny(source.player, source.kind or kindFallback or "Player")
		if playerResolved ~= nil then
			playerResolved.source = sourceRaw
			return playerResolved
		end
	end

	if source.character ~= nil then
		local characterResolved = self:resolveAny(source.character, source.kind or kindFallback or "Character")
		if characterResolved ~= nil then
			characterResolved.source = sourceRaw
			return characterResolved
		end
	end

	local bossSnapshot = resolveBossSnapshot(sourceRaw)
	if bossSnapshot ~= nil then
		local bossTarget = createBossTarget(sourceRaw, bossSnapshot)
		if bossTarget ~= nil then
			return bossTarget
		end
	end

	if typeof(source.position) == "Vector3" then
		return createResolvedTarget(
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

function Target.ResolveCharacterTarget(self: Target, characterRaw: any?): ResolvedTarget?
	local character = if typeof(characterRaw) == "Instance" and characterRaw:IsA("Model")
		then characterRaw
		else self.character
	if character == nil then
		return nil
	end

	if self.resolveCharacterTarget ~= nil then
		local ok, basePart = pcall(self.resolveCharacterTarget, character)
		if ok and typeof(basePart) == "Instance" and basePart:IsA("BasePart") then
			return self:resolveAny(basePart, "Character")
		end
	end

	return self:resolveAny(character, "Character")
end

function Target.Resolve(self: Target, optionsRaw: any?): ResolvedTarget?
	local options = if typeof(optionsRaw) == "table" then optionsRaw else {}
	if self.temporaryOverrideExpiresAt ~= nil and os.clock() >= self.temporaryOverrideExpiresAt then
		self:clearTemporaryOverride()
	end

	local override = if typeof((options :: any).override) == "table" then (options :: any).override else nil
	if override ~= nil then
		local resolvedOverride = self:resolveAny(override, (override :: any).kind or "Override")
		if resolvedOverride ~= nil then
			return resolvedOverride
		end
	end

	if self:hasTemporaryOverride() then
		local temporaryTarget = self:resolveAny(self.temporaryOverride, "TemporaryOverride")
		if temporaryTarget ~= nil then
			temporaryTarget.kind = "TemporaryOverride"
			return temporaryTarget
		end
	end

	local explicitTarget = self:resolveAny(self.explicitTarget, "ExplicitTarget")
	if explicitTarget ~= nil then
		return explicitTarget
	end

	local characterTarget = self:resolveCharacterTarget((options :: any).character)
	if characterTarget ~= nil then
		return characterTarget
	end

	local localPlayer = if typeof((options :: any).localPlayer) == "Instance" and (options :: any).localPlayer:IsA("Player")
		then (options :: any).localPlayer
		else self.localPlayer
	if localPlayer ~= nil then
		return self:resolveAny(localPlayer, "Player")
	end

	return nil
end

Target.new = Target.New
Target.setCharacter = Target.SetCharacter
Target.setExplicitTarget = Target.SetExplicitTarget
Target.setTemporaryOverride = Target.SetTemporaryOverride
Target.clearTemporaryOverride = Target.ClearTemporaryOverride
Target.hasTemporaryOverride = Target.HasTemporaryOverride
Target.resolveAny = Target.ResolveAny
Target.resolveCharacterTarget = Target.ResolveCharacterTarget
Target.resolve = Target.Resolve

return Target
