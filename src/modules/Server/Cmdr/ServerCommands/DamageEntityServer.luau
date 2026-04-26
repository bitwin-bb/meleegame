--!strict
local gameRoot = script:FindFirstAncestor("game")
assert(gameRoot ~= nil, "Missing Nevermore game root for DamageEntityServer.")

local BossServiceUtils = require(gameRoot.Shared.Services.BossServiceUtils)
local BossServiceServer = require(gameRoot.Server.Services.BossServiceServer)
local NpcServiceServer = require(gameRoot.Server.Services.NpcServiceServer)

type EntityEntry = {
	Id: string,
	Kind: string,
	Name: string,
	Tokens: { string }?,
	CanonicalToken: string?,
}

type NpcRuntime = {
	id: string,
	entityId: string?,
	displayName: string,
	hp: number,
	maxHp: number,
	isAlive: boolean,
	isRemoving: boolean,
	slime: {
		hp: number,
		maxHp: number,
		rootPart: BasePart?,
		model: Model?,
		getPosition: (self: any) -> Vector3?,
	},
}

type BossObject = {
	id: string,
	bossId: string,
	displayName: string,
	hp: number,
	maxHp: number,
	isAlive: boolean,
	isDestroyed: boolean?,
	planeX: number?,
	position: Vector3?,
	rootPart: BasePart?,
	model: Model?,
	takeDamage: (self: BossObject, damageRaw: any, sourceRaw: any?, contextRaw: any?) -> number,
}

local KILL_DAMAGE = 10 ^ 9

local function normalizeToken(valueRaw: any): string
	return BossServiceUtils.normalizeToken(valueRaw)
end

local function resolvePlayerRootPart(player: Player): BasePart?
	return BossServiceUtils.resolveCharacterRootPart(player)
end

local function resolveNpcPosition(runtime: NpcRuntime): Vector3?
	local slime = runtime.slime
	if slime == nil then
		return nil
	end

	local slimePosition = slime:getPosition()
	if typeof(slimePosition) == "Vector3" then
		return slimePosition
	end

	local rootPart = slime.rootPart
	if rootPart ~= nil then
		return rootPart.Position
	end

	local model = slime.model
	if model ~= nil then
		local ok, pivotOrError = pcall(function()
			return model:GetPivot()
		end)
		if ok and typeof(pivotOrError) == "CFrame" then
			return pivotOrError.Position
		end
	end

	return nil
end

local function resolveBossPosition(boss: BossObject): Vector3?
	if typeof(boss.position) == "Vector3" then
		return boss.position
	end

	if boss.rootPart ~= nil then
		return boss.rootPart.Position
	end

	local model = boss.model
	if model ~= nil then
		local ok, pivotOrError = pcall(function()
			return model:GetPivot()
		end)
		if ok and typeof(pivotOrError) == "CFrame" then
			return pivotOrError.Position
		end
	end

	return nil
end

