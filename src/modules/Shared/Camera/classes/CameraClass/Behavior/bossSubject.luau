
local require = require(script.Parent.loader).load(script)

local Target = require("Target")

local BossSubject = {}

export type BossSubjectOptions = {
	runtimeId: string?,
	bossId: string?,
	encounterChannel: string?,
	target: any?,
}

function BossSubject.Resolve(optionsRaw: BossSubjectOptions?): Target.ResolvedTarget?
	local resolver = Target.new({
		target = optionsRaw,
	})
	return resolver:resolveAny(optionsRaw, "Boss")
end

function BossSubject.New(optionsRaw: BossSubjectOptions?): BossSubjectOptions
	return optionsRaw or ({} :: any)
end

BossSubject.resolve = BossSubject.Resolve
BossSubject.new = BossSubject.New

return BossSubject
