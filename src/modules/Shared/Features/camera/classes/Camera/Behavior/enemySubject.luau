--!strict

local Target = require(script.Parent.Parent.Target)

local EnemySubject = {}

export type EnemySubjectOptions = {
	target: any?,
	runtimeId: string?,
	model: Model?,
	basePart: BasePart?,
	position: Vector3?,
	velocity: Vector3?,
}

function EnemySubject.Resolve(optionsRaw: EnemySubjectOptions?): Target.ResolvedTarget?
	local resolver = Target.new({
		target = optionsRaw,
	})
	return resolver:resolveAny(optionsRaw, "Enemy")
end

function EnemySubject.New(optionsRaw: EnemySubjectOptions?): EnemySubjectOptions
	return optionsRaw or ({} :: any)
end

EnemySubject.resolve = EnemySubject.Resolve
EnemySubject.new = EnemySubject.New

return EnemySubject
