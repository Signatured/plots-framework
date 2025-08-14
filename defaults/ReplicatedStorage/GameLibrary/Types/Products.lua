--!strict

local DirectoryTypes = require(game.ReplicatedStorage.Game.Library.Types.Directory)

local module = {}

export type raw_dir = {
	ProductId: number,
	DisplayName: string,
	Icon: string,
	Description: string,
	OneTimePurchase: boolean,
	Callback: ((player: Player) -> ())?,
	ServerTest: ((player: Player) -> (boolean, string?))?,
	ClientTest: ((player: Player) -> (boolean, string?))?,
}

export type dir_schema = raw_dir & DirectoryTypes.dir_schema

return module 