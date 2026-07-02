
local require = require(script.Parent.loader).load(script)

local Target = require("Target")

local EnemySubject = {}

export type EnemySubjectOptions = {
	target: any?,
	runtimeId: string?,
	model: Model?,
	basePart: BasePart?,
	position: Vector3?,
	velocity: Vector3?,
}

function EnemySubject.Get(optionsRaw: EnemySubjectOptions?): Target.GotTarget?
	local targetGetter = Target.New({
		target = optionsRaw,
	})
	return targetGetter:GetAny(optionsRaw, "Enemy")
end

function EnemySubject.New(optionsRaw: EnemySubjectOptions?): EnemySubjectOptions
	return optionsRaw or ({} :: any)
end

return EnemySubject
