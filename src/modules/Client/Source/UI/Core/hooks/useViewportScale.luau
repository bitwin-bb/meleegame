local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UiScaleUtils = require("UIScaleUtils")
local useViewport = require("useViewport")

export type ResponsiveMetrics = UiScaleUtils.ResponsiveMetrics

type ProviderProps = {
	children: { React.ReactNode }?,
	usePlatformState: boolean?,
	viewport: Vector2?,
}

local ResponsiveContext = React.createContext(nil :: ResponsiveMetrics?)

local function useViewportScale(viewportOverride: Vector2?, usePlatformStateRaw: boolean?): ResponsiveMetrics
	local viewportState = useViewport({
		usePlatformState = usePlatformStateRaw ~= false,
	})

	return React.useMemo(function(): ResponsiveMetrics
		return UiScaleUtils.GetMetrics(
			viewportOverride or viewportState.viewport,
			viewportState.safeInsetTopLeft,
			viewportState.safeInsetBottomRight
		)
	end, {
		viewportOverride,
		viewportState.viewport,
		viewportState.safeInsetTopLeft,
		viewportState.safeInsetBottomRight,
	})
end

local function useResponsiveMetrics(): ResponsiveMetrics
	local contextMetrics = React.useContext(ResponsiveContext)
	if contextMetrics ~= nil then
		return contextMetrics
	end
	return useViewportScale(nil, nil)
end

local function Provider(props: ProviderProps): React.ReactNode
	local metrics = useViewportScale(props.viewport, props.usePlatformState)

	return React.createElement(ResponsiveContext.Provider, {
		value = metrics,
	}, props.children)
end

return {
	Context = ResponsiveContext,
	Provider = Provider,
	useResponsiveMetrics = useResponsiveMetrics,
	useViewportScale = useViewportScale,
}
