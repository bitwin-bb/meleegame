local require = require(script.Parent.loader).load(script)
local Packets = table.clone(require("NetSharedPackets")) :: any

function Packets.Init(): ()
	return
end

Packets.init = Packets.Init

return Packets
