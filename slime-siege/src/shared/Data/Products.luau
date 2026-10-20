--!strict
-- Monetization catalog. IDs are 0 until real game passes / dev products are created;
-- while an ID is 0, purchases are granted in Studio and refused ("coming soon") live.
-- Rule: never sell gameplay power beyond what's listed here (co-op fairness).

export type Product = {
	key: string,
	kind: "gamepass" | "devproduct",
	id: number,
	displayName: string,
	description: string,
	goo: number?, -- dev products: Goo granted per purchase
}

local Products: { [string]: Product } = {
	DoubleGoo = {
		key = "DoubleGoo",
		kind = "gamepass",
		id = 0,
		displayName = "2x Goo",
		description = "Earn double Goo from every match.",
	},
	ExtraCash = {
		key = "ExtraCash",
		kind = "gamepass",
		id = 0,
		displayName = "Extra Starting Cash",
		description = "Start every match with +$150.",
	},
	VipSkins = {
		key = "VipSkins",
		kind = "gamepass",
		id = 0,
		displayName = "VIP Tower Skins",
		description = "Golden skins for all of your towers.",
	},
	GooSmall = {
		key = "GooSmall",
		kind = "devproduct",
		id = 0,
		displayName = "Bucket of Goo",
		description = "+250 Goo",
		goo = 250,
	},
	GooLarge = {
		key = "GooLarge",
		kind = "devproduct",
		id = 0,
		displayName = "Barrel of Goo",
		description = "+1000 Goo",
		goo = 1000,
	},
}

return Products
