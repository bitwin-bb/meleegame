--!strict
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Cleanup = require(script.Parent.internal.cleanup)
local PlatformServiceClient = require(script:FindFirstAncestor("game").Client.Services.PlatformServiceClient)
local PlatformServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlatformServiceUtils)
local React = require(ReplicatedStorage.Packages.React)

type PlatformState = PlatformServiceUtils.PlatformState

export type ViewportState = {
	viewport: Vector2,
	safeInsetTopLeft: Vector2,
	safeInsetBottomRight: Vector2,
	guiInsetTopLeft: Vector2,
	guiInsetBottomRight: Vector2,
	camera: Camera?,
	platformState: PlatformState?,
	uiScaleSnapshot: any?,
}

export type ViewportOptions = {
	usePlatformState: boolean?,
}

local FALLBACK_VIEWPORT = Vector2.new(1920, 1080)

local function resolveCurrentViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local viewportSize = camera.ViewportSize
		return Vector2.new(math.max(1, viewportSize.X), math.max(1, viewportSize.Y))
	end
	return FALLBACK_VIEWPORT
end

local function resolveViewportState(usePlatformState: boolean): ViewportState
	local camera = Workspace.CurrentCamera
	local guiInsetTopLeft, guiInsetBottomRight = GuiService:GetGuiInset()
	local platformState = nil :: PlatformState?
	if usePlatformState then
		local ok, resolvedState = pcall(function()
			return PlatformServiceClient:getState()
		end)
		if ok and typeof(resolvedState) == "table" then
			platformState = resolvedState :: PlatformState
		end
	end

	local uiScaleSnapshot = nil
	local okUIScale, uiScale = pcall(function()
		return PlatformServiceClient:getUIScale()
	end)
	if okUIScale and uiScale ~= nil and typeof((uiScale :: any).getSnapshot) == "function" then
		local okSnapshot, resolvedSnapshot = pcall(function()
			return (uiScale :: any):getSnapshot()
		end)
		if okSnapshot and typeof(resolvedSnapshot) == "table" then
			uiScaleSnapshot = resolvedSnapshot
		end
	end

	local safeInsetTopLeft = guiInsetTopLeft
	local safeInsetBottomRight = guiInsetBottomRight
	if uiScaleSnapshot ~= nil and typeof((uiScaleSnapshot :: any).safeTopLeft) == "Vector2" then
		safeInsetTopLeft = (uiScaleSnapshot :: any).safeTopLeft
	end
	if uiScaleSnapshot ~= nil and typeof((uiScaleSnapshot :: any).safeBottomRight) == "Vector2" then
		safeInsetBottomRight = (uiScaleSnapshot :: any).safeBottomRight
	end

	local viewport = if platformState ~= nil and typeof(platformState.viewport) == "Vector2"
		then platformState.viewport
		else resolveCurrentViewportSize()

	return {
		viewport = viewport,
		safeInsetTopLeft = safeInsetTopLeft,
		safeInsetBottomRight = safeInsetBottomRight,
		guiInsetTopLeft = guiInsetTopLeft,
		guiInsetBottomRight = guiInsetBottomRight,
		camera = camera,
		platformState = platformState,
		uiScaleSnapshot = uiScaleSnapshot,
	}
end

local function useViewport(options: ViewportOptions?): ViewportState
	local usePlatformState = if options ~= nil and options.usePlatformState ~= nil
		then options.usePlatformState == true
		else true
	local viewportState, setViewportState = React.useState(function(): ViewportState
		return resolveViewportState(usePlatformState)
	end)

	React.useEffect(function()
		local viewportConnection = nil

		local function refresh()
			setViewportState(resolveViewportState(usePlatformState))
		end

		local function bindViewportConnection()
			Cleanup.Call(viewportConnection)
			viewportConnection = nil

			local camera = Workspace.CurrentCamera
			if camera == nil then
				return
			end

			viewportConnection = camera:GetPropertyChangedSignal("ViewportSize"):Connect(refresh)
		end

		local stateSignal = PlatformServiceClient:getStateChangedSignal()
		local uiScaleSignal = PlatformServiceClient:getUIScaleChangedSignal()
		local stateConnection = if stateSignal ~= nil and typeof((stateSignal :: any).Connect) == "function"
			then (stateSignal :: any):Connect(refresh)
			else nil
		local uiScaleConnection = if uiScaleSignal ~= nil
				and typeof((uiScaleSignal :: any).Connect) == "function"
			then (uiScaleSignal :: any):Connect(refresh)
			else nil
		local cameraChangedConnection = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
			bindViewportConnection()
			refresh()
		end)

		bindViewportConnection()
		refresh()

		return function()
			Cleanup.Call(viewportConnection)
			Cleanup.Call(stateConnection)
			Cleanup.Call(uiScaleConnection)
			cameraChangedConnection:Disconnect()
		end
	end, { usePlatformState })

	return viewportState
end

return useViewport
