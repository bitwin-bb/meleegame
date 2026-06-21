
local require = require(script.Parent.loader).load(script)

local Target = require("Target")

local CutsceneSubject = {}

export type CutsceneSubjectOptions = {
	target: any?,
	position: Vector3?,
	lookPosition: Vector3?,
	durationSeconds: number?,
	expiresAt: number?,
}

function CutsceneSubject.Resolve(optionsRaw: CutsceneSubjectOptions?): Target.ResolvedTarget?
	local resolver = Target.new({
		target = optionsRaw,
	})
	return resolver:resolveAny(optionsRaw, "Cutscene")
end

function CutsceneSubject.New(optionsRaw: CutsceneSubjectOptions?): CutsceneSubjectOptions
	return optionsRaw or ({} :: any)
end

CutsceneSubject.resolve = CutsceneSubject.Resolve
CutsceneSubject.new = CutsceneSubject.New

return CutsceneSubject
