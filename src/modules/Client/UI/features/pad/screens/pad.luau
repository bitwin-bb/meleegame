--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GamepadPointer = require(script:FindFirstAncestor("game").Shared.Modules.Platform.GamepadPointer)
local GamepadTargetServiceClient = require(script:FindFirstAncestor("game").Client.Services.GamepadTargetServiceClient)
local React = require(ReplicatedStorage.Packages.React)
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

local TILE_SIZE_STUDS = GamepadPointer.DEFAULT_TILE_SIZE_STUDS
local BILLBOARD_SIZE = Vector2.new(72, 72)
local INDICATOR_SIZE = 44
local IDLE_EXPANDED_SIZE = Vector2.new(52, 52)
local IDLE_PHASE_DURATION = 0.7
local RETURN_SPEED = 10

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

local function getWorldOffset(position: Vector2, rootPart: BasePart, selectedWorldPosition: Vector3?): Vector3
	if selectedWorldPosition ~= nil then
		return selectedWorldPosition - rootPart.Position
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
	local selectedWorldPosition, setSelectedWorldPosition =
		React.useState(GamepadTargetServiceClient.getTargetWorldPosition() :: Vector3?)
	local idlePad = usePad({
		enabled = activeIndicator ~= nil or selectedWorldPosition ~= nil,
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
		setSelectedWorldPosition(GamepadTargetServiceClient.getTargetWorldPosition())

		return GamepadTargetServiceClient.onTargetChanged(function(worldPosition: Vector3?)
			setSelectedWorldPosition(worldPosition)
		end)
	end, {})

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

	if activeIndicator == nil and selectedWorldPosition == nil then
		return nil
	end

	local fallbackPosition = if activeIndicator ~= nil
		then activeIndicator.position
		else GamepadTargetServiceClient.getTargetScreenVector() or Vector2.zero
	local worldOffset = getWorldOffset(fallbackPosition, rootPart, selectedWorldPosition)

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
