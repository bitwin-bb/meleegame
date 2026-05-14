--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

local ParallaxComponent = require(script.Parent.Parent.components.Parallax)
local ParallaxSlice = require(script:FindFirstAncestor("parallax").ParallaxSlice)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

local e: typeof(React.createElement) = React.createElement

local function resolveAspectRatio(canvasSize: Vector2): number
	if canvasSize.X <= 0 or canvasSize.Y <= 0 then
		return 1
	end
	return math.clamp(canvasSize.X / canvasSize.Y, 0.01, 100)
end

local function resolvePlayerGui(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	if playerGui ~= nil and playerGui:IsA("PlayerGui") then
		return playerGui
	end
	return nil
end

return function(): React.ReactNode
	local state = (useStore(ParallaxSlice.surfaceStateAtom) :: ParallaxSlice.ParallaxSurfaceState?)
		or ParallaxSlice.getSurfaceState()
	local playerGui = resolvePlayerGui()

	if state.adornee == nil or playerGui == nil then
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
						AspectRatio = resolveAspectRatio(state.canvasSize),
						DominantAxis = Enum.DominantAxis.Width,
					}),
					e(ParallaxComponent, {
						state = state,
					}),
				}),
			}),
		}),
		playerGui
	)
end
