
-- Deterministic waveform and ping-pong helpers.

local require = require(script.Parent.loader).load(script)

local Num = require("Num")
local Range = require("Range")
local Trig = require("Trig")

local Osc = {}

function Osc.Phase01(time: number, frequency: number, phaseRadians: number?): number
	local cycles = time * frequency + (phaseRadians or 0) / Trig.TAU
	return Range.Wrap(cycles, 0, 1)
end

function Osc.Sine(time: number, amplitude: number?, frequency: number?, phaseRadians: number?, offset: number?): number
	local amp = amplitude or 1
	local hz = frequency or 1
	local phase = phaseRadians or 0
	local bias = offset or 0
	return bias + amp * math.sin(Trig.TAU * hz * time + phase)
end

function Osc.Cosine(
	time: number,
	amplitude: number?,
	frequency: number?,
	phaseRadians: number?,
	offset: number?
): number
	local amp = amplitude or 1
	local hz = frequency or 1
	local phase = phaseRadians or 0
	local bias = offset or 0
	return bias + amp * math.cos(Trig.TAU * hz * time + phase)
end

function Osc.Triangle(
	time: number,
	amplitude: number?,
	frequency: number?,
	phaseRadians: number?,
	offset: number?
): number
	local amp = amplitude or 1
	local hz = frequency or 1
	local bias = offset or 0
	local phase = Osc.Phase01(time, hz, phaseRadians)
	local wave = 1 - 4 * math.abs(phase - 0.5)
	return bias + amp * wave
end

function Osc.Saw(time: number, amplitude: number?, frequency: number?, phaseRadians: number?, offset: number?): number
	local amp = amplitude or 1
	local hz = frequency or 1
	local bias = offset or 0
	local phase = Osc.Phase01(time, hz, phaseRadians)
	return bias + amp * (phase * 2 - 1)
end

function Osc.Square(
	time: number,
	amplitude: number?,
	frequency: number?,
	phaseRadians: number?,
	dutyCycle: number?,
	offset: number?
): number
	local amp = amplitude or 1
	local hz = frequency or 1
	local bias = offset or 0
	local duty = Num.Clamp(dutyCycle or 0.5, 0, 1)
	local phase = Osc.Phase01(time, hz, phaseRadians)
	local wave = if phase < duty then 1 else -1
	return bias + amp * wave
end

function Osc.PingPong(time: number, length: number): number
	local extent = math.max(length, 0)
	if extent == 0 then
		return 0
	end

	local wrapped = Range.Wrap(time, 0, extent * 2)
	return extent - math.abs(wrapped - extent)
end
return Osc
