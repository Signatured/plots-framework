--!strict

local DirectoryTypes = require(game.ReplicatedStorage.Game.GameLibrary.Types.Directory)

local module = {}

export type raw_dir = {
	GamepassId: number,
	DisplayName: string,
	Icon: string,
	Description: string,
	Callback: ((player: Player) -> ())?,
}

export type dir_schema = raw_dir & DirectoryTypes.dir_schema

return module
