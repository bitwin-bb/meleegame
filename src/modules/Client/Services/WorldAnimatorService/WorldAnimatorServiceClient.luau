--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Janitor = require(ReplicatedStorage.Packages.Janitor)
local Configs = require(script:FindFirstAncestor("game").Shared.Modules.Core.Configs)
local NevermoreSupport = require(script:FindFirstAncestor("game").Shared.Modules.Core.NevermoreSupport)
local ClientBinderSupport = require(script:FindFirstAncestor("game").Client.Binders.ClientBinderSupport)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local WorldAnimatorServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.WorldAnimatorService.WorldAnimatorServiceUtils)

type ChunkAnimatorSettings = WorldAnimatorServiceUtils.ChunkAnimatorSettings
type ChunkAnimationType = WorldAnimatorServiceUtils.ChunkAnimationType
type ChunkAnimationEasing = WorldAnimatorServiceUtils.ChunkAnimationEasing

type JanitorClass = {
	GiveChore: (self: JanitorClass, chore: any, ...any) -> (any),
	Clean: (self: JanitorClass) -> (),
	Destroy: (self: JanitorClass) -> (),
}

type ChunkAnimationState = {
	chunkModel: Model,
	visualModel: Model,
	originalParts: { BasePart },
	originalLocalTransparencyModifiers: { number },
	cloneParts: { BasePart },
	cloneBaseTransparency: { number },
	startPivot: CFrame,
	targetPivot: CFrame,
	startedAt: number,
	duration: number,
	animationType: ChunkAnimationType,
	easing: ChunkAnimationEasing,
	destroyConnection: RBXScriptConnection?,
}

type StartAnimationResult = "started" | "retry" | "skip"

local WorldAnimatorServiceClient = {}

local RUNTIME_FOLDER_NAME = "WorldAnimatorRuntime"
local SKIP_WORLD_ANIMATOR_ATTRIBUTE = "SkipWorldAnimator"
local ANIMATING_WORLD_ANIMATOR_ATTRIBUTE = "WorldAnimatorAnimating"

local function safeGetModelPivot(model: Model): (boolean, CFrame)
	local ok, result = pcall(function()
		return model:GetPivot()
	end)
	if not ok then
		return false, CFrame.new()
	end
	return true, result :: CFrame
end

local function collectModelParts(model: Model, maxCount: number): { BasePart }
	local parts = {}
	for _, descendant in model:GetDescendants() do
		if descendant:IsA("BasePart") then
			table.insert(parts, descendant)
			if #parts >= maxCount then
				break
			end
		end
	end
	return parts
end

local function resolveChunkIdentityKey(chunkModel: Model): string?
	local chunkKeyRaw = chunkModel:GetAttribute("ChunkKey")
	if typeof(chunkKeyRaw) == "string" and chunkKeyRaw ~= "" then
		return chunkKeyRaw
	end

	local chunkX = chunkModel:GetAttribute("ChunkX")
	local chunkY = chunkModel:GetAttribute("ChunkY")
	if typeof(chunkX) == "number" and typeof(chunkY) == "number" then
		return `{math.floor(chunkX)}:{math.floor(chunkY)}`
	end

	local nameChunkX, nameChunkY = string.match(chunkModel.Name, "^Chunk_(-?%d+)_(-?%d+)$")
	if nameChunkX ~= nil and nameChunkY ~= nil then
		return `{nameChunkX}:{nameChunkY}`
	end

	return nil
end

local function hasSiblingChunkWithSameIdentity(chunkModel: Model): boolean
	local identityKey = resolveChunkIdentityKey(chunkModel)
	if identityKey == nil then
		return false
	end

	local parent = chunkModel.Parent
	if parent == nil then
		return false
	end

	for _, sibling in parent:GetChildren() do
		if sibling == chunkModel then
			continue
		end
		if not WorldAnimatorServiceUtils.isChunkModel(sibling) then
			continue
		end

		local siblingModel = sibling :: Model
		local siblingIdentityKey = resolveChunkIdentityKey(siblingModel)
		if siblingIdentityKey ~= nil and siblingIdentityKey == identityKey then
			return true
		end
	end

	return false
end

