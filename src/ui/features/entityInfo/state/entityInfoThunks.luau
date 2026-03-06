--!strict
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local ConnectionUtils = require(ReplicatedStorage.UI.core.utils.ConnectionUtils)
local entityInfoSlice = require(ReplicatedStorage.UI.features.entityInfo.state.entityInfoSlice)
local NpcServiceClient = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceClient)
local NpcServiceUtils = require(ReplicatedStorage.Shared.Services.NpcService.NpcServiceUtils)
local WorkspaceFolders = require(ReplicatedStorage.Shared.Modules.Core.WorkspaceFolders)

type EntityInfoState = entityInfoSlice.EntityInfoState
type NpcSnapshot = NpcServiceUtils.NpcSnapshot

type NpcServiceClientState = {
	byId: { [string]: NpcSnapshot },
	orderedIds: { string },
	updatedAt: number,
}

local entityInfoThunks = {}

local ENTITY_HOVER_ID = "npc_entity_hover"
local HIGHLIGHT_NAME = "EntityInfoHoverHighlight"
local HIGHLIGHT_FILL_COLOR = Color3.fromRGB(255, 236, 66)
local HIGHLIGHT_FILL_TRANSPARENCY = 0.38
local HIGHLIGHT_OUTLINE_TRANSPARENCY = 1

local runtime = {
	started = false,
	localPlayer = nil :: Player?,
	mouse = nil :: Mouse?,
	cachedNpcState = nil :: NpcServiceClientState?,
	hoveredRuntimeId = nil :: string?,
	hoveredModel = nil :: Model?,
	highlight = nil :: Highlight?,
	stateChangedConnection = nil :: RBXScriptConnection?,
	renderSteppedConnection = nil :: RBXScriptConnection?,
}

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
		return existing
	end

	local gameFolder = WorkspaceFolders.getOrCreateGameFolder()
	local existingInGame = gameFolder:FindFirstChild(HIGHLIGHT_NAME)
	if existingInGame ~= nil then
		if existingInGame:IsA("Highlight") then
			runtime.highlight = existingInGame
			return existingInGame
		end
		existingInGame:Destroy()
	end

	local legacy = Workspace:FindFirstChild(HIGHLIGHT_NAME)
	if legacy ~= nil then
		if legacy:IsA("Highlight") then
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

local function syncStateFromService()
	local success, stateOrError = pcall(function()
		return NpcServiceClient:getState()
	end)
	if success and typeof(stateOrError) == "table" then
		runtime.cachedNpcState = stateOrError :: NpcServiceClientState
	end
end

local function getCachedSnapshot(runtimeId: string): NpcSnapshot?
	local cachedState = runtime.cachedNpcState
	if cachedState ~= nil then
		local cachedSnapshot = cachedState.byId[runtimeId]
		if cachedSnapshot ~= nil then
			return cachedSnapshot
		end
	end

	syncStateFromService()
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

	runtime.hoveredRuntimeId = nil
	runtime.hoveredModel = nil
	applyHighlight(nil)
	entityInfoSlice.hideEntityInfo(ENTITY_HOVER_ID)
end

local function resolveHoveredNpc(targetRaw: any): (Model?, string?)
	local model = NpcServiceUtils.resolveRuntimeModelFromInstance(targetRaw)
	if model == nil then
		return nil, nil
	end

	local runtimeId = NpcServiceUtils.resolveRuntimeIdFromInstance(model)
	if runtimeId == nil or runtimeId == "" then
		return nil, nil
	end

	return model, runtimeId
end

local function showHover(runtimeId: string, model: Model, mousePosition: Vector2)
	local snapshot = getCachedSnapshot(runtimeId)
	if snapshot == nil then
		clearHover()
		return
	end

	runtime.hoveredRuntimeId = runtimeId
	runtime.hoveredModel = model
	applyHighlight(model)
	entityInfoSlice.showEntityInfo({
		hoverId = ENTITY_HOVER_ID,
		runtimeId = runtimeId,
		displayName = snapshot.displayName,
		hp = snapshot.hp,
		maxHp = snapshot.maxHp,
		mousePosition = mousePosition,
	})
end

local function refreshHoveredSnapshot()
	local runtimeId = runtime.hoveredRuntimeId
	local hoveredModel = runtime.hoveredModel
	if runtimeId == nil or hoveredModel == nil or hoveredModel.Parent == nil then
		clearHover()
		return
	end

	local snapshot = getCachedSnapshot(runtimeId)
	if snapshot == nil then
		clearHover()
		return
	end

	local currentState = entityInfoSlice.getEntityInfoState()
	entityInfoSlice.showEntityInfo({
		hoverId = ENTITY_HOVER_ID,
		runtimeId = runtimeId,
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

	local hoveredModel, runtimeId = resolveHoveredNpc(targetPart)
	if hoveredModel == nil or runtimeId == nil then
		clearHover()
		return
	end

	if currentState.visible == true
		and currentState.runtimeId == runtimeId
		and runtime.hoveredRuntimeId == runtimeId
		and runtime.hoveredModel == hoveredModel then
		applyHighlight(hoveredModel)
		return
	end

	showHover(runtimeId, hoveredModel, mousePosition)
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

	syncStateFromService()
	ensureHighlight()

	local stateChangedSignal = NpcServiceClient.stateChanged
	if stateChangedSignal ~= nil then
		runtime.stateChangedConnection = stateChangedSignal:Connect(function(nextState: NpcServiceClientState)
			runtime.cachedNpcState = nextState
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
		runtime.stateChangedConnection,
		runtime.renderSteppedConnection,
	})
	runtime.stateChangedConnection = nil
	runtime.renderSteppedConnection = nil

	runtime.started = false
	runtime.cachedNpcState = nil
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
