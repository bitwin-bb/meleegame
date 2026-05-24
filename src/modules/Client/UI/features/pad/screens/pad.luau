--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BillboardCard = require(script:FindFirstAncestor("game").Client.UI.core.components.BillboardCard)
local GamepadNav = require(script:FindFirstAncestor("game").Shared.Core.Platform.GamepadNav)
local GamepadPointer = require(script:FindFirstAncestor("game").Shared.Core.Platform.GamepadPointer)
local React = require(ReplicatedStorage.Packages.React)
local WorkspaceFolders = require(script:FindFirstAncestor("game").Shared.Core.WorkspaceFolders)
local padSlice = require(script:FindFirstAncestor("game").Client.UI.features.pad.state.padSlice)
local usePad = require(script:FindFirstAncestor("game").Client.UI.features.pad.hooks.usePad)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type PadState = padSlice.PadState

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

local WORLD_FOLDER_NAME = "WorldGeneration"
local BILLBOARD_SIZE = Vector2.new(640, 640)
local INDICATOR_SIZE = 44
local IDLE_EXPANDED_SIZE = Vector2.new(52, 52)
local IDLE_PHASE_DURATION = 0.7
local FALLBACK_PRESENTATION_RADIUS_PIXELS = 48
local RETURN_SPEED = 10
local THUMBSTICK_ACTIVE_EPSILON = GamepadNav.THUMBSTICK_ACTIVE_EPSILON

local function dependencyArray(...: any): { any }
	return { ... }
end

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

local function resolveWorldTileSizeStuds(): number
	local worldFolder = WorkspaceFolders.findFolderInGameOrWorkspace(WORLD_FOLDER_NAME)
	if worldFolder ~= nil then
		local tileSize = worldFolder:GetAttribute("TileSize")
		if typeof(tileSize) == "number" and tileSize == tileSize and tileSize > 0 then
			return tileSize
		end
	end

	return GamepadPointer.DEFAULT_TILE_SIZE_STUDS
end

local function resolvePresentationDeadzoneMagnitude(state: PadState): number
	return GamepadNav.resolveRemappedDeadzoneMagnitude(state.stickDeadzone, state.navigationDeadzone)
end

local function resolvePresentationVector(state: PadState, position: Vector2): Vector2
	local deadzoneMagnitude = resolvePresentationDeadzoneMagnitude(state)
	local magnitude = position.Magnitude
	if magnitude <= deadzoneMagnitude or magnitude <= THUMBSTICK_ACTIVE_EPSILON then
		return Vector2.zero
	end

	local scaledMagnitude = (magnitude - deadzoneMagnitude) / math.max(THUMBSTICK_ACTIVE_EPSILON, 1 - deadzoneMagnitude)
	return position.Unit * math.clamp(scaledMagnitude, 0, 1)
end

local function resolveBackendReachPixelOffset(rootPart: BasePart, vector: Vector2, tileSizeStuds: number): Vector2?
	local camera = Workspace.CurrentCamera
	if camera == nil then
		return nil
	end

	local worldOffset = GamepadPointer.resolveWorldOffsetForScreenVector(vector, tileSizeStuds, rootPart)
	if worldOffset == nil then
		return Vector2.zero
	end

	local rootViewportPosition = camera:WorldToViewportPoint(rootPart.Position)
	local targetViewportPosition = camera:WorldToViewportPoint(rootPart.Position + worldOffset)
	return Vector2.new(
		targetViewportPosition.X - rootViewportPosition.X,
		targetViewportPosition.Y - rootViewportPosition.Y
	)
end

local function getPresentationPixelOffset(state: PadState, position: Vector2, rootPart: BasePart): Vector2
	local presentationVector = resolvePresentationVector(state, position)
	if presentationVector.Magnitude <= THUMBSTICK_ACTIVE_EPSILON then
		return Vector2.zero
	end

	local tileSizeStuds = resolveWorldTileSizeStuds()
	local backendPixelOffset = resolveBackendReachPixelOffset(rootPart, presentationVector, tileSizeStuds)
	if backendPixelOffset ~= nil then
		return backendPixelOffset
	end

	return presentationVector * FALLBACK_PRESENTATION_RADIUS_PIXELS
end

local function isStickPresentationActive(state: PadState, stick: padSlice.PadStickState): boolean
	return stick.active and stick.magnitude > resolvePresentationDeadzoneMagnitude(state)
end

local function getPresentationPosition(state: PadState, position: Vector2, rootPart: BasePart): UDim2
	local pixelOffset = getPresentationPixelOffset(state, position, rootPart)
	return UDim2.fromOffset(BILLBOARD_SIZE.X * 0.5 + pixelOffset.X, BILLBOARD_SIZE.Y * 0.5 + pixelOffset.Y)
end

local function renderStickIndicator(
	state: PadState,
	imageId: string,
	position: Vector2,
	rootPart: BasePart,
	size: Vector2,
	zIndex: number
)
	return e("ImageLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Image = imageId,
		ImageTransparency = 0.08,
		Position = getPresentationPosition(state, position, rootPart),
		Size = UDim2.fromOffset(math.floor(size.X + 0.5), math.floor(size.Y + 0.5)),
		ZIndex = zIndex,
	})
end

return function(props: PadScreenProps?): React.ReactNode
	local resolvedProps: PadScreenProps = if props ~= nil then props else ({} :: any)
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
		if isStickPresentationActive(state, state.rightStick) then
			setActiveIndicator({
				position = state.rightStick.position,
				hideOnCenter = false,
			})
			return nil
		end

		if isStickPresentationActive(state, state.leftStick) then
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
	end, dependencyArray(
		state.leftStick.active,
		state.leftStick.position,
		state.rightStick.active,
		state.rightStick.position,
		state.stickDeadzone,
		state.navigationDeadzone
	))

	;(React.useEffect :: any)(function(): (() -> ())?
		local current = activeIndicator
		if current == nil then
			return nil
		end
		if current.hideOnCenter ~= true then
			return nil
		end
		if current.position.Magnitude <= THUMBSTICK_ACTIVE_EPSILON then
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
				if distance <= THUMBSTICK_ACTIVE_EPSILON then
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
	end, dependencyArray(activeIndicator))

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

	return e(BillboardCard, {
		adornee = rootPart,
		alwaysOnTop = true,
		enabled = true,
		lightInfluence = 0,
		maxDistance = 80,
		size = UDim2.fromOffset(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y),
		studsOffset = Vector3.zero,
		studsOffsetWorldSpace = Vector3.zero,
		zIndexBehavior = Enum.ZIndexBehavior.Sibling,
		cardVisible = false,
		nativeBillboard = {
			ResetOnSpawn = false,
		},
	}, {
		ActiveIndicator = renderStickIndicator(
			state,
			imageId,
			activeIndicator.position,
			rootPart,
			idlePad.size,
			zIndex + 1
		),
	})
end
