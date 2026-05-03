--!strict
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DropsInfo = require(script:FindFirstAncestor("game").Client.UI.core.components.DropsInfo)
local PlayerServiceUtils = require(script:FindFirstAncestor("game").Shared.Services.PlayerServiceUtils)
local React = require(ReplicatedStorage.Packages.React)
local infoPlayerSlice = require(script:FindFirstAncestor("game").Client.UI.features.player.state.infoPlayerSlice)
local infoPlayerThunks = require(script:FindFirstAncestor("game").Client.UI.features.player.state.infoPlayerThunks)
local useInfoPopUp = require(script:FindFirstAncestor("game").Client.UI.features.player.hooks.useInfoPopUp)
local useStore = require(script:FindFirstAncestor("game").Client.UI.core.hooks.useStore)

type InfoPlayerState = infoPlayerSlice.InfoPlayerState
type InfoPlayerPopup = infoPlayerSlice.InfoPlayerPopup

type InfoPlayerScreenProps = {
	layoutOrder: number?,
	zIndex: number?,
	visible: boolean?,
}

type PopupEntryProps = {
	localPlayer: Player,
	popup: InfoPlayerPopup,
	index: number,
	zIndex: number,
}

local e: typeof(React.createElement) = React.createElement

local function resolveCharacterRootPart(localPlayer: Player): BasePart?
	local character = localPlayer.Character
	if character == nil then
		return nil
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	if humanoidRootPart ~= nil and humanoidRootPart:IsA("BasePart") then
		return humanoidRootPart
	end

	if character.PrimaryPart ~= nil then
		return character.PrimaryPart
	end

	return character:FindFirstChildWhichIsA("BasePart")
end

local function resolveThemeByPopupKind(kind: infoPlayerSlice.InfoPlayerPopupKind): { [string]: any }
	if kind == "damage_taken" then
		return {
			backgroundColor = Color3.fromRGB(36, 13, 17),
			strokeColor = Color3.fromRGB(255, 91, 108),
			accentColor = Color3.fromRGB(255, 123, 138),
			titleColor = Color3.fromRGB(255, 232, 236),
			subtitleColor = Color3.fromRGB(255, 183, 194),
			descriptionColor = Color3.fromRGB(243, 161, 175),
			amountColor = Color3.fromRGB(255, 246, 247),
		}
	end
	if kind == "damage_dealt" then
		return {
			backgroundColor = Color3.fromRGB(30, 19, 8),
			strokeColor = Color3.fromRGB(255, 172, 72),
			accentColor = Color3.fromRGB(255, 201, 102),
			titleColor = Color3.fromRGB(255, 243, 220),
			subtitleColor = Color3.fromRGB(248, 215, 159),
			descriptionColor = Color3.fromRGB(236, 198, 133),
			amountColor = Color3.fromRGB(255, 250, 240),
		}
	end

	return {
		backgroundColor = Color3.fromRGB(11, 28, 23),
		strokeColor = Color3.fromRGB(93, 224, 186),
		accentColor = Color3.fromRGB(129, 240, 207),
		titleColor = Color3.fromRGB(237, 255, 248),
		subtitleColor = Color3.fromRGB(182, 235, 215),
		descriptionColor = Color3.fromRGB(148, 212, 187),
		amountColor = Color3.fromRGB(244, 255, 250),
	}
end

