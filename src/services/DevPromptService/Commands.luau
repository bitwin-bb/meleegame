--!strict
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevPromptServiceUtils = require(ReplicatedStorage.Shared.Services.DevPromptService.DevPromptServiceUtils)

type ConsoleEntry = DevPromptServiceUtils.ConsoleEntry

export type CommandResult = {
	ok: boolean,
	entries: { ConsoleEntry },
	clearBefore: boolean,
	echoInput: boolean,
}

export type CommandDefinition = {
	name: string,
	aliases: { string },
	description: string,
	usage: string,
	run: (context: CommandContext) -> (),
}

export type CommandContext = {
	service: any,
	player: Player,
	commandName: string,
	rawText: string,
	args: { string },
	result: CommandResult,
	reply: (self: CommandContext, kind: DevPromptServiceUtils.ConsoleEntryKind, text: string) -> (),
	resolvePlayer: (self: CommandContext, queryRaw: any, defaultPlayerRaw: Player?) -> (Player?, string?),
}

local Commands = {}

local commandDefinitions = {} :: { CommandDefinition }
local commandAliasMap = {} :: { [string]: CommandDefinition }

local function addCommand(definition: CommandDefinition)
	commandDefinitions[#commandDefinitions + 1] = definition
	commandAliasMap[string.lower(definition.name)] = definition
	for _, alias in definition.aliases do
		commandAliasMap[string.lower(alias)] = definition
	end
end

local function newResult(): CommandResult
	return {
		ok = true,
		entries = {},
		clearBefore = false,
		echoInput = true,
	}
end

local function parseWholeNumber(valueRaw: any): number?
	local text = DevPromptServiceUtils.trim(valueRaw)
	if text == "" then
		return nil
	end
	if string.match(text, "^%-?%d+$") == nil then
		return nil
	end
	local value = tonumber(text)
	if value == nil or value ~= value then
		return nil
	end
	return math.floor(value)
end

local function parseNumber(valueRaw: any): number?
	local text = DevPromptServiceUtils.trim(valueRaw)
	if text == "" then
		return nil
	end

	local value = tonumber(text)
	if value == nil or value ~= value then
		return nil
	end
	return value
end

local function parsePositiveWholeNumber(valueRaw: any, fallback: number, minimum: number, maximum: number): number
	local value = parseWholeNumber(valueRaw)
	if value == nil then
		return fallback
	end
	return math.clamp(value, minimum, maximum)
end

local function joinArgs(args: { string }, startIndex: number): string
	if startIndex > #args then
		return ""
	end
	local output = table.create(#args - startIndex + 1)
	local outputIndex = 0
	for index = startIndex, #args do
		outputIndex += 1
		output[outputIndex] = args[index]
	end
	return table.concat(output, " ")
end

local function normalizeToken(valueRaw: any): string
	local text = DevPromptServiceUtils.trim(valueRaw)
	if text == "" then
		return ""
	end
	return string.lower(string.gsub(text, "[%s_%-%.]", ""))
end

local WEATHER_TYPE_BY_VARIANT = {
	clear = "Clear",
	sun = "Clear",
	sunny = "Clear",
	rain = "Rainstorm",
	rainy = "Rainstorm",
	rainstorm = "Rainstorm",
	storm = "Rainstorm",
	thunder = "Thunderstorm",
	lightning = "Thunderstorm",
	thunderstorm = "Thunderstorm",
}

local DAYLIGHT_ENABLE_VARIANTS = {
	on = true,
	enable = true,
	enabled = true,
	resume = true,
}

local DAYLIGHT_DISABLE_VARIANTS = {
	off = true,
	disable = true,
	disabled = true,
	pause = true,
	stop = true,
}

local DAYLIGHT_TOGGLE_VARIANTS = {
	toggle = true,
	switch = true,
}

local DAYLIGHT_TIME_VARIANTS = {
	time = true,
	clock = true,
	set = true,
}

local function resolveWeatherType(valueRaw: any): string?
	local normalized = normalizeToken(valueRaw)
	if normalized == "" then
		return nil
	end
	return WEATHER_TYPE_BY_VARIANT[normalized]
end

local function buildWeatherServiceErrorMessage(reasonRaw: any, fallback: string): string
	local reason = DevPromptServiceUtils.trim(reasonRaw)
	if reason == "service_unavailable" then
		return "Weather service is not available in this server."
	end
	if reason == "service_disabled" then
		return "Weather service is disabled in this server."
	end
	return fallback
end

local function sortDefinitions()
	table.sort(commandDefinitions, function(a, b)
		return a.name < b.name
	end)
end

local function createContext(service: any, player: Player, commandName: string, rawText: string, args: { string }): CommandContext
	local result = newResult()
	local context = {
		service = service,
		player = player,
		commandName = commandName,
		rawText = rawText,
		args = args,
		result = result,
		reply = function(self: CommandContext, kind: DevPromptServiceUtils.ConsoleEntryKind, text: string)
			self.result.entries[#self.result.entries + 1] = DevPromptServiceUtils.createConsoleEntry(kind, text, {
				timestamp = os.clock(),
			})
		end,
		resolvePlayer = function(self: CommandContext, queryRaw: any, defaultPlayerRaw: Player?): (Player?, string?)
			return self.service:resolvePlayerQuery(queryRaw, defaultPlayerRaw)
		end,
	}
	return context
end

local function findDefinition(nameRaw: any): CommandDefinition?
	local key = DevPromptServiceUtils.normalizeCommandName(nameRaw)
	if key == "" then
		return nil
	end
	return commandAliasMap[key]
end

addCommand({
	name = "clear",
	aliases = { "cls" },
	description = "Clear the local developer console output or remove all active entities.",
	usage = "clear [entities]",
	run = function(context: CommandContext)
		local option = normalizeToken(context.args[1])
		if option ~= "" then
			if option ~= "entities" and option ~= "entity" and option ~= "all" then
				context.result.ok = false
				context:reply("error", "Usage: clear [entities]")
				return
			end

			local removedNpcCount, removedBossCount, removedProjectileCount = context.service:clearAllEntities()
			context:reply(
				"success",
				("Cleared %d NPC(s), %d boss(es), and %d projectile(s)."):format(
					removedNpcCount,
					removedBossCount,
					removedProjectileCount
				)
			)
			return
		end

		context.result.clearBefore = true
		context.result.echoInput = false
	end,
})

addCommand({
	name = "echo",
	aliases = { "say" },
	description = "Print a line back into the developer console.",
	usage = 'echo "message"',
	run = function(context: CommandContext)
		local message = joinArgs(context.args, 1)
		if message == "" then
			context.result.ok = false
			context:reply("error", "Usage: echo \"message\"")
			return
		end
		context:reply("info", message)
	end,
})

addCommand({
	name = "help",
	aliases = { "commands", "?" },
	description = "List available commands or show help for one command.",
	usage = "help [command]",
	run = function(context: CommandContext)
		local query = context.args[1]
		if query ~= nil then
			local definition = findDefinition(query)
			if definition == nil then
				context.result.ok = false
				context:reply("error", ("Unknown command \"%s\"."):format(query))
				return
			end
			local aliasText = if #definition.aliases > 0
				then ("Aliases: %s"):format(table.concat(definition.aliases, ", "))
				else "Aliases: none"
			context:reply(
				"info",
				("%s\n%s\nUsage: %s"):format(definition.description, aliasText, definition.usage)
			)
			return
		end

		local lines = table.create(#commandDefinitions)
		for index, definition in commandDefinitions do
			lines[index] = ("%s - %s"):format(definition.usage, definition.description)
		end
		context:reply("info", table.concat(lines, "\n"))
	end,
})

addCommand({
	name = "owner",
	aliases = { "creator" },
	description = "Show the resolved experience owner for command permissions.",
	usage = "owner",
	run = function(context: CommandContext)
		local ownerUserId = context.service.ownerUserId
		if ownerUserId == nil then
			context:reply("warning", "The game owner could not be resolved for this server.")
			return
		end
		local ownerName = context.service.ownerName
		if ownerName == "" then
			ownerName = tostring(ownerUserId)
		end
		context:reply("info", ("Resolved owner: %s (%d)"):format(ownerName, ownerUserId))
	end,
})

addCommand({
	name = "players",
	aliases = { "list", "who" },
	description = "List players currently in the server with their resolved roles.",
	usage = "players",
	run = function(context: CommandContext)
		local roleSnapshots = context.service:getSortedPlayerRoleSnapshots()
		if #roleSnapshots <= 0 then
			context:reply("warning", "No players are currently tracked.")
			return
		end

		local lines = table.create(#roleSnapshots)
		for index, snapshot in roleSnapshots do
			lines[index] = ("[%s] %s (%s)"):format(snapshot.tagText, snapshot.userName, snapshot.roleName)
		end
		context:reply("info", table.concat(lines, "\n"))
	end,
})

addCommand({
	name = "role",
	aliases = { "whois" },
	description = "Inspect the resolved role for a player.",
	usage = "role [playerName]",
	run = function(context: CommandContext)
		local targetPlayer, errorMessage = context:resolvePlayer(context.args[1], context.player)
		if targetPlayer == nil then
			context.result.ok = false
			context:reply("error", errorMessage or "Player not found.")
			return
		end

		local snapshot = context.service:getPlayerRoleSnapshot(targetPlayer)
		if snapshot == nil then
			context.result.ok = false
			context:reply("error", ("No role snapshot is available for %s."):format(targetPlayer.Name))
			return
		end

		local permissionText = if snapshot.canUseCommands then "can use commands" else "cannot use commands"
		context:reply(
			"info",
			("%s is %s (%s) and %s."):format(snapshot.userName, snapshot.roleName, snapshot.tagText, permissionText)
		)
	end,
})

addCommand({
	name = "sethealth",
	aliases = { "sethp", "maxhealth", "maxhp" },
	description = "Permanently set a player's max health and refill it.",
	usage = "sethealth [playerName] <amount>",
	run = function(context: CommandContext)
		local firstArg = context.args[1]
		local secondArg = context.args[2]
		if firstArg == nil or firstArg == "" then
			context.result.ok = false
			context:reply("error", "Usage: sethealth [playerName] <amount>")
			return
		end

		local targetPlayer = context.player
		local amountToken = firstArg
		if parseWholeNumber(firstArg) == nil then
			local resolvedPlayer, errorMessage = context:resolvePlayer(firstArg, nil)
			if resolvedPlayer == nil then
				context.result.ok = false
				context:reply("error", errorMessage or "Player not found.")
				return
			end
			targetPlayer = resolvedPlayer
			amountToken = secondArg
		end

		local amount = parseWholeNumber(amountToken)
		if amount == nil then
			context.result.ok = false
			context:reply("error", "Health amount must be a whole number between 1 and 500.")
			return
		end

		local ok, currentHealth, maxHealth = context.service:setPlayerMaxHealthTarget(targetPlayer, amount)
		if not ok then
			context.result.ok = false
			context:reply("error", ("Failed to set health for %s."):format(targetPlayer.Name))
			return
		end

		context:reply(
			"success",
			("%s max health set to %.0f HP. Current health: %.0f/%.0f."):format(
				targetPlayer.Name,
				maxHealth,
				currentHealth,
				maxHealth
			)
		)
	end,
})

addCommand({
	name = "setmana",
	aliases = { "maxmana" },
	description = "Permanently set a player's max mana and refill it.",
	usage = "setmana [playerName] <amount>",
	run = function(context: CommandContext)
		local firstArg = context.args[1]
		local secondArg = context.args[2]
		if firstArg == nil or firstArg == "" then
			context.result.ok = false
			context:reply("error", "Usage: setmana [playerName] <amount>")
			return
		end

		local targetPlayer = context.player
		local amountToken = firstArg
		if parseWholeNumber(firstArg) == nil then
			local resolvedPlayer, errorMessage = context:resolvePlayer(firstArg, nil)
			if resolvedPlayer == nil then
				context.result.ok = false
				context:reply("error", errorMessage or "Player not found.")
				return
			end
			targetPlayer = resolvedPlayer
			amountToken = secondArg
		end

		local amount = parseWholeNumber(amountToken)
		if amount == nil then
			context.result.ok = false
			context:reply("error", "Mana amount must be a whole number between 1 and 200.")
			return
		end

		local ok, currentMana, maxMana = context.service:setPlayerMaxManaTarget(targetPlayer, amount)
		if not ok then
			context.result.ok = false
			context:reply("error", ("Failed to set mana for %s."):format(targetPlayer.Name))
			return
		end

		context:reply(
			"success",
			("%s max mana set to %.0f. Current mana: %.0f/%.0f."):format(targetPlayer.Name, maxMana, currentMana, maxMana)
		)
	end,
})

addCommand({
	name = "heal",
	aliases = { "hp" },
	description = "Heal yourself or another player.",
	usage = "heal [playerName] [amount]",
	run = function(context: CommandContext)
		local firstArg = context.args[1]
		local secondArg = context.args[2]
		local targetPlayer = context.player
		local amount = math.huge

		if firstArg ~= nil and parseWholeNumber(firstArg) == nil then
			local resolvedPlayer, errorMessage = context:resolvePlayer(firstArg, nil)
			if resolvedPlayer == nil then
				context.result.ok = false
				context:reply("error", errorMessage or "Player not found.")
				return
			end
			targetPlayer = resolvedPlayer
			amount = parsePositiveWholeNumber(secondArg, 999999, 1, 999999)
		else
			amount = parsePositiveWholeNumber(firstArg, 999999, 1, 999999)
		end

		local didHeal, resultingHealth = context.service:healPlayerTarget(targetPlayer, amount)
		if not didHeal then
			context.result.ok = false
			context:reply("error", ("Failed to heal %s."):format(targetPlayer.Name))
			return
		end
		context:reply("success", ("%s healed to %.1f HP."):format(targetPlayer.Name, resultingHealth))
	end,
})

addCommand({
	name = "give",
	aliases = { "item" },
	description = "Give an item to yourself or another player.",
	usage = "give <itemId> [playerName] [amount]",
	run = function(context: CommandContext)
		local itemId = context.args[1]
		if itemId == nil or itemId == "" then
			context.result.ok = false
			context:reply("error", "Usage: give <itemId> [playerName] [amount]")
			return
		end

		local targetPlayer = context.player
		local amount = 1
		local secondArg = context.args[2]
		local thirdArg = context.args[3]
		if secondArg ~= nil and parseWholeNumber(secondArg) == nil then
			local resolvedPlayer, errorMessage = context:resolvePlayer(secondArg, nil)
			if resolvedPlayer == nil then
				context.result.ok = false
				context:reply("error", errorMessage or "Player not found.")
				return
			end
			targetPlayer = resolvedPlayer
			amount = parsePositiveWholeNumber(thirdArg, 1, 1, 9999)
		else
			amount = parsePositiveWholeNumber(secondArg, 1, 1, 9999)
		end

		local ok, canonicalItemId, addedAmount, requestedAmount, reason =
			context.service:giveItemToPlayer(targetPlayer, itemId, amount)
		if not ok then
			context.result.ok = false
			context:reply(
				"error",
				("Failed to give \"%s\" to %s%s."):format(
					tostring(itemId),
					targetPlayer.Name,
					if reason ~= nil and reason ~= "" then (" (%s)"):format(reason) else ""
				)
			)
			return
		end

		context:reply(
			"success",
			("Gave %d/%d %s to %s."):format(addedAmount, requestedAmount, canonicalItemId, targetPlayer.Name)
		)
	end,
})

addCommand({
	name = "spawn",
	aliases = { "summon" },
	description = "Spawn a supported entity near you. This supports slime variants and Eye of Cthulhu.",
	usage = "spawn <entity> [amount] [simulationSpeed] [aggressiveness]",
	run = function(context: CommandContext)
		local entityToken = context.args[1]
		if entityToken == nil or entityToken == "" then
			context.result.ok = false
			context:reply("error", "Usage: spawn <entity> [amount] [simulationSpeed] [aggressiveness]")
			return
		end

		local entityType = normalizeToken(entityToken)
		local amount = parsePositiveWholeNumber(
			context.args[2],
			1,
			1,
			if entityType == "eye" or entityType == "eoc" or entityType == "eyeofcthulhu" then 5 else 20
		)
		local simulationSpeed = nil :: number?
		local aggressiveness = nil :: number?
		if context.args[3] ~= nil and context.args[3] ~= "" then
			local parsed = parseNumber(context.args[3])
			if parsed == nil then
				context.result.ok = false
				context:reply("error", "Simulation speed must be a number between 0.05 and 5.")
				return
			end
			simulationSpeed = math.clamp(parsed, 0.05, 5)
		end
		if context.args[4] ~= nil and context.args[4] ~= "" then
			local parsed = parseNumber(context.args[4])
			if parsed == nil then
				context.result.ok = false
				context:reply("error", "Aggressiveness must be a number between 0.1 and 3.")
				return
			end
			aggressiveness = math.clamp(parsed, 0.1, 3)
		end

		local ok, spawnedCount, reason = context.service:spawnEntityForPlayer(context.player, entityToken, amount, {
			simulationSpeed = simulationSpeed,
			aggressiveness = aggressiveness,
		})
		if not ok then
			context.result.ok = false
			context:reply(
				"error",
				if reason ~= nil and reason ~= ""
					then ("Spawn failed: %s"):format(reason)
					else "Spawn failed."
			)
			return
		end

		context:reply("success", ("Spawned %d %s instance(s)."):format(spawnedCount, entityToken))
	end,
})

addCommand({
	name = "weather",
	aliases = { "forecast" },
	description = "Change the active weather preset for the server.",
	usage = "weather <clear|rainstorm|thunderstorm> [transitionSeconds]",
	run = function(context: CommandContext)
		local weatherType = resolveWeatherType(context.args[1])
		if weatherType == nil then
			context.result.ok = false
			context:reply("error", "Weather must be clear, rainstorm, or thunderstorm.")
			return
		end

		local transitionSeconds = nil :: number?
		if context.args[2] ~= nil and context.args[2] ~= "" then
			local parsed = parseNumber(context.args[2])
			if parsed == nil then
				context.result.ok = false
				context:reply("error", "Transition seconds must be a number between 0 and 60.")
				return
			end
			transitionSeconds = math.clamp(parsed, 0, 60)
		end

		local ok, appliedWeatherType, appliedTransition, reason =
			context.service:setWeatherState(weatherType, transitionSeconds)
		if not ok then
			context.result.ok = false
			context:reply("error", buildWeatherServiceErrorMessage(reason, "Failed to change weather."))
			return
		end

		context:reply(
			"success",
			("Weather changed to %s over %.1f seconds."):format(appliedWeatherType or weatherType, appliedTransition)
		)
	end,
})

addCommand({
	name = "daylight",
	aliases = { "clock", "timeofday" },
	description = "Control the day-night cycle or set the current clock time.",
	usage = "daylight <on|off|toggle|time> [clockTime]",
	run = function(context: CommandContext)
		local firstArg = context.args[1]
		if firstArg == nil or firstArg == "" then
			context.result.ok = false
			context:reply("error", "Usage: daylight <on|off|toggle|time> [clockTime]")
			return
		end

		local parsedClockTime = parseNumber(firstArg)
		if parsedClockTime ~= nil then
			local ok, clockTime, reason = context.service:setDaylightClockTime(parsedClockTime)
			if not ok then
				context.result.ok = false
				context:reply("error", buildWeatherServiceErrorMessage(reason, "Failed to set clock time."))
				return
			end

			context:reply("success", ("Clock time set to %.2f."):format(clockTime))
			return
		end

		local normalized = normalizeToken(firstArg)
		if DAYLIGHT_TIME_VARIANTS[normalized] == true then
			local clockTimeArg = context.args[2]
			local clockTime = parseNumber(clockTimeArg)
			if clockTime == nil then
				context.result.ok = false
				context:reply("error", "Usage: daylight time <clockTime>")
				return
			end

			local ok, nextClockTime, reason = context.service:setDaylightClockTime(clockTime)
			if not ok then
				context.result.ok = false
				context:reply("error", buildWeatherServiceErrorMessage(reason, "Failed to set clock time."))
				return
			end

			context:reply("success", ("Clock time set to %.2f."):format(nextClockTime))
			return
		end

		local desiredEnabled = nil :: boolean?
		if DAYLIGHT_ENABLE_VARIANTS[normalized] == true then
			desiredEnabled = true
		elseif DAYLIGHT_DISABLE_VARIANTS[normalized] == true then
			desiredEnabled = false
		elseif DAYLIGHT_TOGGLE_VARIANTS[normalized] == true then
			local state = context.service:getWeatherStateSnapshot()
			if state == nil then
				context.result.ok = false
				context:reply("error", buildWeatherServiceErrorMessage("service_unavailable", "Failed to inspect daylight state."))
				return
			end
			desiredEnabled = not state.dayNightCycleEnabled
		else
			context.result.ok = false
			context:reply("error", "Usage: daylight <on|off|toggle|time> [clockTime]")
			return
		end

		local ok, nextEnabled, clockTime, reason = context.service:setDaylightCycleEnabled(desiredEnabled)
		if not ok then
			context.result.ok = false
			context:reply("error", buildWeatherServiceErrorMessage(reason, "Failed to change daylight cycle."))
			return
		end

		context:reply(
			"success",
			("Daylight cycle %s at %.2f."):format(if nextEnabled then "enabled" else "disabled", clockTime)
		)
	end,
})

addCommand({
	name = "godmode",
	aliases = { "gm", "immortal" },
	description = "Toggle invulnerability for yourself or another player.",
	usage = "godmode [playerName] [on|off|toggle]",
	run = function(context: CommandContext)
		local targetPlayer = context.player
		local modeToken = context.args[1]
		local secondArg = context.args[2]

		if modeToken ~= nil and modeToken ~= "" then
			local normalizedMode = string.lower(modeToken)
			if normalizedMode ~= "on" and normalizedMode ~= "off" and normalizedMode ~= "toggle" then
				local resolvedPlayer, errorMessage = context:resolvePlayer(modeToken, nil)
				if resolvedPlayer == nil then
					context.result.ok = false
					context:reply("error", errorMessage or "Player not found.")
					return
				end
				targetPlayer = resolvedPlayer
				modeToken = secondArg
			end
		end

		local normalizedMode = if modeToken ~= nil and modeToken ~= ""
			then string.lower(modeToken)
			else "toggle"
		local desiredEnabled: boolean?
		if normalizedMode == "on" then
			desiredEnabled = true
		elseif normalizedMode == "off" then
			desiredEnabled = false
		elseif normalizedMode == "toggle" then
			desiredEnabled = nil
		else
			context.result.ok = false
			context:reply("error", "Mode must be on, off, or toggle.")
			return
		end

		local nextEnabled = context.service:setGodmode(targetPlayer, desiredEnabled)
		context:reply(
			"success",
			("Godmode %s for %s."):format(if nextEnabled then "enabled" else "disabled", targetPlayer.Name)
		)
	end,
})

addCommand({
	name = "fly",
	aliases = { "airwalk" },
	description = "Enable flight for yourself or another player.",
	usage = "fly [playerName] [speed]",
	run = function(context: CommandContext)
		local firstArg = context.args[1]
		local secondArg = context.args[2]
		local targetPlayer = context.player
		local speed = nil :: number?

		if firstArg ~= nil and firstArg ~= "" then
			if parseWholeNumber(firstArg) ~= nil then
				speed = parsePositiveWholeNumber(
					firstArg,
					DevPromptServiceUtils.DEFAULT_FLY_SPEED,
					DevPromptServiceUtils.MIN_FLY_SPEED,
					DevPromptServiceUtils.MAX_FLY_SPEED
				)
			else
				local resolvedPlayer, errorMessage = context:resolvePlayer(firstArg, nil)
				if resolvedPlayer == nil then
					context.result.ok = false
					context:reply("error", errorMessage or "Player not found.")
					return
				end
				targetPlayer = resolvedPlayer
				if secondArg ~= nil and secondArg ~= "" then
					local parsedSpeed = parseWholeNumber(secondArg)
					if parsedSpeed == nil then
						context.result.ok = false
						context:reply(
							"error",
							("Flight speed must be a whole number between %d and %d."):format(
								DevPromptServiceUtils.MIN_FLY_SPEED,
								DevPromptServiceUtils.MAX_FLY_SPEED
							)
						)
						return
					end
					speed = math.clamp(
						parsedSpeed,
						DevPromptServiceUtils.MIN_FLY_SPEED,
						DevPromptServiceUtils.MAX_FLY_SPEED
					)
				end
			end
		end

		local nextEnabled, appliedSpeed = context.service:setFlyEnabled(targetPlayer, true, speed)
		if not nextEnabled then
			context.result.ok = false
			context:reply("error", ("Failed to enable flight for %s."):format(targetPlayer.Name))
			return
		end

		context:reply("success", ("Flight enabled for %s at speed %d."):format(targetPlayer.Name, appliedSpeed))
	end,
})

addCommand({
	name = "unfly",
	aliases = { "land" },
	description = "Disable flight for yourself or another player.",
	usage = "unfly [playerName]",
	run = function(context: CommandContext)
		local targetPlayer, errorMessage = context:resolvePlayer(context.args[1], context.player)
		if targetPlayer == nil then
			context.result.ok = false
			context:reply("error", errorMessage or "Player not found.")
			return
		end

		local nextEnabled = context.service:setFlyEnabled(targetPlayer, false)
		if nextEnabled then
			context.result.ok = false
			context:reply("error", ("Failed to disable flight for %s."):format(targetPlayer.Name))
			return
		end

		context:reply("success", ("Flight disabled for %s."):format(targetPlayer.Name))
	end,
})

sortDefinitions()

function Commands.getDefinitions(): { CommandDefinition }
	local definitions = table.create(#commandDefinitions)
	for index, definition in commandDefinitions do
		definitions[index] = {
			name = definition.name,
			aliases = table.clone(definition.aliases),
			description = definition.description,
			usage = definition.usage,
			run = definition.run,
		}
	end
	return definitions
end

function Commands.execute(service: any, player: Player, rawTextRaw: any): CommandResult
	local rawText = DevPromptServiceUtils.trim(rawTextRaw)
	local result = newResult()
	if rawText == "" then
		result.ok = false
		result.echoInput = false
		return result
	end

	local normalizedText = DevPromptServiceUtils.stripCommandPrefix(rawText, service.commandPrefix)
	local tokens = DevPromptServiceUtils.tokenizeCommandText(normalizedText)
	if #tokens <= 0 then
		result.ok = false
		result.echoInput = false
		return result
	end

	local definition = findDefinition(tokens[1])
	if definition == nil then
		result.ok = false
		result.entries[1] = DevPromptServiceUtils.createConsoleEntry(
			"error",
			("Unknown command \"%s\". Use help to list commands."):format(tokens[1])
		)
		return result
	end

	local args = table.create(math.max(0, #tokens - 1))
	for index = 2, #tokens do
		args[#args + 1] = tokens[index]
	end
	local context = createContext(service, player, definition.name, normalizedText, args)

	local ok, errorMessage = pcall(function()
		definition.run(context)
	end)
	if not ok then
		context.result.ok = false
		context.result.entries[#context.result.entries + 1] = DevPromptServiceUtils.createConsoleEntry(
			"error",
			("Command \"%s\" failed: %s"):format(definition.name, tostring(errorMessage))
		)
	end

	return context.result
end

return Commands