local function computePositionRelativeFadeAlpha(startPivot: CFrame, currentPivot: CFrame, targetPivot: CFrame): number
	local startPosition = startPivot.Position
	local targetPosition = targetPivot.Position
	local totalDistance = (targetPosition - startPosition).Magnitude
	if totalDistance <= 0.0001 then
		return 1
	end

	local currentDistance = (currentPivot.Position - startPosition).Magnitude
	return math.clamp(currentDistance / totalDistance, 0, 1)
end

function WorldAnimatorServiceClient.EnsureRuntimeFolder(self: WorldAnimatorServiceClient): Folder
	return WorkspaceFolders.getOrCreateFolderInGame(RUNTIME_FOLDER_NAME)
end

function WorldAnimatorServiceClient.StopRenderLoop(self: WorldAnimatorServiceClient)
	if self.renderConnection ~= nil then
		self.renderConnection:Disconnect()
		self.renderConnection = nil
	end
end

function WorldAnimatorServiceClient.EnsureRenderLoop(self: WorldAnimatorServiceClient)
	if self.renderConnection ~= nil then
		return
	end

	self.renderConnection = RunService.RenderStepped:Connect(function()
		self:processPendingChunks()
		self:stepAnimations()

		if #self.pendingChunks <= 0 and #self.activeAnimations <= 0 then
			self:stopRenderLoop()
		end
	end)
end

function WorldAnimatorServiceClient.RestoreOriginalChunkVisibility(self: WorldAnimatorServiceClient, animation: ChunkAnimationState)
	for index, part in animation.originalParts do
		pcall(function()
			part.LocalTransparencyModifier = animation.originalLocalTransparencyModifiers[index] or 0
		end)
	end
end

function WorldAnimatorServiceClient.StopAnimation(self: WorldAnimatorServiceClient, animation: ChunkAnimationState, revealOriginal: boolean)
	pcall(function()
		animation.chunkModel:SetAttribute(ANIMATING_WORLD_ANIMATOR_ATTRIBUTE, false)
	end)

	if revealOriginal then
		self:restoreOriginalChunkVisibility(animation)
	end

	if animation.destroyConnection ~= nil then
		animation.destroyConnection:Disconnect()
		animation.destroyConnection = nil
	end

	if animation.visualModel.Parent ~= nil then
		animation.visualModel:Destroy()
	end

	self.animationsByChunk[animation.chunkModel] = nil
	for index = #self.activeAnimations, 1, -1 do
		if self.activeAnimations[index] == animation then
			table.remove(self.activeAnimations, index)
			break
		end
	end
end

function WorldAnimatorServiceClient.StepAnimations(self: WorldAnimatorServiceClient)
	if #self.activeAnimations <= 0 then
		return
	end

	local now = os.clock()
	for index = #self.activeAnimations, 1, -1 do
		local animation = self.activeAnimations[index]
		if animation.chunkModel.Parent == nil then
			self:stopAnimation(animation, true)
			continue
		end

		local elapsed = now - animation.startedAt
		local alpha = math.clamp(elapsed / animation.duration, 0, 1)
		local easedAlpha = WorldAnimatorServiceUtils.applyEasing(animation.easing, alpha)
		local nextPivot = animation.startPivot:Lerp(animation.targetPivot, easedAlpha)
		animation.visualModel:PivotTo(nextPivot)

		if WorldAnimatorServiceUtils.doesAnimationUseFade(animation.animationType) then
			local fadeAlpha = easedAlpha
			if self.settings.transparencyRelativeToChunkPosition then
				fadeAlpha = computePositionRelativeFadeAlpha(animation.startPivot, nextPivot, animation.targetPivot)
			end
			for partIndex, part in animation.cloneParts do
				local baseTransparency = animation.cloneBaseTransparency[partIndex] or 0
				part.Transparency = baseTransparency + (1 - baseTransparency) * (1 - fadeAlpha)
			end
		end

		if alpha >= 1 then
			self:stopAnimation(animation, true)
		end
	end
end

function WorldAnimatorServiceClient.EnqueueChunkForAnimation(self: WorldAnimatorServiceClient, chunkModel: Model)
	if not self.settings.enabled then
		return
	end
	if self.animationsByChunk[chunkModel] ~= nil then
		return
	end
	if self.pendingChunkLookup[chunkModel] ~= nil then
		return
	end

	self.pendingChunkLookup[chunkModel] = true
	table.insert(self.pendingChunks, chunkModel)
	self:ensureRenderLoop()
end

