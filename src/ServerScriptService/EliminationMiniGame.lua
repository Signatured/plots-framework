--!strict

local MiniGame = require(game.ServerScriptService.MiniGame.MiniGame)
export type MiniGameType = MiniGame.Type

type Functions<self> = {
	Eliminate: (self, player: Player) -> (),
}
export type Type = MiniGameType & Functions<Type>

local prototype = {}::Functions<Type>

function prototype:Eliminate(player: Player)
	print("eliminated player")
end

local Metatable = table.freeze({
	__index = function(tbl, key)
		return prototype[key] or MiniGame.Prototype[key]
	end
})

local module = {}

function module.new(minigameType: string): Type
	local base = MiniGame.new(minigameType)
	local self: Type = setmetatable(base :: any, Metatable)
	return self
end

return module