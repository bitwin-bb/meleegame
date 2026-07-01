local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")


local Players = game:GetService("Players")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local ParallaxComponent = require("ParallaxView")
local ParallaxSlice = require("ParallaxSlice")
local useStore = require("useCoreStore")

local e: typeof(React.createElement) = React.createElement

local function GetAspectRatio(canvasSize: Vector2): number
	if canvasSize.X <= 0 or canvasSize.Y <= 0 then
		return 1
	end
	return math.clamp(canvasSize.X / canvasSize.Y, 0.01, 100)
end

local function GetPortalTarget(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

return function(): React.ReactNode
	local state = (useStore(ParallaxSlice.surfaceStateAtom) :: ParallaxSlice.ParallaxSurfaceState?)
		or ParallaxSlice.GetSurfaceState()
	local portalTarget = GetPortalTarget()

	if state.adornee == nil or portalTarget == nil then
		return nil
	end

	return ReactRoblox.createPortal(
		e(React.Fragment, nil, {
			Parallax = e("SurfaceGui", {
				Adornee = state.adornee,
				AlwaysOnTop = false,
				Brightness = state.brightness,
				CanvasSize = state.canvasSize,
				Enabled = state.visible,
				Face = state.face,
				LightInfluence = 0,
				ResetOnSpawn = false,
				SizingMode = Enum.SurfaceGuiSizingMode.FixedSize,
				ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
			}, {
				e("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromScale(0.5, 0.5),
					Size = UDim2.fromScale(1, 1),
					BackgroundTransparency = 1,
					BorderSizePixel = 0,
					ClipsDescendants = true,
				}, {
					e("UIAspectRatioConstraint", {
						AspectRatio = GetAspectRatio(state.canvasSize),
						DominantAxis = Enum.DominantAxis.Width,
					}),
					e(ParallaxComponent, {
						state = state,
					}),
				}),
			}),
		}),
		portalTarget
	)
end
