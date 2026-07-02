local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Sift = require(ReplicatedStorage.Packages.Sift)
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local BossServiceUtils = require("BossServiceUtils")
local ImageIds = require("ImageIds")
local Layer = require("Layer")
local Marker = require("Marker")
local React = require(ReplicatedStorage.Packages.React)
local markerSlice = require("MarkerSlice")
local markerThunks = require("MarkerThunks")
local useStore = require("useCoreStore")

type MarkerState = markerSlice.MarkerState
type BossSnapshot = BossServiceUtils.BossSnapshot
type BossId = BossServiceUtils.BossId

type MarkerScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

type RenderedMarker = {
	runtimeId: string,
	icon: string,
	position: Vector2,
	rotation: number,
}

local e: typeof(React.createElement) = React.createElement

local EDGE_PADDING = 72
local MARKER_SIZE = UDim2.fromOffset(70, 70)
local ROTATION_OFFSET_DEGREES = 90
local DEFAULT_DIRECTION = Vector2.new(0, -1)
local MISSING_ASSET_ERROR = "no asset found!"

local BOSS_ICON_BY_ID: { [BossId]: string } = {
	EyeOfCthulhu = ImageIds.eocIcon,
}

local function GetBossIcon(bossId: BossId): string
	local icon = BOSS_ICON_BY_ID[bossId]
	if typeof(icon) == "string" and icon ~= "" then
		return icon
	end
	error(MISSING_ASSET_ERROR, 0)
end

local function GetBossPosition(snapshot: BossSnapshot): Vector3?
	if snapshot.position ~= nil then
		return snapshot.position
	end
	return snapshot.motion.position
end

local function isBossSafelyOnScreen(viewportPoint: Vector3, viewportSize: Vector2): boolean
	if viewportPoint.Z <= 0 then
		return false
	end

	return viewportPoint.X >= EDGE_PADDING
		and viewportPoint.X <= viewportSize.X - EDGE_PADDING
		and viewportPoint.Y >= EDGE_PADDING
		and viewportPoint.Y <= viewportSize.Y - EDGE_PADDING
end

local function GetDirection(viewportPoint: Vector3, viewportSize: Vector2): Vector2
	local center = viewportSize * 0.5
	local direction = Vector2.new(viewportPoint.X, viewportPoint.Y) - center
	if viewportPoint.Z <= 0 then
		direction = -direction
	end

	if direction.Magnitude <= 1e-4 then
		return DEFAULT_DIRECTION
	end

	return direction.Unit
end

local function clampToViewportEdge(direction: Vector2, viewportSize: Vector2): Vector2
	local center = viewportSize * 0.5
	local safeHalfExtents = Vector2.new(math.max(24, center.X - EDGE_PADDING), math.max(24, center.Y - EDGE_PADDING))
	local safeDirection = if direction.Magnitude > 1e-4 then direction else DEFAULT_DIRECTION
	local scaleX = if math.abs(safeDirection.X) > 1e-4 then safeHalfExtents.X / math.abs(safeDirection.X) else math.huge
	local scaleY = if math.abs(safeDirection.Y) > 1e-4 then safeHalfExtents.Y / math.abs(safeDirection.Y) else math.huge
	local scale = math.min(scaleX, scaleY)

	return center + safeDirection * scale
end

local function areRenderedMarkersEqual(left: { RenderedMarker }, right: { RenderedMarker }): boolean
	if #left ~= #right then
		return false
	end

	for index = 1, #left do
		local leftMarker = left[index]
		local rightMarker = right[index]
		if leftMarker.runtimeId ~= rightMarker.runtimeId or leftMarker.icon ~= rightMarker.icon then
			return false
		end
		if
			math.abs(leftMarker.position.X - rightMarker.position.X) > 0.5
			or math.abs(leftMarker.position.Y - rightMarker.position.Y) > 0.5
			or math.abs(leftMarker.rotation - rightMarker.rotation) > 0.5
		then
			return false
		end
	end

	return true
end

local function buildRenderedMarkers(camera: Camera?, markerState: MarkerState): { RenderedMarker }
	if camera == nil then
		return {}
	end

	local viewportSize = camera.ViewportSize
	if viewportSize.X <= 0 or viewportSize.Y <= 0 then
		return {}
	end

	local renderedMarkers = Sift.Array.create(#markerState.orderedIds)
	for _, runtimeId in markerState.orderedIds do
		local snapshot = markerState.byId[runtimeId]
		if snapshot == nil or snapshot.isAlive ~= true then
			continue
		end

		local bossPosition = GetBossPosition(snapshot)
		if bossPosition == nil then
			continue
		end

		local viewportPoint, isOnScreen = camera:WorldToViewportPoint(bossPosition)
		if isOnScreen and isBossSafelyOnScreen(viewportPoint, viewportSize) then
			continue
		end

		local direction = GetDirection(viewportPoint, viewportSize)
		local markerPosition = clampToViewportEdge(direction, viewportSize)
		local rotation = math.deg(math.atan2(direction.Y, direction.X)) + ROTATION_OFFSET_DEGREES

		renderedMarkers = Sift.Array.append(renderedMarkers, {
			runtimeId = runtimeId,
			icon = GetBossIcon(snapshot.bossId),
			position = markerPosition,
			rotation = rotation,
		})
	end

	return renderedMarkers
end

return function(props: MarkerScreenProps): React.ReactNode
	local markerState = (useStore(markerSlice.markerStateAtom) :: MarkerState?) or markerSlice.getMarkerState()
	local isMarkerReady = (useStore(markerSlice.markerReadyAtom) :: boolean?) or markerSlice.isMarkerReady()
	local renderedMarkers, setRenderedMarkers = React.useState({} :: { RenderedMarker })
	local markerStateRef = React.useRef(markerState)
	local markerReadyRef = React.useRef(isMarkerReady)

	markerStateRef.current = markerState
	markerReadyRef.current = isMarkerReady

	React.useEffect(function()
		local stop = markerThunks.Start()

		return function()
			stop()
		end
	end, {})

	React.useEffect(function()
		local connection = RunService.RenderStepped:Connect(function()
			if markerReadyRef.current ~= true then
				setRenderedMarkers(function(current: { RenderedMarker }): { RenderedMarker }
					if #current == 0 then
						return current
					end
					return {}
				end)
				return
			end

			local nextMarkers = buildRenderedMarkers(Workspace.CurrentCamera, markerStateRef.current)
			setRenderedMarkers(function(current: { RenderedMarker }): { RenderedMarker }
				if areRenderedMarkersEqual(current, nextMarkers) then
					return current
				end
				return nextMarkers
			end)
		end)

		return function()
			connection:Disconnect()
		end
	end, {})

	if props.visible == false or isMarkerReady ~= true or #renderedMarkers <= 0 then
		return nil
	end

	local zIndex = props.zIndex or 165
	local children: { React.ReactNode } = {}
	for _, renderedMarker in renderedMarkers do
		children[#children + 1] = e(Marker, {
			icon = renderedMarker.icon,
			position = renderedMarker.position,
			rotation = renderedMarker.rotation,
			size = MARKER_SIZE,
			zIndex = zIndex + 1,
		})
	end

	return e(Layer, {
		layoutOrder = props.layoutOrder or 165,
		zIndex = zIndex,
		active = false,
		native = {
			Selectable = false,
		},
		children = children,
	})
end
