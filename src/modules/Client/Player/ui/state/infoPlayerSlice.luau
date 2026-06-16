local require = require(script.Parent.loader).load(script)

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Packages.Charm)
local Sift = require(ReplicatedStorage.Packages.Sift)

export type InfoPlayerPopupKind = "pickup" | "damage_dealt" | "damage_taken"

export type InfoPlayerPopup = {
	id: string,
	eventToken: string,
	kind: InfoPlayerPopupKind,
	title: string,
	subtitle: string,
	description: string,
	amount: number,
	amountPrefix: string,
	targetKind: string?,
	targetRuntimeId: string?,
	targetPosition: Vector3?,
	createdAt: number,
}

export type InfoPlayerState = {
	enabled: boolean,
	popups: { InfoPlayerPopup },
	sequence: number,
	updatedAt: number,
}

export type PushPopupPayload = {
	id: string?,
	kind: InfoPlayerPopupKind?,
	title: string?,
	subtitle: string?,
	description: string?,
	amount: number?,
	amountPrefix: string?,
	targetKind: string?,
	targetRuntimeId: string?,
	targetPosition: Vector3?,
	replaceExistingKind: boolean?,
}

local MAX_POPUP_COUNT = 8

local DEFAULT_STATE: InfoPlayerState = {
	enabled = true,
	popups = {},
	sequence = 0,
	updatedAt = os.clock(),
}

local infoPlayerStateAtom: Charm.Atom<InfoPlayerState> = Charm.atom(DEFAULT_STATE)

local function sanitizePopupKind(valueRaw: any): InfoPlayerPopupKind
	if valueRaw == "pickup" then
		return "pickup"
	end
	if valueRaw == "damage_dealt" then
		return "damage_dealt"
	end
	if valueRaw == "damage_taken" then
		return "damage_taken"
	end
	return "pickup"
end

local function sanitizeString(valueRaw: any, fallback: string): string
	if typeof(valueRaw) ~= "string" then
		return fallback
	end
	local value = string.match(valueRaw, "^%s*(.-)%s*$") or ""
	if value == "" then
		return fallback
	end
	return value
end

local function sanitizeAmount(valueRaw: any): number
	if typeof(valueRaw) ~= "number" or valueRaw ~= valueRaw then
		return 0
	end
	return math.max(0, math.floor(valueRaw + 0.5))
end

local function sanitizeOptionalString(valueRaw: any): string?
	if typeof(valueRaw) ~= "string" then
		return nil
	end
	local value = string.match(valueRaw, "^%s*(.-)%s*$") or ""
	if value == "" then
		return nil
	end
	return value
end

local function sanitizeOptionalVector3(valueRaw: any): Vector3?
	if typeof(valueRaw) ~= "Vector3" then
		return nil
	end
	return valueRaw
end

local function clonePopups(popupsRaw: { InfoPlayerPopup }): { InfoPlayerPopup }
	return Sift.Array.map(popupsRaw, function(popup: InfoPlayerPopup): InfoPlayerPopup
		return {
			id = popup.id,
			eventToken = popup.eventToken,
			kind = popup.kind,
			title = popup.title,
			subtitle = popup.subtitle,
			description = popup.description,
			amount = popup.amount,
			amountPrefix = popup.amountPrefix,
			targetKind = popup.targetKind,
			targetRuntimeId = popup.targetRuntimeId,
			targetPosition = popup.targetPosition,
			createdAt = popup.createdAt,
		}
	end)
end

local function limitPopups(popups: { InfoPlayerPopup }): { InfoPlayerPopup }
	if #popups <= MAX_POPUP_COUNT then
		return popups
	end
	return Sift.Array.slice(popups, 1, MAX_POPUP_COUNT)
end

local function formatWordsFromToken(tokenRaw: string): string
	local compact = string.gsub(tokenRaw, "[%s_%-]+", " ")
	compact = string.gsub(compact, "(%l)(%u)", "%1 %2")
	compact = string.gsub(compact, "^%s*(.-)%s*$", "%1")
	if compact == "" then
		return "Item"
	end
	local formatted = (string.gsub :: any)(
			compact,
			"(%a)([%w_']*)",
			function(first: string, tail: string): string
				return string.upper(first) .. string.lower(tail)
			end
		) :: string
	return formatted
