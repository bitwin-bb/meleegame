local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ImageIds = require("ImageIds")
local React: any = require(ReplicatedStorage.Packages.React)
local Table: any = require("Table")
local UiSound = require("UISound")
local infoThunks = require("InfoThunks")
local useCooldownEffect = require("useCooldownEffect")
local useHover = require("useHover")
local useTimer = require("useTimer")

export type BuffProps = {
	record: any,
	layoutOrder: number?,
	size: UDim2?,
	iconSize: number?,
	slotImage: string?,
	icon: string?,
	zIndex: number?,
	visible: boolean?,
	DebugInnerBounds: boolean?,
	debugInnerBounds: boolean?,
	native: { [any]: any }?,
}

type BuffSlotProps = {
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	SlotImage: string,
	IconImage: string?,
	ZIndex: number?,
	DebugInnerBounds: boolean?,
	Cooldown: React.ReactNode?,
}

local e: typeof(React.createElement) = React.createElement

local DEFAULT_SLOT_SIZE = 50
local TIMER_HEIGHT = 16
local SLOT_IMAGE_SIZE = Vector2.new(168, 180)
local INNER_POS = Vector2.new(18, 8)
local INNER_SIZE = Vector2.new(132, 132)

local ICON_ALIASES = {
	healingpotionsickness = "healingPotionSickness",
	rollcooldown = "rollCooldown",
	bleeding = "bleeding",
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end

	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function normalizeKey(valueRaw: any): string
	local value = string.lower(trim(valueRaw))
	return string.gsub(value, "[^%w]", "")
end

local function GetImageId(valueRaw: any): string
	if typeof(valueRaw) == "string" and valueRaw ~= "" then
		return valueRaw
	end

	return ""
end

local function GetIconFromGroup(iconGroupRaw: any, iconKeyRaw: any): string
	if typeof(iconGroupRaw) ~= "table" then
		return ""
	end

	return GetImageId((iconGroupRaw :: { [string]: any })[iconKeyRaw])
end

local function GetEcordIcon(recordRaw: any, propIconRaw: any): string
	local propIcon = GetImageId(propIconRaw)
	if propIcon ~= "" then
		return propIcon
	end

	local record: any = if typeof(recordRaw) == "table" then recordRaw else {}
	local recordIcon = GetImageId(record.icon or record.iconId)
	if recordIcon ~= "" then
		return recordIcon
	end

	local key = normalizeKey(record.name)
	if key == "" then
		key = normalizeKey(record.id)
	end
	local alias = ICON_ALIASES[key] or key

	local imageFromGroup = ""
	if record.kind == "Debuff" then
		imageFromGroup = GetIconFromGroup((ImageIds :: any).debuffs, alias)
	elseif record.kind == "Buff" then
		imageFromGroup = GetIconFromGroup((ImageIds :: any).buffs, alias)
	else
		imageFromGroup = GetIconFromGroup((ImageIds :: any).debuffs, alias)
		if imageFromGroup == "" then
			imageFromGroup = GetIconFromGroup((ImageIds :: any).buffs, alias)
		end
	end
	if imageFromGroup ~= "" then
		return imageFromGroup
	end

	return GetImageId((ImageIds :: any)[alias])
end

local function GetSlotImage(slotImageRaw: any): string
	local slotImage = GetImageId(slotImageRaw)
	if slotImage ~= "" then
		return slotImage
	end

	slotImage = GetImageId((ImageIds :: any).buffSlot)
	if slotImage ~= "" then
		return slotImage
	end

	return GetImageId((ImageIds :: any).skillSlot or (ImageIds :: any).inventorySlot)
end

local function GetStacks(recordRaw: any): string?
	if typeof(recordRaw) ~= "table" then
		return nil
	end

	local stacks = (recordRaw :: { [string]: any }).stacks
	if typeof(stacks) ~= "number" or stacks <= 1 then
		return nil
	end

	return `x{math.floor(stacks)}`
end

local function composeHoverText(recordRaw: any): string
	if typeof(recordRaw) ~= "table" then
		return ""
	end

	local record = recordRaw :: { [string]: any }
	local parts = {}
	local name = trim(record.name)
	if name ~= "" then
		parts[#parts + 1] = name
	end

	local description = trim(record.description)
	if description ~= "" then
		parts[#parts + 1] = description
	end

	local affects = trim(record.affects)
	if affects ~= "" then
		parts[#parts + 1] = affects
	end

	return table.concat(parts, "\n")
end

local function BuffSlot(props: BuffSlotProps): React.ReactNode
	local zIndex = props.ZIndex or 1
	local iconClipProps = {
		BackgroundTransparency = if props.DebugInnerBounds == true then 0.5 else 1,
		BackgroundColor3 = Color3.fromRGB(255, 0, 0),
		BorderSizePixel = 0,
		ClipsDescendants = true,
		Position = UDim2.fromScale(INNER_POS.X / SLOT_IMAGE_SIZE.X, INNER_POS.Y / SLOT_IMAGE_SIZE.Y),
		Size = UDim2.fromScale(INNER_SIZE.X / SLOT_IMAGE_SIZE.X, INNER_SIZE.Y / SLOT_IMAGE_SIZE.Y),
		ZIndex = zIndex + 1,
	}
	local iconChildren: { [any]: React.ReactNode } = {}

	if GetImageId(props.IconImage) ~= "" then
		iconChildren.BuffIcon = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0.5, 0.5),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.IconImage,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = zIndex + 2,
		})
	end

	if props.Cooldown ~= nil then
		iconChildren.Cooldown = props.Cooldown
	end

	return e("Frame", {
		Size = props.Size
			or UDim2.fromOffset(DEFAULT_SLOT_SIZE, math.ceil(DEFAULT_SLOT_SIZE * SLOT_IMAGE_SIZE.Y / SLOT_IMAGE_SIZE.X)),
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = zIndex,
	}, {
		AspectRatio = e("UIAspectRatioConstraint", {
			AspectRatio = SLOT_IMAGE_SIZE.X / SLOT_IMAGE_SIZE.Y,
		}),
		SlotImage = e("ImageLabel", {
			Size = UDim2.fromScale(1, 1),
			Position = UDim2.fromScale(0, 0),
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Image = props.SlotImage,
			ScaleType = Enum.ScaleType.Stretch,
			ZIndex = zIndex,
		}),
		IconClip = if props.IconImage ~= nil and props.IconImage ~= "" or props.Cooldown ~= nil
			then e("Frame", iconClipProps, iconChildren)
			else nil,
	})
end

return function(props: BuffProps): React.ReactNode
	local record = props.record
	local timer = useTimer(record)
	local zIndex = props.zIndex or 20
	local slotSize = props.iconSize or DEFAULT_SLOT_SIZE
	local slotHeight = math.ceil(slotSize * (SLOT_IMAGE_SIZE.Y / SLOT_IMAGE_SIZE.X))
	local frameProps = if props.native ~= nil then Table.copy(props.native) else {}
	local children: { React.ReactNode } = {}
	local stackText = GetStacks(record)
	local recordIcon = GetEcordIcon(record, props.icon)
	local debugInnerBounds = props.DebugInnerBounds == true or props.debugInnerBounds == true
	local hoverId = `buff_{normalizeKey(if typeof(record) == "table" then (record :: { [string]: any }).id else "")}`
	local hoverText = composeHoverText(record)
	local hover = useHover({
		onHoverStart = function()
			if hoverText == "" then
				return
			end

			infoThunks.ShowHover({
				id = hoverId,
				text = hoverText,
			})
			UiSound.playHover()
		end,
		onHoverEnd = function()
			infoThunks.HideHover(hoverId)
		end,
	})

	React.useEffect(function()
		return function()
			infoThunks.HideHover(hoverId)
		end
	end, { hoverId })

	children[#children + 1] = e(BuffSlot, {
		Size = UDim2.fromOffset(slotSize, slotHeight),
		Position = UDim2.fromScale(0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		SlotImage = GetSlotImage(props.slotImage),
		IconImage = recordIcon,
		ZIndex = zIndex + 1,
		DebugInnerBounds = debugInnerBounds,
		Cooldown = useCooldownEffect({
			record = record,
			zIndex = zIndex + 4,
		}),
	})

	if stackText ~= nil then
		children[#children + 1] = e("TextLabel", {
			Size = UDim2.fromOffset(26, 14),
			Position = UDim2.fromOffset(slotSize - 20, 2),
			BackgroundTransparency = 1,
			Font = Enum.Font.PatrickHand,
			Text = stackText,
			TextColor3 = Color3.fromRGB(255, 255, 255),
			TextStrokeTransparency = 0.2,
			TextSize = 11,
			TextXAlignment = Enum.TextXAlignment.Right,
			TextYAlignment = Enum.TextYAlignment.Center,
			ZIndex = zIndex + 5,
		})
	end

	children[#children + 1] = e("TextLabel", {
		Size = UDim2.new(1, 0, 0, TIMER_HEIGHT),
		Position = UDim2.new(0.5, 0, 0, slotHeight + 4),
		AnchorPoint = Vector2.new(0.5, 0),
		BackgroundTransparency = 1,
		Font = Enum.Font.PatrickHand,
		Text = timer.text,
		TextColor3 = Color3.fromRGB(255, 255, 255),
		TextStrokeTransparency = 0.35,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextYAlignment = Enum.TextYAlignment.Center,
		ZIndex = zIndex + 5,
	})

	frameProps.Size = frameProps.Size or props.size or UDim2.fromOffset(slotSize, slotHeight + TIMER_HEIGHT + 4)
	frameProps.BackgroundTransparency = frameProps.BackgroundTransparency or 1
	frameProps.BorderSizePixel = frameProps.BorderSizePixel or 0
	frameProps.Active = if frameProps.Active ~= nil then frameProps.Active else hoverText ~= ""
	frameProps.LayoutOrder = frameProps.LayoutOrder or props.layoutOrder or 1
	frameProps.Visible = if frameProps.Visible ~= nil then frameProps.Visible else props.visible ~= false
	frameProps.ZIndex = frameProps.ZIndex or zIndex
	frameProps[React.Event.MouseEnter] = frameProps[React.Event.MouseEnter]
		or hover.eventHandlers[React.Event.MouseEnter]
	frameProps[React.Event.MouseLeave] = frameProps[React.Event.MouseLeave]
		or hover.eventHandlers[React.Event.MouseLeave]

	return e("Frame", frameProps, children)
end
