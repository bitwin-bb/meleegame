--!strict
local GoreServiceUtils = {}

GoreServiceUtils.NETWORK_METHOD_REQUEST_SYNC = "requestSync"
GoreServiceUtils.NETWORK_METHOD_REGISTER_ENTITY = "registerEntity"
GoreServiceUtils.NETWORK_METHOD_REMOVE_ENTITY = "removeEntity"
GoreServiceUtils.NETWORK_METHOD_SET_BLOOD_COLOR = "setBloodColor"
GoreServiceUtils.NETWORK_METHOD_DESTROY_LIMB = "destroyLimb"
GoreServiceUtils.NETWORK_METHOD_EMIT_BLOOD = "emitBlood"
GoreServiceUtils.NETWORK_METHOD_SPAWN_GIBS = "spawnGibs"
GoreServiceUtils.NETWORK_METHOD_EMIT_SLIME_BLOOD = "emitSlimeBlood"

GoreServiceUtils.DEFAULT_PLAYER_BLOOD_COLOR = Color3.fromRGB(105, 0, 0)
GoreServiceUtils.DEFAULT_NPC_BLOOD_COLOR = Color3.fromRGB(39, 145, 58)
GoreServiceUtils.DEFAULT_PLAYER_DAMAGE_BLOOD_AMOUNT = 6
GoreServiceUtils.DEFAULT_PLAYER_DEATH_BLOOD_AMOUNT = 44
GoreServiceUtils.DEFAULT_NPC_DAMAGE_BLOOD_AMOUNT = 8
GoreServiceUtils.DEFAULT_NPC_DEATH_BLOOD_AMOUNT = 52
GoreServiceUtils.DEFAULT_NPC_DEATH_GIB_COUNT = 4
GoreServiceUtils.MAX_BLOOD_AMOUNT = 200
GoreServiceUtils.MAX_GIB_COUNT = 20
GoreServiceUtils.MAX_EFFECT_DURATION_SECONDS = 10

local function trim(valueRaw: any): string
	if typeof(valueRaw) ~= "string" then
		return ""
	end
	return string.match(valueRaw, "^%s*(.-)%s*$") or ""
end

local function sanitizeNumber(valueRaw: any, fallback: number, minimum: number?, maximum: number?): number
	local value = fallback
	if typeof(valueRaw) == "number" and valueRaw == valueRaw then
		value = valueRaw
	elseif typeof(valueRaw) == "string" then
		local parsed = tonumber(trim(valueRaw))
		if parsed ~= nil and parsed == parsed then
			value = parsed
		end
	end

	if minimum ~= nil and value < minimum then
		value = minimum
	end
	if maximum ~= nil and value > maximum then
		value = maximum
	end
	return value
end

function GoreServiceUtils.SanitizeEntityId(valueRaw: any): string?
	local value = trim(valueRaw)
	if value == "" then
		return nil
	end
	return value
end

function GoreServiceUtils.SanitizeBoolean(valueRaw: any, fallback: boolean): boolean
	if typeof(valueRaw) == "boolean" then
		return valueRaw
	end
	return fallback
end

function GoreServiceUtils.SanitizeBloodAmount(valueRaw: any, fallback: number): number
	return math.floor(sanitizeNumber(valueRaw, fallback, 1, GoreServiceUtils.MAX_BLOOD_AMOUNT) + 0.5)
end

function GoreServiceUtils.SanitizeGibCount(valueRaw: any, fallback: number): number
	return math.floor(sanitizeNumber(valueRaw, fallback, 0, GoreServiceUtils.MAX_GIB_COUNT) + 0.5)
end

function GoreServiceUtils.SanitizeEffectDuration(valueRaw: any, fallback: number): number
	return sanitizeNumber(valueRaw, fallback, 0.05, GoreServiceUtils.MAX_EFFECT_DURATION_SECONDS)
end

function GoreServiceUtils.SanitizeColor(valueRaw: any, fallback: Color3): Color3
	if typeof(valueRaw) == "Color3" then
		return valueRaw
	end
	return fallback
end

function GoreServiceUtils.MakePlayerEntityId(playerRaw: any): string?
	if typeof(playerRaw) ~= "Instance" or not playerRaw:IsA("Player") then
		return nil
	end
	if playerRaw.UserId <= 0 then
		return nil
	end
	return ("player:%d"):format(playerRaw.UserId)
end

function GoreServiceUtils.MakeNpcEntityId(runtimeIdRaw: any): string?
	local runtimeId = GoreServiceUtils.SanitizeEntityId(runtimeIdRaw)
	if runtimeId == nil then
		return nil
	end
	return "npc:" .. runtimeId
end

function GoreServiceUtils.ResolveModelRootPart(modelRaw: any): BasePart?
	if typeof(modelRaw) ~= "Instance" or not modelRaw:IsA("Model") then
		return nil
	end

	local root = modelRaw:FindFirstChild("HumanoidRootPart")
	if root ~= nil and root:IsA("BasePart") then
		return root
	end

	if modelRaw.PrimaryPart ~= nil then
		return modelRaw.PrimaryPart
	end

	for _, descendant in modelRaw:GetDescendants() do
		if descendant:IsA("BasePart") then
			return descendant
		end
	end

	return nil
end

function GoreServiceUtils.ResolveOriginPart(modelRaw: any, originRaw: any): BasePart?
	if typeof(originRaw) == "Instance" and originRaw:IsA("BasePart") then
		if typeof(modelRaw) == "Instance" and modelRaw:IsA("Model") then
			if originRaw:IsDescendantOf(modelRaw) then
				return originRaw
			end
		else
			return originRaw
		end
	end

	return GoreServiceUtils.ResolveModelRootPart(modelRaw)
end

function GoreServiceUtils.ResolveBloodOrigin(modelRaw: any, originRaw: any): (Vector3 | BasePart)?
	if typeof(originRaw) == "Vector3" then
		return originRaw
	end

	local originPart = GoreServiceUtils.ResolveOriginPart(modelRaw, originRaw)
	if originPart ~= nil then
		return originPart
	end

	return nil
end

function GoreServiceUtils.CloneDictionary(sourceRaw: any): { [string]: any }
	if typeof(sourceRaw) ~= "table" then
		return {}
	end

	local out = {}
	for key, value in sourceRaw do
		if typeof(key) == "string" then
			out[key] = value
		end
	end
	return out
end

GoreServiceUtils.sanitizeEntityId = GoreServiceUtils.SanitizeEntityId
GoreServiceUtils.sanitizeBoolean = GoreServiceUtils.SanitizeBoolean
GoreServiceUtils.sanitizeBloodAmount = GoreServiceUtils.SanitizeBloodAmount
GoreServiceUtils.sanitizeGibCount = GoreServiceUtils.SanitizeGibCount
GoreServiceUtils.sanitizeEffectDuration = GoreServiceUtils.SanitizeEffectDuration
GoreServiceUtils.sanitizeColor = GoreServiceUtils.SanitizeColor
GoreServiceUtils.makePlayerEntityId = GoreServiceUtils.MakePlayerEntityId
GoreServiceUtils.makeNpcEntityId = GoreServiceUtils.MakeNpcEntityId
GoreServiceUtils.resolveModelRootPart = GoreServiceUtils.ResolveModelRootPart
GoreServiceUtils.resolveOriginPart = GoreServiceUtils.ResolveOriginPart
GoreServiceUtils.resolveBloodOrigin = GoreServiceUtils.ResolveBloodOrigin
GoreServiceUtils.cloneDictionary = GoreServiceUtils.CloneDictionary

return GoreServiceUtils