end

local function getInfoPlayerState(): InfoPlayerState
	return infoPlayerStateAtom()
end

local function setInfoPlayerState(stateRaw: any): InfoPlayerState
	local current = infoPlayerStateAtom()
	local source = if typeof(stateRaw) == "table" then stateRaw :: { [string]: any } else {} :: any
	local enabled = if typeof(source.enabled) == "boolean" then source.enabled else current.enabled
	local sequenceRaw = if typeof(source.sequence) == "number" and source.sequence == source.sequence
		then source.sequence
		else current.sequence
	local nextSequence = math.max(0, math.floor(sequenceRaw))

	local nextPopups = clonePopups(current.popups)
	if typeof(source.popups) == "table" then
		nextPopups = {}
		for _, popupRaw in source.popups do
			if typeof(popupRaw) ~= "table" then
				continue
			end
			local popupSource = popupRaw :: { [string]: any }
			local id = sanitizeString(popupSource.id, ("event_%d"):format(nextSequence + #nextPopups + 1))
			local popupAmount = sanitizeAmount(popupSource.amount)
			nextPopups = Sift.Array.append(nextPopups, {
				id = id,
				eventToken = sanitizeString(popupSource.eventToken, id),
				kind = sanitizePopupKind(popupSource.kind),
				title = sanitizeString(popupSource.title, "Update"),
				subtitle = sanitizeString(popupSource.subtitle, ""),
				description = sanitizeString(popupSource.description, ""),
				amount = popupAmount,
				amountPrefix = sanitizeString(popupSource.amountPrefix, "+"),
				targetKind = sanitizeOptionalString(popupSource.targetKind),
				targetRuntimeId = sanitizeOptionalString(popupSource.targetRuntimeId),
				targetPosition = sanitizeOptionalVector3(popupSource.targetPosition),
				createdAt = if typeof(popupSource.createdAt) == "number"
						and popupSource.createdAt == popupSource.createdAt
					then popupSource.createdAt
					else os.clock(),
			})
		end
	end

	nextPopups = limitPopups(nextPopups)

	local nextState: InfoPlayerState = {
		enabled = enabled,
		popups = nextPopups,
		sequence = nextSequence,
		updatedAt = os.clock(),
	}
	infoPlayerStateAtom(nextState)
	return nextState
end

local function pushPopup(payloadRaw: any): InfoPlayerPopup?
	local payload = if typeof(payloadRaw) == "table" then payloadRaw :: { [string]: any } else {} :: any
	local current = infoPlayerStateAtom()
	if current.enabled ~= true then
		return nil
	end

	local amount = sanitizeAmount(payload.amount)
	if amount <= 0 then
		return nil
	end

	local nextSequence = current.sequence + 1
	local eventId = sanitizeString(payload.id, ("event_%d"):format(nextSequence))
	local popupKind = sanitizePopupKind(payload.kind)
	local popup: InfoPlayerPopup = {
		id = eventId,
		eventToken = ("%s::%d"):format(eventId, nextSequence),
		kind = popupKind,
		title = sanitizeString(payload.title, "Update"),
		subtitle = sanitizeString(payload.subtitle, ""),
		description = sanitizeString(payload.description, ""),
		amount = amount,
		amountPrefix = sanitizeString(payload.amountPrefix, "+"),
		targetKind = sanitizeOptionalString(payload.targetKind),
		targetRuntimeId = sanitizeOptionalString(payload.targetRuntimeId),
		targetPosition = sanitizeOptionalVector3(payload.targetPosition),
		createdAt = os.clock(),
	} :: any

	local basePopups = clonePopups(current.popups)
	if payload.replaceExistingKind == true then
		basePopups = Sift.Array.filter(basePopups, function(existingPopup: InfoPlayerPopup): boolean
			return existingPopup.kind ~= popupKind
		end)
	end

	local nextPopups = limitPopups(Sift.Array.prepend(basePopups, popup))

	infoPlayerStateAtom({
		enabled = true,
		popups = nextPopups,
		sequence = nextSequence,
		updatedAt = os.clock(),
	})
	return popup
end

local function pushPickup(itemIdRaw: any, amountRaw: any): InfoPlayerPopup?
	local itemId = sanitizeString(itemIdRaw, "")
	local amount = sanitizeAmount(amountRaw)
	if itemId == "" or amount <= 0 then
		return nil
	end

	local displayName = formatWordsFromToken(itemId)
	return pushPopup({
		kind = "pickup",
		title = displayName,
		subtitle = "Item Picked Up",
		description = itemId,
		amount = amount,
		amountPrefix = "+",
	})
end

local function pushDamageDealt(amountRaw: any, targetRaw: any?): InfoPlayerPopup?
	local amount = sanitizeAmount(amountRaw)
	if amount <= 0 then
		return nil
	end
	local target = if typeof(targetRaw) == "table" then targetRaw :: { [string]: any } else {} :: any

	return pushPopup({
		kind = "damage_dealt",
		title = "Damage Dealt",
		subtitle = "Target Hit",
		description = "You dealt damage",
		amount = amount,
		amountPrefix = "-",
		targetKind = target.targetKind,
		targetRuntimeId = target.targetRuntimeId,
		targetPosition = target.targetPosition,
		replaceExistingKind = true,
	})
end

local function pushDamageTaken(amountRaw: any): InfoPlayerPopup?
	local amount = sanitizeAmount(amountRaw)
	if amount <= 0 then
		return nil
	end

	return pushPopup({
		kind = "damage_taken",
		title = "Damage Taken",
		subtitle = "You were hit",
		description = "Incoming damage",
		amount = amount,
		amountPrefix = "-",
	})
end

local function removePopup(popupIdRaw: any): InfoPlayerState
	local popupId = sanitizeString(popupIdRaw, "")
	if popupId == "" then
		return infoPlayerStateAtom()
	end

	local current = infoPlayerStateAtom()
	local nextPopups = Sift.Array.filter(current.popups, function(popup: InfoPlayerPopup): boolean
		return popup.id ~= popupId
	end)

	if #nextPopups == #current.popups then
		return current
	end

	local nextState: InfoPlayerState = {
		enabled = current.enabled,
		popups = nextPopups,
		sequence = current.sequence,
		updatedAt = os.clock(),
	}
	infoPlayerStateAtom(nextState)
	return nextState
end

local function clearPopups(): InfoPlayerState
	local current = infoPlayerStateAtom()
	if #current.popups <= 0 then
		return current
	end

	local nextState: InfoPlayerState = {
		enabled = current.enabled,
		popups = {},
		sequence = current.sequence,
		updatedAt = os.clock(),
	}
	infoPlayerStateAtom(nextState)
	return nextState
end

local function setEnabled(enabledRaw: any): InfoPlayerState
	local enabled = enabledRaw == true
	local current = infoPlayerStateAtom()
	if current.enabled == enabled then
		return current
	end

	local nextState: InfoPlayerState = {
		enabled = enabled,
		popups = if enabled then current.popups else {} :: any,
		sequence = current.sequence,
		updatedAt = os.clock(),
	}
	infoPlayerStateAtom(nextState)
	return nextState
end

local function resetInfoPlayerState(): InfoPlayerState
	local nextState: InfoPlayerState = {
		enabled = true,
		popups = {},
		sequence = 0,
		updatedAt = os.clock(),
	}
	infoPlayerStateAtom(nextState)
	return nextState
end

return {
	infoPlayerStateAtom = infoPlayerStateAtom,
	getInfoPlayerState = getInfoPlayerState,
	setInfoPlayerState = setInfoPlayerState,
	pushPopup = pushPopup,
	pushPickup = pushPickup,
	pushDamageDealt = pushDamageDealt,
	pushDamageTaken = pushDamageTaken,
	removePopup = removePopup,
	clearPopups = clearPopups,
	setEnabled = setEnabled,
	resetInfoPlayerState = resetInfoPlayerState,
}
