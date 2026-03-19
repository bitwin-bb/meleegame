--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RichTextFormatter = require(ReplicatedStorage.Shared.Modules.UI.RichTextFormatter)

export type RoleId = "Owner" | "Admin" | "Moderator" | "Member"

export type TextLabelStyle = {
	textColor3: Color3,
	effects: { [string]: any },
}

export type PlayerRoleSnapshot = {
	userId: number,
	userName: string,
	displayName: string,
	roleId: RoleId,
	roleName: string,
	tagText: string,
	priority: number,
	canUseCommands: boolean,
}

export type RoleDefinition = {
	id: RoleId,
	roleName: string,
	tagText: string,
	priority: number,
	canUseCommands: boolean,
	chatMode: "rainbow" | "gradient" | "solid",
	chatColors: { Color3 },
	react: {
		tag: TextLabelStyle,
		name: TextLabelStyle,
		message: TextLabelStyle,
	},
}

export type RoleOverrides = {
	admins: { number },
	moderators: { number },
}

export type RoleResolveContext = {
	ownerUserId: number?,
	creatorGroupId: number?,
	roleOverrides: RoleOverrides?,
	adminMinGroupRank: number?,
	moderatorMinGroupRank: number?,
}

local Role = {}

local DEFAULT_ADMIN_MIN_GROUP_RANK = 254
local DEFAULT_MODERATOR_MIN_GROUP_RANK = 200
local DEFAULT_ROLE_OVERRIDES: RoleOverrides = {
	admins = {},
	moderators = {},
}

local OWNER_COLORS = {
	Color3.fromRGB(255, 85, 85),
	Color3.fromRGB(255, 166, 0),
	Color3.fromRGB(255, 235, 59),
	Color3.fromRGB(46, 204, 113),
	Color3.fromRGB(52, 152, 219),
	Color3.fromRGB(155, 89, 182),
	Color3.fromRGB(255, 102, 204),
}

local ADMIN_COLORS = {
	Color3.fromRGB(255, 88, 88),
	Color3.fromRGB(255, 156, 108),
}

local MODERATOR_COLORS = {
	Color3.fromRGB(98, 175, 255),
	Color3.fromRGB(43, 107, 224),
}

local MEMBER_COLORS = {
	Color3.fromRGB(228, 233, 242),
}

local CHAT_TAG_RAINBOW_SATURATION = 0.95
local CHAT_TAG_RAINBOW_VALUE = 1
local CHAT_TAG_RAINBOW_SPREAD = 0.72

