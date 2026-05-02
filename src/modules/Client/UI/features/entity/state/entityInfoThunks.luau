--!strict
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local BossServiceClient = require(script:FindFirstAncestor("game").Client.Services.BossServiceClient)
local BossServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BossServiceUtils)
local ConnectionUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.ConnectionUtils)
local CoreRuntime = require(script:FindFirstAncestor("game").Shared.Modules.Core.Runtime)
local GamepadPointer = require(script:FindFirstAncestor("game").Shared.Modules.Platform.GamepadPointer)
local NpcServiceClient = require(script:FindFirstAncestor("game").Client.Services.NpcServiceClient)
local NpcServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.NpcServiceUtils)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Modules.Core.WorkspaceFolders)
local entityInfoSlice = require(script:FindFirstAncestor("game").Client.UI.features.entity.state.entityInfoSlice)

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
local ENTITY_HOVER_WORLD_RADIUS = 2.5

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

local function shouldUseGamepadWorldHover(): boolean
	return PlatformServiceClient:isGamepad() and PlatformServiceClient:getMachineFamily() ~= "desktop"
end

local function resolveCharacterRootPart(playerRaw: any): BasePart?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end

	local character = (playerRaw :: Player).Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function resolveGamepadNav(): any?
	local runtimeContext = nil
	local ok, runtimeOrError = pcall(function()
		return CoreRuntime.getClientRuntime()
	end)
	if ok then
		runtimeContext = runtimeOrError
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).init) == "function" then
		pcall(function()
			(runtimeContext :: any):init()
		end)
	end

	if runtimeContext ~= nil and typeof((runtimeContext :: any).getGamepadNav) == "function" then
		local didResolve, gamepadNavOrError = pcall(function()
			return (runtimeContext :: any):getGamepadNav()
		end)
		if didResolve then
			return gamepadNavOrError
		end
	end

	if runtimeContext ~= nil then
		return (runtimeContext :: any).gamepadNav
	end

	return nil
end

local function resolveGamepadWorldPosition(): Vector3?
	local gamepadNav = resolveGamepadNav()
	if gamepadNav == nil or typeof((gamepadNav :: any).getThumbstickState) ~= "function" then
		return nil
	end

	local ok, snapshotOrError = pcall(function()
		return (gamepadNav :: any):getThumbstickState()
	end)
	if not ok or typeof(snapshotOrError) ~= "table" then
		return nil
	end

	local screenVector = GamepadPointer.resolveOwnedVector(snapshotOrError)
	if typeof(screenVector) ~= "Vector2" then
		return nil
	end

	local rootPart = resolveCharacterRootPart(runtime.localPlayer)
	if rootPart == nil then
		return nil
	end

	local worldOffset =
		GamepadPointer.resolveWorldOffsetForScreenVector(screenVector, GamepadPointer.DEFAULT_TILE_SIZE_STUDS, rootPart)
	if worldOffset == nil then
		return nil
	end

	return rootPart.Position + worldOffset
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

local function resolveHoverGuiPositionFromWorldPosition(worldPosition: Vector3, fallback: Vector2): Vector2
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return fallback
	end

	local viewportPosition, isOnScreen = camera:WorldToViewportPoint(worldPosition)
	if not isOnScreen then
		return fallback
	end

	return toGuiPosition(Vector2.new(viewportPosition.X, viewportPosition.Y))
end

local function resolveHoveredEntityFromWorldPosition(worldPosition: Vector3): (Model?, string?, HoverEntityKind?)
	local overlapParams = OverlapParams.new()
	overlapParams.FilterType = Enum.RaycastFilterType.Exclude
	overlapParams.MaxParts = 32

	local success, parts = pcall(function()
		return Workspace:GetPartBoundsInRadius(worldPosition, ENTITY_HOVER_WORLD_RADIUS, overlapParams)
	end)
	if not success or type(parts) ~= "table" then
		return nil, nil, nil
	end

	local bestDistance = math.huge
	local bestModel = nil :: Model?
	local bestRuntimeId = nil :: string?
	local bestEntityKind = nil :: HoverEntityKind?

	for _, part in parts do
		if not part:IsA("BasePart") then
			continue
		end

		local hoveredModel, runtimeId, entityKind = resolveHoveredEntity(part)
		if hoveredModel == nil or runtimeId == nil or entityKind == nil then
			continue
		end

		local samplePosition = part.Position
		local adornee = resolveModelAdornee(hoveredModel)
		if adornee ~= nil then
			samplePosition = adornee.Position
		end

		local distance = (samplePosition - worldPosition).Magnitude
		if distance < bestDistance then
			bestDistance = distance
			bestModel = hoveredModel
			bestRuntimeId = runtimeId
			bestEntityKind = entityKind
		end
	end

	return bestModel, bestRuntimeId, bestEntityKind
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
	if shouldUseGamepadWorldHover() then
		local worldPosition = resolveGamepadWorldPosition()
		if worldPosition == nil then
			clearHover()
			return
		end

		local hoverPosition = resolveHoverGuiPositionFromWorldPosition(worldPosition, currentState.mousePosition)
		entityInfoSlice.updateMousePosition(hoverPosition)

		local hoveredModel, runtimeId, entityKind = resolveHoveredEntityFromWorldPosition(worldPosition)
		if hoveredModel == nil or runtimeId == nil or entityKind == nil then
			clearHover()
			return
		end

		if
			currentState.visible == true
			and currentState.runtimeId == runtimeId
			and runtime.hoveredEntityKind == entityKind
			and runtime.hoveredRuntimeId == runtimeId
			and runtime.hoveredModel == hoveredModel
		then
			applyHighlight(hoveredModel)
			return
		end

		showHover(runtimeId, entityKind, hoveredModel, hoverPosition)
		return
	end

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

	if
		currentState.visible == true
		and currentState.runtimeId == runtimeId
		and runtime.hoveredEntityKind == entityKind
		and runtime.hoveredRuntimeId == runtimeId
		and runtime.hoveredModel == hoveredModel
	then
		applyHighlight(hoveredModel)
		return
	end

	showHover(runtimeId, entityKind, hoveredModel, mousePosition)
end

function entityInfoThunks.Start(): () -> ()
	if runtime.started then
		return entityInfoThunks.Stop
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

	return entityInfoThunks.Stop
end

function entityInfoThunks.Stop()
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

function entityInfoThunks.SyncHover()
	stepHoverState()
end

function entityInfoThunks.GetEntityInfoState(): EntityInfoState
	return entityInfoSlice.getEntityInfoState()
end

entityInfoThunks.start = entityInfoThunks.Start
entityInfoThunks.stop = entityInfoThunks.Stop
entityInfoThunks.syncHover = entityInfoThunks.SyncHover
entityInfoThunks.getEntityInfoState = entityInfoThunks.GetEntityInfoState

return entityInfoThunks
