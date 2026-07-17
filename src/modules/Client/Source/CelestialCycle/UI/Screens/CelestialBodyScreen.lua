local require = require(script.Parent.loader).load(script)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local React: any = require(ReplicatedStorage.Packages.React)
local ReactRoblox: any = require(ReplicatedStorage.Packages.ReactRoblox)
local Table: any = require("Table")

local CelestialBody = require("CelestialBody")
local Hooks = require("useCycle")

local e: typeof(React.createElement) = React.createElement

local CelestialBodyScreen = {}

local function getPortalTarget(): PlayerGui?
	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end
	return localPlayer:FindFirstChildOfClass("PlayerGui")
end

local function getAspectRatio(canvasSize: Vector2): number
	if canvasSize.X <= 0 or canvasSize.Y <= 0 then
		return 1
	end
	return math.clamp(canvasSize.X / canvasSize.Y, 0.01, 100)
end

function CelestialBodyScreen.Render(): React.ReactNode
	local state = Hooks.UseCycle()
	local portalTarget = getPortalTarget()
	if state.adornee == nil or portalTarget == nil or state.cycle == nil then
		return nil
	end

	return ReactRoblox.createPortal(
		e("SurfaceGui", {
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
			Frame = e("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				BackgroundTransparency = 1,
				BorderSizePixel = 0,
				ClipsDescendants = true,
				Position = UDim2.fromScale(0.5, 0.5),
				Size = UDim2.fromScale(1, 1),
			}, {
				Aspect = e("UIAspectRatioConstraint", {
					AspectRatio = getAspectRatio(state.canvasSize),
					DominantAxis = Enum.DominantAxis.Width,
				}),
				Sun = e(CelestialBody, {
					body = state.cycle.sun,
				}),
				Moon = e(CelestialBody, {
					body = state.cycle.moon,
				}),
			}),
		}),
		portalTarget
	)
end

local readonlyScreen = Table.readonly(CelestialBodyScreen)

return function(): React.ReactNode
	return readonlyScreen.Render()
end