local ROLE_DEFINITIONS: { [RoleId]: RoleDefinition } = {
	Owner = {
		id = "Owner",
		roleName = "Owner",
		tagText = "OWNER",
		priority = 400,
		canUseCommands = true,
		chatMode = "rainbow",
		chatColors = OWNER_COLORS,
		react = {
			tag = {
				textColor3 = Color3.fromRGB(255, 255, 255),
				effects = {
					rainbow = {
						enabled = true,
						gradient = true,
						speed = 0.2,
						saturation = 0.95,
						value = 1,
						spread = 0.16,
					},
					outline = {
						enabled = true,
						color = Color3.fromRGB(255, 255, 255),
						transparency = 0.82,
						thickness = 2,
					},
					shadow = {
						enabled = true,
						color = Color3.fromRGB(0, 0, 0),
						transparency = 0.28,
						offset = Vector2.new(2, 2),
						layers = 2,
					},
				},
			},
			name = {
				textColor3 = Color3.fromRGB(255, 255, 255),
				effects = {
					rainbow = {
						enabled = true,
						gradient = true,
						speed = 0.16,
						saturation = 0.92,
						value = 1,
						spread = 0.14,
					},
					shadow = {
						enabled = true,
						color = Color3.fromRGB(0, 0, 0),
						transparency = 0.38,
						offset = Vector2.new(1, 1),
						layers = 2,
					},
				},
			},
			message = {
				textColor3 = Color3.fromRGB(255, 255, 255),
				effects = {
					rainbow = {
						enabled = true,
						gradient = true,
						speed = 0.14,
						saturation = 0.9,
						value = 1,
						spread = 0.13,
					},
				},
			},
		},
	},
	Admin = {
		id = "Admin",
		roleName = "Admin",
		tagText = "ADMIN",
		priority = 300,
		canUseCommands = false,
		chatMode = "gradient",
		chatColors = ADMIN_COLORS,
		react = {
			tag = {
				textColor3 = Color3.fromRGB(255, 215, 215),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, ADMIN_COLORS[1]),
							ColorSequenceKeypoint.new(1, ADMIN_COLORS[2]),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
					outline = {
						enabled = true,
						color = Color3.fromRGB(70, 14, 14),
						transparency = 0.2,
						thickness = 2,
					},
					shadow = {
						enabled = true,
						color = Color3.fromRGB(35, 0, 0),
						transparency = 0.42,
						offset = Vector2.new(1, 1),
						layers = 2,
					},
				},
			},
			name = {
				textColor3 = Color3.fromRGB(255, 215, 215),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, ADMIN_COLORS[1]),
							ColorSequenceKeypoint.new(1, ADMIN_COLORS[2]),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
				},
			},
			message = {
				textColor3 = Color3.fromRGB(255, 220, 220),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 110, 110)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 192, 146)),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
				},
			},
		},
	},
	Moderator = {
		id = "Moderator",
		roleName = "Moderator",
		tagText = "MOD",
		priority = 200,
		canUseCommands = false,
		chatMode = "gradient",
		chatColors = MODERATOR_COLORS,
		react = {
			tag = {
				textColor3 = Color3.fromRGB(232, 242, 255),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, MODERATOR_COLORS[1]),
							ColorSequenceKeypoint.new(1, MODERATOR_COLORS[2]),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
					outline = {
						enabled = true,
						color = Color3.fromRGB(12, 35, 76),
						transparency = 0.25,
						thickness = 2,
					},
					shadow = {
						enabled = true,
						color = Color3.fromRGB(0, 17, 40),
						transparency = 0.45,
						offset = Vector2.new(1, 1),
						layers = 2,
					},
				},
			},
			name = {
				textColor3 = Color3.fromRGB(232, 242, 255),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, MODERATOR_COLORS[1]),
							ColorSequenceKeypoint.new(1, MODERATOR_COLORS[2]),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
				},
			},
			message = {
				textColor3 = Color3.fromRGB(220, 235, 255),
				effects = {
					gradient = {
						enabled = true,
						color = ColorSequence.new({
							ColorSequenceKeypoint.new(0, Color3.fromRGB(126, 197, 255)),
							ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 132, 255)),
						}),
						rotation = 0,
						offset = Vector2.new(0, 0),
						animated = false,
					},
				},
			},
		},
	},
	Member = {
		id = "Member",
		roleName = "Member",
		tagText = "PLAYER",
		priority = 100,
		canUseCommands = false,
		chatMode = "solid",
		chatColors = MEMBER_COLORS,
		react = {
			tag = {
				textColor3 = Color3.fromRGB(228, 233, 242),
				effects = {
					shadow = {
						enabled = true,
						color = Color3.fromRGB(0, 0, 0),
						transparency = 0.52,
						offset = Vector2.new(1, 1),
						layers = 1,
					},
				},
			},
			name = {
				textColor3 = Color3.fromRGB(228, 233, 242),
				effects = {},
			},
			message = {
				textColor3 = Color3.fromRGB(245, 247, 252),
				effects = {},
			},
		},
	},
}

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeUserId(userIdRaw: any): number?
	if typeof(userIdRaw) ~= "number" or userIdRaw ~= userIdRaw then
		return nil
	end
	local userId = math.floor(userIdRaw)
	if userId <= 0 then
		return nil
	end
	return userId
end

