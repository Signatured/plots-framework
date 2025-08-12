--!strict

type Fields<self> = {
	MineGameType: string,
	Participants: {[Player]: boolean},
	Spectators: {[Player]: boolean},
}

type Functions<self> = {
	Fire: (self, Player, ...any) -> (),
    FireAll: (self, ...any) -> (),
}
export type Type = Fields<Type> & Functions<Type>

local prototype = {}::Functions<Type>

function prototype:Fire(player: Player, ...)
	
end

function prototype:FireAll(...)
	
end

local Metatable = table.freeze({ __index = table.freeze(prototype) })

local module = {}

function module.new(minigameType: string): Type
	-- Instance
	local self: Fields<Type> = {
		MineGameType = minigameType,
		Participants = {},
		Spectators = {}
	}
	
	local self: Type = setmetatable(self::any, Metatable)
	
	return self
end

module.Prototype = prototype

return module