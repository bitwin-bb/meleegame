--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local FloatingCard = require(script.Parent.FloatingCard)
local React = require(ReplicatedStorage.Packages.React)
local ReactRoblox = require(ReplicatedStorage.Packages.ReactRoblox)

export type BillboardCardProps = {
	adornee: Instance?,
	enabled: boolean?,
	visible: boolean?,
	active: boolean?,
	alwaysOnTop: boolean?,
	maxDistance: number?,
	lightInfluence: number?,
	studsOffset: Vector3?,
	studsOffsetWorldSpace: Vector3?,
	extentsOffset: Vector3?,
	size: UDim2?,
	zIndex: number?,
	zIndexBehavior: Enum.ZIndexBehavior?,
	resetOnSpawn: boolean?,
	clipsDescendants: boolean?,
	playerToHideFrom: Player?,
	portalTarget: Instance?,
	disablePortal: boolean?,
	cardSize: UDim2?,
	cardPosition: UDim2?,
	cardAnchorPoint: Vector2?,
	title: string?,
	subtitle: string?,
	body: string?,
	icon: string?,
	nativeBillboard: { [any]: any }?,
	nativeCard: { [any]: any }?,
	cardVisible: boolean?,
	children: { React.ReactNode }?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_SIZE = UDim2.fromOffset(260, 112)
local DEFAULT_CARD_SIZE = UDim2.fromOffset(220, 72)
local DEFAULT_STUDS_OFFSET = Vector3.new(0, 3, 0)

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = if typeof(valueRaw) == "number" and valueRaw == valueRaw then valueRaw else fallback
	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

local function sanitizeVector3(valueRaw: any, fallback: Vector3): Vector3
	return if typeof(valueRaw) == "Vector3" then valueRaw else fallback
end

local function applyNativeProps(target: { [any]: any }, nativeProps: { [any]: any }?)
	if nativeProps == nil then
		return
	end

	for key, value in nativeProps do
		target[key] = value
	end
end

local function resolvePortalTarget(props: BillboardCardProps): Instance?
	if props.disablePortal == true then
		return nil
	end
	if props.portalTarget ~= nil then
		return props.portalTarget
	end

	local localPlayer = Players.LocalPlayer
	if localPlayer == nil then
		return nil
	end

	local playerGui = localPlayer:FindFirstChildOfClass("PlayerGui")
	return playerGui
end

return function(props: BillboardCardProps): React.ReactNode
	if props.visible == false then
		return nil
	end

	local zIndex = props.zIndex or 30
	local billboardProps: { [any]: any } = {
		Adornee = props.adornee,
		Enabled = props.enabled ~= false,
		Active = props.active == true,
		AlwaysOnTop = props.alwaysOnTop ~= false,
		MaxDistance = sanitizeNumber(props.maxDistance, 130, 0, 20000),
		LightInfluence = sanitizeNumber(props.lightInfluence, 0, 0, 1),
		StudsOffset = sanitizeVector3(props.studsOffset, DEFAULT_STUDS_OFFSET),
		StudsOffsetWorldSpace = sanitizeVector3(props.studsOffsetWorldSpace, Vector3.zero),
		ExtentsOffset = sanitizeVector3(props.extentsOffset, Vector3.zero),
		Size = props.size or DEFAULT_SIZE,
		ResetOnSpawn = props.resetOnSpawn == true,
		ClipsDescendants = props.clipsDescendants == true,
		PlayerToHideFrom = props.playerToHideFrom,
		ZIndexBehavior = props.zIndexBehavior or Enum.ZIndexBehavior.Sibling,
	}
	applyNativeProps(billboardProps, props.nativeBillboard)

	local billboardChildren: { React.ReactNode } = {}
	if props.cardVisible == false then
		if props.children ~= nil then
			for key, child in props.children do
				billboardChildren[key] = child
			end
		end
	else
		billboardChildren.Card = e(FloatingCard, {
			size = props.cardSize or DEFAULT_CARD_SIZE,
			position = props.cardPosition or UDim2.fromScale(0.5, 1),
			anchorPoint = props.cardAnchorPoint or Vector2.new(0.5, 1),
			title = props.title,
			subtitle = props.subtitle,
			body = props.body,
			icon = props.icon,
			zIndex = zIndex,
			native = props.nativeCard,
			children = props.children,
		})
	end

	local element = e("BillboardGui", billboardProps, billboardChildren)

	local portalTarget = resolvePortalTarget(props)
	if portalTarget ~= nil then
		return ReactRoblox.createPortal(element, portalTarget)
	end

	return element
end