local function entityTokens(entity: EntityEntry): { string }
	local tokens = {}
	tokens[#tokens + 1] = normalizeToken(entity.Id)
	tokens[#tokens + 1] = normalizeToken(entity.Name)

	if typeof(entity.CanonicalToken) == "string" then
		tokens[#tokens + 1] = normalizeToken(entity.CanonicalToken)
	end

	if typeof(entity.Tokens) == "table" then
		for _, token in entity.Tokens do
			tokens[#tokens + 1] = normalizeToken(token)
		end
	end

	return tokens
end

local function matchesNpcRuntime(entity: EntityEntry, runtime: NpcRuntime): boolean
	if runtime.isRemoving or not runtime.isAlive then
		return false
	end

	local runtimeTokens = {
		normalizeToken(runtime.entityId),
		normalizeToken(runtime.displayName),
	}
	local expectedTokens = entityTokens(entity)

	for _, runtimeToken in runtimeTokens do
		if runtimeToken ~= "" then
			for _, expectedToken in expectedTokens do
				if expectedToken ~= "" and runtimeToken == expectedToken then
					return true
				end
			end
		end
	end

	return false
end

local function matchesBoss(entity: EntityEntry, boss: BossObject): boolean
	if boss.isAlive ~= true or boss.isDestroyed == true then
		return false
	end

	local bossId = normalizeToken(boss.bossId)
	if bossId == "" then
		return false
	end

	for _, expectedToken in entityTokens(entity) do
		if expectedToken ~= "" and bossId == expectedToken then
			return true
		end
	end

	return false
end

local function findNearestNpcRuntime(entity: EntityEntry, player: Player, seenIds: { [string]: boolean }): NpcRuntime?
	local rootPart = resolvePlayerRootPart(player)
	if rootPart == nil then
		return nil
	end

	local nearestRuntime = nil :: NpcRuntime?
	local nearestDistance = math.huge

	for runtimeId, runtime in NpcServiceServer.runtimes do
		if seenIds[runtimeId] == true or not matchesNpcRuntime(entity, runtime) then
			continue
		end

		local position = resolveNpcPosition(runtime)
		if position == nil then
			continue
		end

		local distance = (position - rootPart.Position).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestRuntime = runtime
		end
	end

	return nearestRuntime
end

local function findNearestBoss(entity: EntityEntry, player: Player, seenIds: { [string]: boolean }): BossObject?
	local rootPart = resolvePlayerRootPart(player)
	if rootPart == nil then
		return nil
	end

	local nearestBoss = nil :: BossObject?
	local nearestDistance = math.huge

	for runtimeId, boss in BossServiceServer.controllersById do
		if seenIds[runtimeId] == true or not matchesBoss(entity, boss) then
			continue
		end

		local bossPosition = resolveBossPosition(boss)
		if bossPosition == nil then
			continue
		end

		local playerPosition = rootPart.Position
		if typeof(boss.planeX) == "number" then
			playerPosition = BossServiceUtils.projectPositionToPlaneX(playerPosition, boss.planeX)
		end

		local distance = (bossPosition - playerPosition).Magnitude
		if distance < nearestDistance then
			nearestDistance = distance
			nearestBoss = boss
		end
	end

	return nearestBoss
end

local function formatHealth(currentHpRaw: any, maxHpRaw: any): string
	local currentHp = math.max(0, math.floor(BossServiceUtils.sanitizeNumber(currentHpRaw, 0, 0, 10 ^ 9) + 0.5))
	local maxHp = math.max(currentHp, math.floor(BossServiceUtils.sanitizeNumber(maxHpRaw, currentHp, 0, 10 ^ 9) + 0.5))
	return (`{currentHp}/{maxHp} HP`)
end

local function applyNpcDamage(runtime: NpcRuntime, player: Player, amountRaw: number?): (number, string, string)
	local requestedDamage = if amountRaw ~= nil then amountRaw else KILL_DAMAGE
	local appliedDamage = NpcServiceServer:applyRuntimeDamage(runtime, requestedDamage, player, "DebugCommand")
	local currentHp = runtime.hp
	local maxHp = runtime.maxHp

	if runtime.slime ~= nil then
		currentHp = runtime.slime.hp
		maxHp = runtime.slime.maxHp
	end

	return appliedDamage, runtime.displayName, formatHealth(currentHp, maxHp)
end

local function applyBossDamage(boss: BossObject, player: Player, amountRaw: number?): (number, string, string)
	local requestedDamage = if amountRaw ~= nil then amountRaw else KILL_DAMAGE
	local appliedDamage = boss:takeDamage(requestedDamage, player, "DebugCommand")
	if appliedDamage > 0 then
		BossServiceServer:syncControllerSnapshot(boss, true)
	end

	return appliedDamage, boss.displayName, formatHealth(boss.hp, boss.maxHp)
end

return function(_context, entity: EntityEntry, players: { Player }, amountRaw: number?)
	local responseParts = {}
	local seenIds = {}

	for _, player in players do
		local rootPart = resolvePlayerRootPart(player)
		if rootPart == nil then
			responseParts[#responseParts + 1] = (`Could not target anything for {player.Name} because their character was unavailable.`)
			continue
		end

		if entity.Kind == "Npc" then
			local runtime = findNearestNpcRuntime(entity, player, seenIds)
			if runtime == nil then
				responseParts[#responseParts + 1] = (`Could not find {entity.Name} near {player.Name}.`)
				continue
			end

			seenIds[runtime.id] = true

			local appliedDamage, displayName, healthText = applyNpcDamage(runtime, player, amountRaw)
			if appliedDamage > 0 then
				if runtime.hp <= 0 then
					responseParts[#responseParts + 1] = (`Killed {displayName} near {player.Name} ({healthText}).`)
				else
					responseParts[#responseParts + 1] =
						(`Damaged {displayName} near {player.Name} for {math.floor(appliedDamage + 0.5)} ({healthText}).`)
				end
			else
				responseParts[#responseParts + 1] = (`Could not damage {displayName} near {player.Name}.`)
			end
		elseif entity.Kind == "Boss" then
			local boss = findNearestBoss(entity, player, seenIds)
			if boss == nil then
				responseParts[#responseParts + 1] = (`Could not find {entity.Name} near {player.Name}.`)
				continue
			end

			seenIds[boss.id] = true

			local appliedDamage, displayName, healthText = applyBossDamage(boss, player, amountRaw)
			if appliedDamage > 0 then
				if boss.hp <= 0 then
					responseParts[#responseParts + 1] = (`Killed {displayName} near {player.Name} ({healthText}).`)
				else
					responseParts[#responseParts + 1] =
						(`Damaged {displayName} near {player.Name} for {math.floor(appliedDamage + 0.5)} ({healthText}).`)
				end
			else
				responseParts[#responseParts + 1] = (`Could not damage {displayName} near {player.Name}.`)
			end
		else
			responseParts[#responseParts + 1] = (`Unsupported entity kind "{entity.Kind}".`)
		end
	end

	if #responseParts <= 0 then
		return "No entities were affected."
	end

	return table.concat(responseParts, " ")
end
