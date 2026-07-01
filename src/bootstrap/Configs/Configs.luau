--!strict

export type BootstrapConfig = {
	loadingScreenEnabled: boolean,
	startClientServices: boolean,
	startServerServices: boolean,
	runServerTests: boolean,
}

local Configs = {}

Configs.defaults = {
	loadingScreenEnabled = true,
	startClientServices = true,
	startServerServices = true,
	runServerTests = false,
} :: BootstrapConfig

function Configs.GetDefaults(): BootstrapConfig
	return table.clone(Configs.defaults)
end

return Configs
