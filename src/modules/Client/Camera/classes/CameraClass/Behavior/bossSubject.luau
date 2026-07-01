
local require = require(script.Parent.loader).load(script)

local Target = require("Target")

local BossSubject = {}

export type BossSubjectOptions = {
	runtimeId: string?,
	bossId: string?,
	encounterChannel: string?,
	target: any?,
}

function BossSubject.Get(optionsRaw: BossSubjectOptions?): Target.GotTarget?
	local targetGetter = Target.New({
		target = optionsRaw,
	})
	return targetGetter:GetAny(optionsRaw, "Boss")
end

function BossSubject.New(optionsRaw: BossSubjectOptions?): BossSubjectOptions
	return optionsRaw or ({} :: any)
end

return BossSubject
