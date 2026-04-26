--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PortalTargets = require(script:FindFirstAncestor("game").Client.UI.core.utils.PortalTargets)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)
local mouseSlice = require(script:FindFirstAncestor("game").Client.UI.features.mouse.state.mouseSlice)
local mouseThunks = require(script:FindFirstAncestor("game").Client.UI.features.mouse.state.mouseThunks)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type MouseState = mouseSlice.MouseState

type MouseScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
	cursorSize: Vector2?,
	hotspotOffset: Vector2?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_CURSOR_SIZE = Vector2.new(28, 28)
local DEFAULT_HOTSPOT_OFFSET = Vector2.new(0, 0)

return function(props: MouseScreenProps): React.ReactNode
	local currentMouseState = (useStore(mouseSlice.mouseStateAtom) :: MouseState?) or mouseSlice.mouseStateAtom()

	React.useEffect(function()
		local stop = mouseThunks.start()

		return function()
			stop()
		end
	end, {})

	if props.visible == false or currentMouseState.visible ~= true then
		return nil
	end

	local zIndex = props.zIndex or 200
	local cursorSize = props.cursorSize or DEFAULT_CURSOR_SIZE
	local hotspotOffset = props.hotspotOffset or DEFAULT_HOTSPOT_OFFSET
	local cursorPosition = currentMouseState.position - hotspotOffset

	local rootElement = e("Frame", {
		Name = "MouseScreenRoot",
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 0),
		LayoutOrder = props.layoutOrder or 1000,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Active = false,
		Selectable = false,
		ZIndex = zIndex,
	}, {
		MouseCursorImage = e("ImageLabel", {
			Name = "MouseCursorImage",
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Active = false,
			Selectable = false,
			Image = currentMouseState.imageId,
			Position = UDim2.fromOffset(math.floor(cursorPosition.X), math.floor(cursorPosition.Y)),
			Size = UDim2.fromOffset(math.floor(cursorSize.X), math.floor(cursorSize.Y)),
			ZIndex = zIndex + 1,
		}),
	})

	local portalTarget = PortalTargets.resolveUiScreenGui()
	if portalTarget ~= nil then
		return ReactRoblox.createPortal(rootElement, portalTarget)
	end

	return rootElement
end
