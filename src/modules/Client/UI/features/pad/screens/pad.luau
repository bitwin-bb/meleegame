--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local BuildServiceClient = require(script:FindFirstAncestor("game").Client.Services.BuildServiceClient)
local BuildServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.BuildServiceUtils)
local GamepadPointer = require(script:FindFirstAncestor("game").Shared.Modules.Platform.GamepadPointer)
local React = require(ReplicatedStorage.Packages.React)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)
local padSlice = require(script:FindFirstAncestor("game").Client.UI.features.pad.state.padSlice)
local usePad = require(script:FindFirstAncestor("game").Client.UI.features.pad.hooks.usePad)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type PadState = padSlice.PadState
type BuildServiceState = BuildServiceUtils.BuildServiceState

type PadScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

type ActiveIndicatorState = {
	position: Vector2,
	hideOnCenter: boolean,
}

local e: typeof(React.createElement) = React.createElement

local TILE_SIZE_STUDS = GamepadPointer.DEFAULT_TILE_SIZE_STUDS
local BILLBOARD_SIZE = Vector2.new(72, 72)
local INDICATOR_SIZE = 44
local IDLE_EXPANDED_SIZE = Vector2.new(52, 52)
local IDLE_PHASE_DURATION = 0.7
local RETURN_SPEED = 10
local BUILD_PREVIEW_PART_NAME = "BuildPreviewBinder"

local function resolveCharacterRootPart(localPlayer: Player): BasePart?
	local character = localPlayer.Character
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

local function resolveBuildState(): BuildServiceState?
	local state = (BuildServiceClient :: any).state
	if typeof(state) ~= "table" then
		return nil
	end
	if typeof((state :: any).worldOrigin) ~= "Vector3" then
		return nil
	end
	if typeof((state :: any).tileSize) ~= "number" then
		return nil
	end
	if typeof((state :: any).basePlaneX) ~= "number" then
		return nil
	end

	return state :: BuildServiceState
end

local function resolveVisibleBuildPreviewPosition(): Vector3?
	local visualFolder = (BuildServiceClient :: any).visualFolder
	if typeof(visualFolder) ~= "Instance" then
		return nil
	end

	local previewPart = (visualFolder :: Instance):FindFirstChild(BUILD_PREVIEW_PART_NAME)
	if previewPart == nil or not previewPart:IsA("BasePart") then
		return nil
	end
	local previewBasePart = previewPart :: BasePart
	if previewBasePart.Transparency >= 1 then
		return nil
	end

	return previewBasePart.Position
end

local function resolveTerrainHoverPosition(): Vector3?
	local runtime = (WorldGenerationServiceClient :: any).hoveredTerrainRuntime
	if typeof(runtime) ~= "table" then
		return nil
	end

	local hoverPart = (runtime :: any).hoverPart
	if typeof(hoverPart) ~= "Instance" or not hoverPart:IsA("BasePart") then
		return nil
	end
	local hoverBasePart = hoverPart :: BasePart
	if hoverBasePart.Parent == nil then
		return nil
	end

	return hoverBasePart.Position
end

local function resolveSelectedTileCoordinate(): (number?, number?)
	local tileX = BuildServiceUtils.sanitizeTileCoordinate((WorldGenerationServiceClient :: any).hoveredTerrainTileX)
	local tileY = BuildServiceUtils.sanitizeTileCoordinate((WorldGenerationServiceClient :: any).hoveredTerrainTileY)
	if tileX ~= nil and tileY ~= nil then
		return tileX, tileY
	end

	tileX = BuildServiceUtils.sanitizeTileCoordinate((BuildServiceClient :: any).cursorTileX)
	tileY = BuildServiceUtils.sanitizeTileCoordinate((BuildServiceClient :: any).cursorTileY)
	if tileX ~= nil and tileY ~= nil then
		return tileX, tileY
	end

	return nil, nil
end

local function resolveSelectedTileWorldPosition(): Vector3?
	local previewPosition = resolveVisibleBuildPreviewPosition()
	if previewPosition ~= nil then
		return previewPosition
	end

	local terrainHoverPosition = resolveTerrainHoverPosition()
	if terrainHoverPosition ~= nil then
		return terrainHoverPosition
	end

	local tileX, tileY = resolveSelectedTileCoordinate()
	local state = resolveBuildState()
	if tileX == nil or tileY == nil or state == nil then
		return nil
	end

	return BuildServiceUtils.tileToWorldCenter(tileX, tileY, state.worldOrigin, state.tileSize, state.basePlaneX)
end

local function getWorldOffset(position: Vector2, rootPart: BasePart, preferSelectedTile: boolean): Vector3
	if preferSelectedTile then
		local selectedTileWorldPosition = resolveSelectedTileWorldPosition()
		if selectedTileWorldPosition ~= nil then
			return selectedTileWorldPosition - rootPart.Position
		end
	end

	return GamepadPointer.resolveWorldOffsetForScreenVector(position, TILE_SIZE_STUDS, rootPart) or Vector3.zero