local function PopupEntry(props: PopupEntryProps): React.ReactNode
	local rootPart = resolveCharacterRootPart(props.localPlayer)

	local popup = props.popup
	local stackOffset = (props.index - 1) * 1.55
	local popupZIndex = props.zIndex + props.index
	local textValue = ""
	local textSize = 28
	if popup.kind == "pickup" then
		textValue = string.format("%s x%d", popup.title, popup.amount)
		textSize = 22
	else
		textValue = tostring(math.max(0, math.floor(popup.amount + 0.5)))
		textSize = 36
	end

	local popUpAnimation = useInfoPopUp({
		enabled = true,
		eventToken = popup.eventToken,
		riseDuration = 0.34,
		holdDuration = 2.5,
		shrinkDuration = 0.3,
		fromYOffsetStuds = 0,
		toYOffsetStuds = 2.8,
		minScale = 0.18,
	})

	local theme = resolveThemeByPopupKind(popup.kind)
	theme.titleTransparency = popUpAnimation.transparency
	local renderedTextSize = math.max(6, math.floor(textSize * popUpAnimation.scale + 0.5))

	local anchorPart, setAnchorPart = React.useState(nil :: BasePart?)
	React.useEffect(function()
		if rootPart == nil then
			setAnchorPart(nil)
			return nil
		end

		local createdAnchor = Instance.new("Part")
		createdAnchor.Name = ("InfoPlayerPopupAnchor_%s"):format(popup.id)
		createdAnchor.Anchored = true
		createdAnchor.CanCollide = false
		createdAnchor.CanTouch = false
		createdAnchor.CanQuery = false
		createdAnchor.CastShadow = false
		createdAnchor.Transparency = 1
		createdAnchor.Size = Vector3.new(0.1, 0.1, 0.1)
		createdAnchor.CFrame = CFrame.new(rootPart.Position)
		createdAnchor.Parent = PlayerServiceUtils.getOrCreateWorkspaceGameFolder()
		setAnchorPart(createdAnchor)

		return function()
			if createdAnchor.Parent ~= nil then
				createdAnchor:Destroy()
			end
			setAnchorPart(function(currentAnchorPart: BasePart?): BasePart?
				if currentAnchorPart == createdAnchor then
					return nil
				end
				return currentAnchorPart
			end)
		end
	end, { rootPart, popup.id })

	local adornee = anchorPart
	if adornee == nil then
		return nil
	end

	return e(DropsInfo, {
		adornee = adornee,
		eventToken = popup.eventToken,
		visible = true,
		enabled = true,
		alwaysOnTop = true,
		zIndex = popupZIndex,
		showIcon = false,
		showAmount = false,
		showRarityPill = false,
		gradientEnabled = false,
		textOnly = true,
		animationEnabled = false,
		title = textValue,
		subtitle = "",
		description = "",
		studsOffset = Vector3.new(0, 3.1 + stackOffset + popUpAnimation.offsetYStuds, 0),
		maxDistance = 150,
		lifetime = popUpAnimation.totalDuration,
		fadeInTime = 0,
		fadeOutTime = 0,
		titleTextSize = renderedTextSize,
		theme = theme,
		onExpire = function()
			infoPlayerSlice.removePopup(popup.id)
		end,
	})
end

local function createPopupElement(
	localPlayer: Player,
	popup: InfoPlayerPopup,
	index: number,
	zIndex: number
): React.ReactNode
	return e(PopupEntry, {
		localPlayer = localPlayer,
		popup = popup,
		index = index,
		zIndex = zIndex,
	})
end

return function(props: InfoPlayerScreenProps?): React.ReactNode
	local resolvedProps: InfoPlayerScreenProps = if props ~= nil then props else {}
	local localPlayer = Players.LocalPlayer
	local infoPlayerState = (useStore(infoPlayerSlice.infoPlayerStateAtom) :: InfoPlayerState?)
		or infoPlayerSlice.infoPlayerStateAtom()

	React.useEffect(function()
		local stop = infoPlayerThunks.start()

		return function()
			stop()
		end
	end, {})

	if resolvedProps.visible == false then
		return nil
	end
	if infoPlayerState.enabled ~= true then
		return nil
	end
	if #infoPlayerState.popups <= 0 then
		return nil
	end

	local zIndex = resolvedProps.zIndex or 180
	local children: { [string]: React.ReactNode } = {}
	for index, popup in infoPlayerState.popups do
		children[("Popup_%s"):format(popup.id)] = createPopupElement(localPlayer, popup, index, zIndex)
	end

	return e(React.Fragment, nil, children)
end