local function cloneArray<T>(source: { T }): { T }
	local output = table.create(#source)
	for index, value in source do
		output[index] = value
	end
	return output
end

local function deepClone(value: any): any
	if typeof(value) ~= "table" then
		return value
	end
	local output = {}
	for key, nestedValue in value do
		output[key] = deepClone(nestedValue)
	end
	return output
end

local function colorToHex(color: Color3): string
	local r = math.clamp(math.floor(color.R * 255 + 0.5), 0, 255)
	local g = math.clamp(math.floor(color.G * 255 + 0.5), 0, 255)
	local b = math.clamp(math.floor(color.B * 255 + 0.5), 0, 255)
	return string.format("#%02X%02X%02X", r, g, b)
end

local function buildRainbowGradientRichText(textRaw: any, phaseRaw: number?): string
	local text = if typeof(textRaw) == "string" then textRaw else tostring(textRaw)
	if text == "" then
		return ""
	end

	local phase = if typeof(phaseRaw) == "number" and phaseRaw == phaseRaw then phaseRaw else 0
	local characters = {}
	for character in string.gmatch(text, utf8.charpattern) do
		characters[#characters + 1] = character
	end
	if #characters <= 0 then
		return RichTextFormatter.escape(text)
	end

	local parts = table.create(#characters)
	for index, character in characters do
		local alpha = if #characters <= 1 then 0 else (index - 1) / (#characters - 1)
		local hue = (phase + alpha * CHAT_TAG_RAINBOW_SPREAD) % 1
		local color = Color3.fromHSV(hue, CHAT_TAG_RAINBOW_SATURATION, CHAT_TAG_RAINBOW_VALUE)
		parts[index] =
			string.format('<font color="%s">%s</font>', colorToHex(color), RichTextFormatter.escape(character))
	end
	return table.concat(parts)
end

local function containsUserId(list: { number }, userId: number): boolean
	for _, entry in list do
		if entry == userId then
			return true
		end
	end
	return false
end

function Role.getDefaultRoleOverrides(): RoleOverrides
	return {
		admins = cloneArray(DEFAULT_ROLE_OVERRIDES.admins),
		moderators = cloneArray(DEFAULT_ROLE_OVERRIDES.moderators),
	}
end

function Role.getDefinition(roleIdRaw: any): RoleDefinition
	local roleId = if roleIdRaw == "Owner"
			or roleIdRaw == "Admin"
			or roleIdRaw == "Moderator"
		then roleIdRaw
		else "Member"
	return ROLE_DEFINITIONS[roleId]
end

function Role.getPriority(roleIdRaw: any): number
	return Role.getDefinition(roleIdRaw).priority
end

function Role.canUseCommands(roleIdRaw: any): boolean
	return Role.getDefinition(roleIdRaw).canUseCommands
end

function Role.getTagText(roleIdRaw: any): string
	return Role.getDefinition(roleIdRaw).tagText
end

function Role.getReactTextStyle(roleIdRaw: any, surfaceRaw: any): TextLabelStyle
	local definition = Role.getDefinition(roleIdRaw)
	local surface = if surfaceRaw == "tag" or surfaceRaw == "name" then surfaceRaw else "message"
	local source = definition.react[surface]
	return deepClone(source)
end

function Role.createSnapshot(roleIdRaw: any, userIdRaw: any, userNameRaw: any, displayNameRaw: any): PlayerRoleSnapshot
	local definition = Role.getDefinition(roleIdRaw)
	local userId = sanitizeUserId(userIdRaw) or 0
	local userName = trim(userNameRaw)
	local displayName = trim(displayNameRaw)
	if userName == "" then
		userName = tostring(userId)
	end
	if displayName == "" then
		displayName = userName
	end

	return {
		userId = userId,
		userName = userName,
		displayName = displayName,
		roleId = definition.id,
		roleName = definition.roleName,
		tagText = definition.tagText,
		priority = definition.priority,
		canUseCommands = definition.canUseCommands,
	}
end

function Role.resolveRoleIdForPlayer(player: Player, contextRaw: RoleResolveContext?): RoleId
	local context = if typeof(contextRaw) == "table" then contextRaw else {}
	local ownerUserId = sanitizeUserId((context :: any).ownerUserId)
	if ownerUserId ~= nil and player.UserId == ownerUserId then
		return "Owner"
	end

	local overrides = if typeof((context :: any).roleOverrides) == "table"
		then (context :: any).roleOverrides
		else Role.getDefaultRoleOverrides()
	local admins = if typeof((overrides :: any).admins) == "table" then (overrides :: any).admins else {}
	local moderators = if typeof((overrides :: any).moderators) == "table" then (overrides :: any).moderators else {}
	if containsUserId(admins, player.UserId) then
		return "Admin"
	end
	if containsUserId(moderators, player.UserId) then
		return "Moderator"
	end

	local creatorGroupId = sanitizeUserId((context :: any).creatorGroupId)
	if creatorGroupId ~= nil then
		local adminMinRank = math.max(
			1,
			math.floor(
				if typeof((context :: any).adminMinGroupRank) == "number"
					then (context :: any).adminMinGroupRank
					else DEFAULT_ADMIN_MIN_GROUP_RANK
			)
		)
		local moderatorMinRank = math.max(
			1,
			math.floor(
				if typeof((context :: any).moderatorMinGroupRank) == "number"
					then (context :: any).moderatorMinGroupRank
					else DEFAULT_MODERATOR_MIN_GROUP_RANK
			)
		)
		local ok, rankOrError = pcall(function()
			return player:GetRankInGroup(creatorGroupId)
		end)
		if ok and typeof(rankOrError) == "number" then
			local rank = rankOrError :: number
			if rank >= adminMinRank then
				return "Admin"
			end
			if rank >= moderatorMinRank then
				return "Moderator"
			end
		end
	end

	return "Member"
end

function Role.buildChatTagRichText(roleIdRaw: any, phaseRaw: number?): string
	local definition = Role.getDefinition(roleIdRaw)
	local tagText = ("[%s]"):format(definition.tagText)
	if definition.id ~= "Member" then
		return buildRainbowGradientRichText(tagText, phaseRaw)
	end
	return string.format(
		'<font color="%s">%s</font>',
		colorToHex(definition.chatColors[1]),
		RichTextFormatter.escape(tagText)
	)
end

function Role.buildChatPrefixText(roleIdRaw: any, basePrefixTextRaw: any, phaseRaw: number?): string
	local basePrefixText = if typeof(basePrefixTextRaw) == "string" then basePrefixTextRaw else ""
	local tag = Role.buildChatTagRichText(roleIdRaw, phaseRaw)
	if basePrefixText == "" then
		return tag
	end
	return ("%s %s"):format(tag, basePrefixText)
end

function Role.decorateChatMessageText(_roleIdRaw: any, messageTextRaw: any, _phaseRaw: number?): string
	local messageText = if typeof(messageTextRaw) == "string" then messageTextRaw else tostring(messageTextRaw)
	if messageText == "" then
		return ""
	end

	return RichTextFormatter.escape(messageText)
end

return Role
