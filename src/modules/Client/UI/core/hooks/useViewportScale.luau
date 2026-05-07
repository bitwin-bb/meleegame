--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local UiScaleUtils = require(script:FindFirstAncestor("game").Client.UI.core.utils.UiScaleUtils)
local useViewport = require(script.Parent.useViewport)

export type ResponsiveMetrics = UiScaleUtils.ResponsiveMetrics

type ProviderProps = {
	children: { React.ReactNode }?,
	viewport: Vector2?,
}

local ResponsiveContext = React.createContext(nil :: ResponsiveMetrics?)

local function useViewportScale(viewportOverride: Vector2?): ResponsiveMetrics
	local viewportState = useViewport({
		usePlatformState = true,
	})

	return React.useMemo(function(): ResponsiveMetrics
		return UiScaleUtils.resolveMetrics(
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
	return useViewportScale(nil)
end

local function Provider(props: ProviderProps): React.ReactNode
	local metrics = useViewportScale(props.viewport)

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