function WorldAnimatorServiceClient.RemovePendingChunk(self: WorldAnimatorServiceClient, chunkModel: Model)
	if self.pendingChunkLookup[chunkModel] == nil then
		return
	end

	self.pendingChunkLookup[chunkModel] = nil
	for index = #self.pendingChunks, 1, -1 do
		if self.pendingChunks[index] == chunkModel then
			table.remove(self.pendingChunks, index)
		end
	end
end

function WorldAnimatorServiceClient.EvaluateChunkAnimation(
	self: WorldAnimatorServiceClient,
	chunkModel: Model
): (StartAnimationResult, CFrame?)
	if not self.settings.enabled then
		return "skip", nil
	end
	if self.animationsByChunk[chunkModel] ~= nil then
		return "skip", nil
	end
	if #self.activeAnimations >= self.settings.maxConcurrentAnimations then
		return "retry", nil
	end

	local ok, targetPivot = safeGetModelPivot(chunkModel)
	if not ok then
		return "retry", nil
	end

	local distanceFromPlayer = WorldAnimatorServiceUtils.getLocalPlayerDistanceFromPosition(targetPivot.Position)
	if distanceFromPlayer == nil then
		return "retry", nil
	end
	if distanceFromPlayer < self.settings.minPlayerDistanceToAnimate then
		return "skip", nil
	end

	return "started", targetPivot
end

