--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local React = require(ReplicatedStorage.Packages.React)
local WorldGenerationServiceClient =
	require(script:FindFirstAncestor("game").Client.Services.WorldGenerationServiceClient)
local padSlice = require(script:FindFirstAncestor("game").Client.UI.features.pad.state.padSlice)
local usePad = require(script:FindFirstAncestor("game").Client.UI.features.pad.hooks.usePad)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type PadState = padSlice.PadState

type PadScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

local e: typeof(React.createElement) = React.createElement

local BILLBOARD_SIZE = Vector2.new(72, 72)
local INDICATOR_SIZE = 44
local IDLE_EXPANDED_SIZE = Vector2.new(52, 52)
local IDLE_PHASE_DURATION = 0.7
local POSITION_EPSILON = 1e-4

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

local function offsetsEqual(a: Vector3?, b: Vector3?): boolean
	if a == nil or b == nil then
		return a == b
	end

	return (a - b).Magnitude <= POSITION_EPSILON
end

local function resolveHoverWorldOffset(rootPart: BasePart): Vector3?
	local hoverWorldPosition = WorldGenerationServiceClient:getHoveredTerrainWorldPosition()
	if hoverWorldPosition == nil then
		return nil
	end

	return hoverWorldPosition - rootPart.Position
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
	local ringOffset, setRingOffset = React.useState(nil :: Vector3?)
	local ringOffsetRef = React.useRef(nil :: Vector3?)
	local idlePad = usePad({
		enabled = ringOffset ~= nil,
		collapsedSize = Vector2.new(INDICATOR_SIZE, INDICATOR_SIZE),
		expandedSize = IDLE_EXPANDED_SIZE,
		phaseDuration = IDLE_PHASE_DURATION,
	})

	local function applyRingOffset(nextOffset: Vector3?)
		if offsetsEqual(ringOffsetRef.current, nextOffset) then
			return
		end

		ringOffsetRef.current = nextOffset
		setRingOffset(nextOffset)
	end

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
		if rootPart == nil or state.visible ~= true or resolvedProps.visible == false then
			applyRingOffset(nil)
			return nil
		end

		local function refreshRingOffset()
			applyRingOffset(resolveHoverWorldOffset(rootPart))
		end
		refreshRingOffset()

		local connection = RunService.RenderStepped:Connect(refreshRingOffset)
		return function()
			connection:Disconnect()
		end
	end, { rootPart, resolvedProps.visible, state.visible })

	if resolvedProps.visible == false or state.visible ~= true or rootPart == nil then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 980
	local imageId = state.imageId
	if imageId == "" then
		return nil
	end

	if ringOffset == nil then
		return nil
	end

	return e("BillboardGui", {
		Adornee = rootPart,
		AlwaysOnTop = true,
		Enabled = true,
		LightInfluence = 0,
		MaxDistance = 80,
		ResetOnSpawn = false,
		Size = UDim2.fromOffset(BILLBOARD_SIZE.X, BILLBOARD_SIZE.Y),
		StudsOffsetWorldSpace = ringOffset,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
	}, {
		ActiveIndicator = renderStickIndicator(imageId, idlePad.size, zIndex + 1),
	})
end