end

local function renderStickIndicator(imageId: string, size: Vector2, zIndex: number)
	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = imageId,
		ImageTransparency = 0.08,
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(math.floor(size.X + 0.5), math.floor(size.Y + 0.5)),
		ZIndex = zIndex,
	})
end

return function(props: PadScreenProps?): React.ReactNode
	local resolvedProps: PadScreenProps = if props ~= nil then props else {}
	local localPlayer = Players.LocalPlayer
	local state = (useStore(padSlice.padStateAtom) :: PadState?) or padSlice.getPadState()
	local rootPart, setRootPart = React.useState(resolveCharacterRootPart(localPlayer) :: BasePart?)
	local activeIndicator, setActiveIndicator = React.useState(nil :: ActiveIndicatorState?)
	local idlePad = usePad({
		enabled = activeIndicator ~= nil,
		collapsedSize = Vector2.new(INDICATOR_SIZE, INDICATOR_SIZE),
		expandedSize = IDLE_EXPANDED_SIZE,
		phaseDuration = IDLE_PHASE_DURATION,
	})

	React.useEffect(function()
		local characterConnections: { RBXScriptConnection } = {}

		local function disconnectCharacterConnections()
			for _, connection in characterConnections do
				connection:Disconnect()
			end
			table.clear(characterConnections)
		end

		local function refreshRootPart()
			setRootPart(resolveCharacterRootPart(localPlayer))
		end

		local function bindCharacter(character: Model?)
			disconnectCharacterConnections()
			if character == nil then
				setRootPart(nil)
				return
			end

			refreshRootPart()
			table.insert(characterConnections, character.ChildAdded:Connect(refreshRootPart))
			table.insert(characterConnections, character.ChildRemoved:Connect(refreshRootPart))
			table.insert(
				characterConnections,
				character:GetPropertyChangedSignal("PrimaryPart"):Connect(refreshRootPart)
			)
		end

		bindCharacter(localPlayer.Character)

		local characterAddedConnection = localPlayer.CharacterAdded:Connect(function(character: Model)
			bindCharacter(character)
		end)
		local characterRemovingConnection = localPlayer.CharacterRemoving:Connect(function()
			disconnectCharacterConnections()
			setRootPart(nil)
		end)

		return function()
			characterAddedConnection:Disconnect()
			characterRemovingConnection:Disconnect()
			disconnectCharacterConnections()
		end
	end, { localPlayer })

	React.useEffect(function()
		if state.rightStick.active then
			setActiveIndicator({
				position = state.rightStick.position,
				hideOnCenter = false,
			})
			return nil
		end

		if state.leftStick.active then
			setActiveIndicator({
				position = state.leftStick.position,
				hideOnCenter = false,
			})
			return nil
		end

		setActiveIndicator(function(current: ActiveIndicatorState?): ActiveIndicatorState?
			if current == nil then
				return nil
			end
			return {
				position = current.position,
				hideOnCenter = true,
			}
		end)

		return nil
	end, {
		state.leftStick.active,
		state.leftStick.position,
		state.rightStick.active,
		state.rightStick.position,
	})

	React.useEffect(function()
		local current = activeIndicator
		if current == nil then
			return nil
		end
		if current.hideOnCenter ~= true then
			return nil
		end
		if current.position.Magnitude <= 1e-4 then
			setActiveIndicator(nil)
			return nil
		end

		local connection = RunService.RenderStepped:Connect(function(deltaTime: number)
			setActiveIndicator(function(active: ActiveIndicatorState?): ActiveIndicatorState?
				if active == nil then
					return nil
				end
				if active.hideOnCenter ~= true then
					return active
				end

				local distance = active.position.Magnitude
				if distance <= 1e-4 then
					return nil
				end

				local stepDistance = RETURN_SPEED * deltaTime
				local nextPosition = if stepDistance >= distance
					then Vector2.zero
					else active.position.Unit * (distance - stepDistance)

				return {
					position = nextPosition,
					hideOnCenter = true,
				}
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, { activeIndicator })

	if resolvedProps.visible == false or state.visible ~= true or rootPart == nil then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 980
	local imageId = state.imageId
	if imageId == "" then
		return nil
	end

	if activeIndicator == nil then
		return nil
	end

	local worldOffset = getWorldOffset(activeIndicator.position, rootPart, activeIndicator.hideOnCenter ~= true)

	return e("BillboardGui", {
		Adornee = rootPart,
		AlwaysOnTop = true,
		Enabled = true,
		LightInfluence = 0,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y),
		StudsOffsetWorldSpace = worldOffset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		ActiveIndicator = renderStickIndicator(imageId, idlePad.size, zIndex + 1),
	})
end
