--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for SpawnServer.")

local BossServiceUtils = require(gameRoot.Shared.Services.BossServiceUtils)
local BossServiceServer = require(gameRoot.Server.Services.BossServiceServer)
local NpcServiceServer = require(gameRoot.Server.Services.NpcServiceServer)

type EntityEntry = {
	Id: string,
	Kind: string,
	Name: string,
}

local function joinParts(parts: { string }): string
	return table.concat(parts, ", ")
end

local function formatReason(reasonRaw: any): string
	if typeof(reasonRaw) ~= "string" or reasonRaw == "" then
		return "unknown reason"
	end
	return string.lower(string.gsub(reasonRaw, "_", " "))
end

local function spawnBossForPlayer(entity: EntityEntry, player: Player, spawnIndex: number): (boolean, string?)
	local rootPart = BossServiceUtils.resolveCharacterRootPart(player)
	if rootPart == nil then
		return false, "missing_character"
	end

	local boss, reason = BossServiceServer:spawnBoss({
		bossId = entity.Id,
		targetPlayer = player,
		spawnSource = "DebugCommand",
		encounterChannel = BossServiceServer:createUniqueDebugEncounterChannel(entity.Id, player, spawnIndex),
		spawnPosition = rootPart.Position + Vector3.new(0, 18, 0),
		planeX = rootPart.Position.X,
	})
	if boss == nil then
		return false, reason
	end

	return true, nil
end

local function spawnNpcForPlayer(entity: EntityEntry, player: Player, spawnIndex: number): (boolean, string?)
	local runtime, reason = NpcServiceServer:spawnDebugNpcById(entity.Id, player, spawnIndex)
	if runtime == nil then
		return false, reason
	end

	return true, nil
end

return function(_context, entity: EntityEntry, players: { Player }, amountRaw: number)
	local amount = math.max(1, math.floor(amountRaw))
	local spawned = {}
	local failed = {}

	for _, player in players do
		local spawnedCount = 0

		for spawnIndex = 1, amount do
			local ok = false
			local reason = nil :: string?

			if entity.Kind == "Boss" then
				ok, reason = spawnBossForPlayer(entity, player, spawnIndex)
			elseif entity.Kind == "Npc" then
				ok, reason = spawnNpcForPlayer(entity, player, spawnIndex)
			else
				reason = "unsupported_entity_kind"
			end

			if ok then
				spawnedCount += 1
			else
				failed[#failed + 1] = (`{player.Name} ({formatReason(reason)})`)
			end
		end

		if spawnedCount > 0 then
			spawned[#spawned + 1] = (`{player.Name} x{spawnedCount}`)
		end
	end

	local responseParts = {}
	if #spawned > 0 then
		responseParts[#responseParts + 1] = (`Spawned {entity.Name} for {joinParts(spawned)}.`)
	end
	if #failed > 0 then
		responseParts[#responseParts + 1] = (`Failed for {joinParts(failed)}.`)
	end

	return table.concat(responseParts, " ")
end
