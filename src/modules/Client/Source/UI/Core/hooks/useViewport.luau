local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GuiService = game:GetService("GuiService")
local Workspace = game:GetService("Workspace")

local Cleanup = require("Cleanup")
local PlatformServiceUtils = require("PlatformServiceUtils")
local React: any = require(ReplicatedStorage.Packages.React)

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
local platformServiceClient = nil :: any?

local function getPlatformServiceClient(): any
	if platformServiceClient == nil then
		platformServiceClient = require("PlatformServiceClient")
	end
	return platformServiceClient
end

local function GetCurrentViewportSize(): Vector2
	local camera = Workspace.CurrentCamera
	if camera ~= nil then
		local viewportSize = camera.ViewportSize
		return Vector2.new(math.max(1, viewportSize.X), math.max(1, viewportSize.Y))
	end
	return FALLBACK_VIEWPORT
end

local function GetViewportState(usePlatformState: boolean): ViewportState
	local camera = Workspace.CurrentCamera
	local guiInsetTopLeft, guiInsetBottomRight = GuiService:GetGuiInset()
	local platformState = nil :: PlatformState?
	if usePlatformState then
		local PlatformServiceClient = getPlatformServiceClient()
		local ok, GotState = pcall(function()
			return PlatformServiceClient:GetState()
		end)
		if ok and typeof(GotState) == "table" then
			platformState = GotState :: PlatformState
		end
	end

	local uiScaleSnapshot = nil
	if usePlatformState then
		local PlatformServiceClient = getPlatformServiceClient()
		local okUIScale, uiScale = pcall(function()
			return PlatformServiceClient:GetUIScale()
		end)
		if okUIScale and uiScale ~= nil and typeof((uiScale :: any).GetSnapshot) == "function" then
			local okSnapshot, GotSnapshot = pcall(function()
				return (uiScale :: any):GetSnapshot()
			end)
			if okSnapshot and typeof(GotSnapshot) == "table" then
				uiScaleSnapshot = GotSnapshot
			end
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
		else GetCurrentViewportSize()

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
		return GetViewportState(usePlatformState)
	end)

	React.useEffect(function()
		local viewportConnection = nil

		local function refresh()
			setViewportState(GetViewportState(usePlatformState))
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

		local PlatformServiceClient = if usePlatformState then getPlatformServiceClient() else nil
		local stateSignal = if PlatformServiceClient ~= nil then PlatformServiceClient:GetStateChangedSignal() else nil
		local uiScaleSignal = if PlatformServiceClient ~= nil then PlatformServiceClient:GetUIScaleChangedSignal() else nil
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
