local require = require(script.Parent.loader).load(script)
local Packets = table.clone(require("NetPacketsShared")) :: any

function Packets.Init(): ()
	return
end
return Packets
