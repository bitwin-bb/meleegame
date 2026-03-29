--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local entityInfoSlice = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoSlice)
local BossServiceClient = require(ReplicatedStorage.Shared.Services.BossService.BossServiceClient)
local BossServiceUtils = require(ReplicatedStorage.Shared.Services.BossService.BossServiceUtils)
local NpcServiceClient = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceClient)
local NpcServiceUtils = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceUtils)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

type EntityInfoState = entityInfoSlice.EntityInfoState
type BossSnapshot = BossServiceUtils.BossSnapshot
type NpcSnapshot = NpcServiceUtils.NpcSnapshot
type HoverEntityKind = "Npc" | "Boss"
type HoverSnapshot = {
	displayName: string,
	hp: number,
	maxHp: number,
}

type NpcServiceClientState = {
	byId: { [string]: NpcSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

type BossServiceClientState = {
	byId: { [string]: BossSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

local entityInfoThunks = {}

local ENTITY_HOVER_ID = "npc_entity_hover"
local HIGHLIGHT_NAME = "EntityInfoHoverHighlight"
local HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 236, 66)
local HIGHLIGHT_OUTLINE_COLOR = HIGHLIGHT_FILL_COLOR
local HIGHLIGHT_FILL_TRANSPARENCY = 1
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 0

local runtime = {
	started = false,
	localPlayer = nil :: Player?,
	mouse = nil :: Mouse?,
	cachedNpcState = nil :: NpcServiceClientState?,
	cachedBossState = nil :: BossServiceClientState?,
	hoveredEntityKind = nil :: HoverEntityKind?,
	hoveredRuntimeId = nil :: string?,
	hoveredModel = nil :: Model?,
	highlight = nil :: Highlight?,
	npcStateChangedConnection = nil :: RBXScriptConnection?,
	bossStateChangedConnection = nil :: RBXScriptConnection?,
	renderSteppedConnection = nil :: RBXScriptConnection?,
}

local function resolveModelAdornee(model: Model): BasePart?
	local humanoidRootPart = model:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	local primaryPart = model.PrimaryPart
	if primaryPart ~= nil and primaryPart:IsA("BasePart") then
		return primaryPart
	end

	local descendantPart = model:FindFirstChildWhichIsA("BasePart", true)
	if descendantPart ~= nil then
		return descendantPart
	end

	return nil
end

local function toGuiPosition(screenPosition: Vector2): Vector2
	local topLeftInset, _ = GuiService:GetGuiInset()
	return Vector2.new(math.max(0, screenPosition.X - topLeftInset.X), math.max(0, screenPosition.Y - topLeftInset.Y))
end

local function resolveMouseGuiPosition(fallback: Vector2): Vector2
	local success, mousePosition = pcall(function()
		return UserInputService:GetMouseLocation()
	end)
	if success and typeof(mousePosition) == "Vector2" then
		return toGuiPosition(mousePosition)
	end

	return fallback
end

local function ensureHighlight(): Highlight
	local existing = runtime.highlight
	if existing ~= nil and existing.Parent ~= nil then
		existing.FillColor = HIGHLIGHT_FILL_COLOR
		existing.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
		existing.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
		existing.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
		return existing
	end

	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()
	local existingInGame = gameFolder:FindFirstChild(HIGHLIGHT_NAME)
	if existingInGame ~= nil then
		if existingInGame:IsA("Highlight") then
			existingInGame.FillColor = HIGHLIGHT_FILL_COLOR
			existingInGame.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
			existingInGame.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
			existingInGame.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
			runtime.highlight = existingInGame
			return existingInGame
		end
		existingInGame:Destroy()
	end

	local legacy = Workspace:FindFirstChild(HIGHLIGHT_NAME)
	if legacy ~= nil then
		if legacy:IsA("Highlight") then
			legacy.FillColor = HIGHLIGHT_FILL_COLOR
			legacy.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
			legacy.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
			legacy.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
			legacy.Parent = gameFolder
			runtime.highlight = legacy
			return legacy
		end
		legacy:Destroy()
	end

	local highlight = Instance.new("Highlight")
	highlight.Name = HIGHLIGHT_NAME
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = HIGHLIGHT_FILL_COLOR
	highlight.OutlineColor = HIGHLIGHT_OUTLINE_COLOR
	highlight.FillTransparency = HIGHLIGHT_FILL_TRANSPARENCY
	highlight.OutlineTransparency = HIGHLIGHT_OUTLINE_TRANSPARENCY
	highlight.Enabled = false
	highlight.Parent = gameFolder
	runtime.highlight = highlight
	return highlight
end

local function applyHighlight(model: Model?)
	local highlight = ensureHighlight()
	if model == nil then
		highlight.Adornee = nil
		highlight.Enabled = false
		return
	end

	highlight.Adornee = model
	highlight.Enabled = true
end

local function syncNpcStateFromService()
	local success, stateOrError = pcall(function()
		return NpcServiceClient:getState()
	end)
	if success and typeof(stateOrError) == "table" then
		runtime.cachedNpcState = stateOrError :: NpcServiceClientState
	end
end

local function syncBossStateFromService()
	local success, stateOrError = pcall(function()
		return BossServiceClient:getState()
	end)
	if success and typeof(stateOrError) == "table" then
		runtime.cachedBossState = stateOrError :: BossServiceClientState
	end
end

local function syncStateFromServices()
	syncNpcStateFromService()
	syncBossStateFromService()
end

local function getCachedSnapshot(runtimeId: string, entityKind: HoverEntityKind): HoverSnapshot?
	if entityKind == "Boss" then
		local cachedBossState = runtime.cachedBossState
		if cachedBossState ~= nil then
			local cachedSnapshot = cachedBossState.byId[runtimeId]
			if cachedSnapshot ~= nil then
				return cachedSnapshot
			end
		end

		syncBossStateFromService()
		cachedBossState = runtime.cachedBossState
		if cachedBossState == nil then
			return nil
		end

		return cachedBossState.byId[runtimeId]
	end

	local cachedState = runtime.cachedNpcState
	if cachedState ~= nil then
		local cachedSnapshot = cachedState.byId[runtimeId]
		if cachedSnapshot ~= nil then
			return cachedSnapshot
		end
	end

	syncNpcStateFromService()
	cachedState = runtime.cachedNpcState
	if cachedState == nil then
		return nil
	end

	return cachedState.byId[runtimeId]
end

local function clearHover()
	local currentState = entityInfoSlice.getEntityInfoState()
	if runtime.hoveredRuntimeId == nil and currentState.visible ~= true then
		applyHighlight(nil)
		return
	end

	runtime.hoveredEntityKind = nil
	runtime.hoveredRuntimeId = nil
	runtime.hoveredModel = nil
	applyHighlight(nil)
	entityInfoSlice.hideEntityInfo(ENTITY_HOVER_ID)
end

local function resolveHoveredEntity(targetRaw: any): (Model?, string?, HoverEntityKind?)
	local bossModel = BossServiceUtils.resolveRuntimeModelFromInstance(targetRaw)
	if bossModel ~= nil then
		local bossRuntimeId = BossServiceUtils.resolveRuntimeIdFromInstance(bossModel)
		if bossRuntimeId ~= nil and bossRuntimeId ~= "" then
			return bossModel, bossRuntimeId, "Boss"
		end
	end

	local model = NpcServiceUtils.resolveRuntimeModelFromInstance(targetRaw)
	if model == nil then
		return nil, nil, nil
	end

	local runtimeId = NpcServiceUtils.resolveRuntimeIdFromInstance(model)
	if runtimeId == nil or runtimeId == "" then
		return nil, nil, nil
	end

	return model, runtimeId, "Npc"
end

local function showHover(runtimeId: string, entityKind: HoverEntityKind, model: Model, mousePosition: Vector2)
	local snapshot = getCachedSnapshot(runtimeId, entityKind)
	if snapshot == nil then
		clearHover()
		return
	end

	local adornee = resolveModelAdornee(model)
	if adornee == nil then
		clearHover()
		return
	end

	runtime.hoveredEntityKind = entityKind
	runtime.hoveredRuntimeId = runtimeId
	runtime.hoveredModel = model
	applyHighlight(model)
	entityInfoSlice.showEntityInfo({
		hoverId = ENTITY_HOVER_ID,
		runtimeId = runtimeId,
		adornee = adornee,
		displayName = snapshot.displayName,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		mousePosition = mousePosition,
	})
end

local function refreshHoveredSnapshot()
	local entityKind = runtime.hoveredEntityKind
	local runtimeId = runtime.hoveredRuntimeId
	local hoveredModel = runtime.hoveredModel
	if entityKind == nil or runtimeId == nil or hoveredModel == nil or hoveredModel.Parent == nil then
		clearHover()
		return
	end

	local snapshot = getCachedSnapshot(runtimeId, entityKind)
	if snapshot == nil then
		clearHover()
		return
	end

	local adornee = resolveModelAdornee(hoveredModel)
	if adornee == nil then
		clearHover()
		return
	end

	local currentState = entityInfoSlice.getEntityInfoState()
	entityInfoSlice.showEntityInfo({
		hoverId = ENTITY_HOVER_ID,
		runtimeId = runtimeId,
		adornee = adornee,
		displayName = snapshot.displayName,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		mousePosition = currentState.mousePosition,
	})
	applyHighlight(hoveredModel)
end

local function stepHoverState()
	local currentState = entityInfoSlice.getEntityInfoState()
	local mousePosition = resolveMouseGuiPosition(currentState.mousePosition)
	entityInfoSlice.updateMousePosition(mousePosition)

	local mouse = runtime.mouse
	if mouse == nil then
		clearHover()
		return
	end

	local targetPart = mouse.Target
	if targetPart == nil then
		clearHover()
		return
	end

	local hoveredModel, runtimeId, entityKind = resolveHoveredEntity(targetPart)
	if hoveredModel == nil or runtimeId == nil or entityKind == nil then
		clearHover()
		return
	end

	if currentState.visible == true
		and currentState.runtimeId == runtimeId
		and runtime.hoveredEntityKind == entityKind
		and runtime.hoveredRuntimeId == runtimeId
		and runtime.hoveredModel == hoveredModel then
		applyHighlight(hoveredModel)
		return
	end

	showHover(runtimeId, entityKind, hoveredModel, mousePosition)
end

function entityInfoThunks.start(): () -> ()
	if runtime.started then
		return entityInfoThunks.stop
	end

	runtime.started = true
	runtime.localPlayer = Players.LocalPlayer
	if runtime.localPlayer ~= nil then
		local ok, resolvedMouse = pcall(function()
			return (runtime.localPlayer :: Player):GetMouse()
		end)
		if ok and resolvedMouse ~= nil then
			runtime.mouse = resolvedMouse
		end
	end

	syncStateFromServices()
	ensureHighlight()

	local npcStateChangedSignal = NpcServiceClient.stateChanged
	if npcStateChangedSignal ~= nil then
		runtime.npcStateChangedConnection = npcStateChangedSignal:Connect(function(nextState: NpcServiceClientState)
			runtime.cachedNpcState = nextState
			refreshHoveredSnapshot()
		end)
	end

	local bossStateChangedSignal = BossServiceClient.stateChanged
	if bossStateChangedSignal ~= nil then
		runtime.bossStateChangedConnection = bossStateChangedSignal:Connect(function(nextState: BossServiceClientState)
			runtime.cachedBossState = nextState
			refreshHoveredSnapshot()
		end)
	end

	runtime.renderSteppedConnection = RunService.RenderStepped:Connect(function()
		if not runtime.started then
			return
		end
		stepHoverState()
	end)

	return entityInfoThunks.stop
end

function entityInfoThunks.stop()
	ConnectionUtils.disconnectMany({
		runtime.npcStateChangedConnection,
		runtime.bossStateChangedConnection,
		runtime.renderSteppedConnection,
	})
	runtime.npcStateChangedConnection = nil
	runtime.bossStateChangedConnection = nil
	runtime.renderSteppedConnection = nil

	runtime.started = false
	runtime.cachedNpcState = nil
	runtime.cachedBossState = nil
	runtime.hoveredEntityKind = nil
	runtime.hoveredRuntimeId = nil
	runtime.hoveredModel = nil
	runtime.mouse = nil
	runtime.localPlayer = nil
	entityInfoSlice.resetEntityInfoState()

	local highlight = runtime.highlight
	if highlight ~= nil then
		highlight:Destroy()
		runtime.highlight = nil
	end
end

function entityInfoThunks.syncHover()
	stepHoverState()
end

function entityInfoThunks.getEntityInfoState(): EntityInfoState
	return entityInfoSlice.getEntityInfoState()
end

return entityInfoThunks