function WorldAnimatorServiceClient.StartChunkAnimation(self: WorldAnimatorServiceClient, chunkModel: Model): StartAnimationResult
	if chunkModel.Parent == nil then
		return "skip"
	end

	local eligibility, targetPivot = self:evaluateChunkAnimation(chunkModel)
	if eligibility ~= "started" or targetPivot == nil then
		return eligibility
	end

	local originalParts = collectModelParts(chunkModel, self.settings.maxAnimatedPartsPerChunk + 1)
	if #originalParts <= 0 then
		return "retry"
	end
	if #originalParts > self.settings.maxAnimatedPartsPerChunk then
		return "skip"
	end

	local visualClone = chunkModel:Clone()
	visualClone.Name = `{chunkModel.Name}_ChunkAnim`

	local cloneParts = {}
	local cloneBaseTransparency = {}
	for _, descendant in visualClone:GetDescendants() do
		if descendant:IsA("Script") or descendant:IsA("LocalScript") or descendant:IsA("ModuleScript") then
			descendant:Destroy()
		elseif descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanQuery = false
			descendant.CanTouch = false
			descendant.Massless = true
			table.insert(cloneParts, descendant)
			table.insert(cloneBaseTransparency, descendant.Transparency)
		end
	end

	if #cloneParts <= 0 then
		visualClone:Destroy()
		return "skip"
	end

	local originalLocalTransparencyModifiers = Sift.Array.create(#originalParts)
	for index, part in originalParts do
		originalLocalTransparencyModifiers[index] = part.LocalTransparencyModifier
		part.LocalTransparencyModifier = 1
	end

	local animationOffset =
		WorldAnimatorServiceUtils.computeAnimationOffset(self.settings.animationType, self.settings.verticalOffset)
	local startPivot = targetPivot + animationOffset
	visualClone:PivotTo(startPivot)
	if WorldAnimatorServiceUtils.doesAnimationUseFade(self.settings.animationType) then
		for _, part in cloneParts do
			part.Transparency = 1
		end
	end

	visualClone.Parent = self.runtimeFolder

	local animation: ChunkAnimationState = {
		chunkModel = chunkModel,
		visualModel = visualClone,
		originalParts = originalParts,
		originalLocalTransparencyModifiers = originalLocalTransparencyModifiers,
		cloneParts = cloneParts,
		cloneBaseTransparency = cloneBaseTransparency,
		startPivot = startPivot,
		targetPivot = targetPivot,
		startedAt = os.clock(),
		duration = self.settings.duration,
		animationType = self.settings.animationType,
		easing = self.settings.easing,
		destroyConnection = nil,
	}

	animation.destroyConnection = chunkModel.Destroying:Connect(function()
		self:stopAnimation(animation, true)
	end)

	pcall(function()
		chunkModel:SetAttribute(ANIMATING_WORLD_ANIMATOR_ATTRIBUTE, true)
	end)

	self.animationsByChunk[chunkModel] = animation
	table.insert(self.activeAnimations, animation)
	self:ensureRenderLoop()
	return "started"
end

function WorldAnimatorServiceClient.ProcessPendingChunks(self: WorldAnimatorServiceClient)
	if #self.pendingChunks <= 0 then
		return
	end

	local processBudget = math.max(1, self.settings.maxConcurrentAnimations * 2)
	local processed = 0
	while processed < processBudget and #self.pendingChunks > 0 do
		processed += 1
		local chunkModel = table.remove(self.pendingChunks, 1)
		if chunkModel == nil then
			break
		end

		self.pendingChunkLookup[chunkModel] = nil
		if chunkModel.Parent == nil then
			continue
		end

		local result = self:startChunkAnimation(chunkModel)
		if result == "retry" then
			self:enqueueChunkForAnimation(chunkModel)
		end
	end
end

function WorldAnimatorServiceClient.OnChunkAdded(self: WorldAnimatorServiceClient, chunkRaw: Instance)
	if not WorldAnimatorServiceUtils.isChunkModel(chunkRaw) then
		return
	end

	local chunkModel = chunkRaw :: Model
	if chunkModel:GetAttribute(SKIP_WORLD_ANIMATOR_ATTRIBUTE) == true then
		return
	end
	if hasSiblingChunkWithSameIdentity(chunkModel) then
		return
	end

	local result = self:startChunkAnimation(chunkModel)
	if result == "retry" then
		self:enqueueChunkForAnimation(chunkModel)
	end
end

function WorldAnimatorServiceClient.OnChunkRemoved(self: WorldAnimatorServiceClient, chunkRaw: Instance)
	if not chunkRaw:IsA("Model") then
		return
	end

	self:removePendingChunk(chunkRaw)

	local animation = self.animationsByChunk[chunkRaw]
	if animation == nil then
		return
	end
	self:stopAnimation(animation, true)
end

function WorldAnimatorServiceClient.BindChunksFolder(self: WorldAnimatorServiceClient, chunksFolder: Folder)
	self.chunksFolderJanitor:Clean()
	table.clear(self.pendingChunks)
	table.clear(self.pendingChunkLookup)
	self.chunksFolder = chunksFolder
end

function WorldAnimatorServiceClient.BindWorldFolder(self: WorldAnimatorServiceClient, worldFolder: Folder)
	self.worldFolderJanitor:Clean()
	self.chunksFolderJanitor:Clean()
	self.worldFolder = worldFolder
	self.chunksFolder = nil

	local existingChunksFolder = WorldAnimatorServiceUtils.findChunksFolder(worldFolder)
	if existingChunksFolder ~= nil then
		self:bindChunksFolder(existingChunksFolder)
	end

	self.worldFolderJanitor:GiveChore(worldFolder.ChildAdded:Connect(function(child: Instance)
		if child.Name ~= WorldAnimatorServiceUtils.CHUNKS_FOLDER_NAME then
			return
		end
		if child:IsA("Folder") then
			self:bindChunksFolder(child)
		end
	end))

	self.worldFolderJanitor:GiveChore(worldFolder.ChildRemoved:Connect(function(child: Instance)
		if child == self.chunksFolder then
			self.chunksFolderJanitor:Clean()
			table.clear(self.pendingChunks)
			table.clear(self.pendingChunkLookup)
			self.chunksFolder = nil
		end
	end))
end

function WorldAnimatorServiceClient.TryBindExistingWorldFolder(self: WorldAnimatorServiceClient)
	local worldFolder = WorldAnimatorServiceUtils.findWorldGenerationFolder()
	if worldFolder ~= nil then
		self:bindWorldFolder(worldFolder)
	end
end

function WorldAnimatorServiceClient.Init(self: WorldAnimatorServiceClient)
	self.settings = WorldAnimatorServiceUtils.createSettingsFromConfigs(Configs)
	self.janitor = Janitor.new()
	self.worldFolderJanitor = Janitor.new()
	self.chunksFolderJanitor = Janitor.new()
	self.janitor:GiveChore(self.worldFolderJanitor)
	self.janitor:GiveChore(self.chunksFolderJanitor)
	self.runtimeFolder = self:ensureRuntimeFolder()
	self.worldFolder = nil :: Folder?
	self.chunksFolder = nil :: Folder?
	self.activeAnimations = {}
	self.animationsByChunk = {}
	self.pendingChunks = {}
	self.pendingChunkLookup = {}
	self.renderConnection = nil :: RBXScriptConnection?
	self.binders = NevermoreSupport.getService(ClientBinderSupport)

	local function onWorldFolderAdded(child: Instance)
		if child.Name ~= WorldAnimatorServiceUtils.WORLD_FOLDER_NAME then
			return
		end
		if child:IsA("Folder") then
			self:bindWorldFolder(child)
		end
	end

	local function onWorldFolderRemoved(child: Instance)
		if child ~= self.worldFolder then
			return
		end

		self.worldFolderJanitor:Clean()
		self.chunksFolderJanitor:Clean()
		table.clear(self.pendingChunks)
		table.clear(self.pendingChunkLookup)
		self.worldFolder = nil
		self.chunksFolder = nil
	end

	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()
	self.janitor:GiveChore(gameFolder.ChildAdded:Connect(onWorldFolderAdded))
	self.janitor:GiveChore(gameFolder.ChildRemoved:Connect(onWorldFolderRemoved))

	self.janitor:GiveChore(Workspace.ChildAdded:Connect(onWorldFolderAdded))
	self.janitor:GiveChore(Workspace.ChildRemoved:Connect(onWorldFolderRemoved))

	self:tryBindExistingWorldFolder()
end

function WorldAnimatorServiceClient.Destroy(self: WorldAnimatorServiceClient)
	for index = #self.activeAnimations, 1, -1 do
		local animation = self.activeAnimations[index]
		self:stopAnimation(animation, true)
	end

	self:stopRenderLoop()
	if self.janitor ~= nil then
		self.janitor:Destroy()
	end

	table.clear(self.pendingChunks)
	table.clear(self.pendingChunkLookup)
end

WorldAnimatorServiceClient.ensureRuntimeFolder = WorldAnimatorServiceClient.EnsureRuntimeFolder
WorldAnimatorServiceClient.stopRenderLoop = WorldAnimatorServiceClient.StopRenderLoop
WorldAnimatorServiceClient.ensureRenderLoop = WorldAnimatorServiceClient.EnsureRenderLoop
WorldAnimatorServiceClient.restoreOriginalChunkVisibility = WorldAnimatorServiceClient.RestoreOriginalChunkVisibility
WorldAnimatorServiceClient.stopAnimation = WorldAnimatorServiceClient.StopAnimation
WorldAnimatorServiceClient.stepAnimations = WorldAnimatorServiceClient.StepAnimations
WorldAnimatorServiceClient.enqueueChunkForAnimation = WorldAnimatorServiceClient.EnqueueChunkForAnimation
WorldAnimatorServiceClient.removePendingChunk = WorldAnimatorServiceClient.RemovePendingChunk
WorldAnimatorServiceClient.evaluateChunkAnimation = WorldAnimatorServiceClient.EvaluateChunkAnimation
WorldAnimatorServiceClient.startChunkAnimation = WorldAnimatorServiceClient.StartChunkAnimation
WorldAnimatorServiceClient.processPendingChunks = WorldAnimatorServiceClient.ProcessPendingChunks
WorldAnimatorServiceClient.onChunkAdded = WorldAnimatorServiceClient.OnChunkAdded
WorldAnimatorServiceClient.onChunkRemoved = WorldAnimatorServiceClient.OnChunkRemoved
WorldAnimatorServiceClient.bindChunksFolder = WorldAnimatorServiceClient.BindChunksFolder
WorldAnimatorServiceClient.bindWorldFolder = WorldAnimatorServiceClient.BindWorldFolder
WorldAnimatorServiceClient.tryBindExistingWorldFolder = WorldAnimatorServiceClient.TryBindExistingWorldFolder
WorldAnimatorServiceClient.init = WorldAnimatorServiceClient.Init
WorldAnimatorServiceClient.destroy = WorldAnimatorServiceClient.Destroy

type WorldAnimatorServiceClient = typeof(WorldAnimatorServiceClient) & {
	settings: ChunkAnimatorSettings,
	janitor: JanitorClass,
	worldFolderJanitor: JanitorClass,
	chunksFolderJanitor: JanitorClass,
	worldFolder: Folder?,
	chunksFolder: Folder?,
	runtimeFolder: Folder,
	activeAnimations: { ChunkAnimationState },
	animationsByChunk: { [Model]: ChunkAnimationState },
	pendingChunks: { Model },
	pendingChunkLookup: { [Model]: boolean },
	renderConnection: RBXScriptConnection?,
}

return WorldAnimatorServiceClient :: WorldAnimatorServiceClient
