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
	priceRobux: number, -- display only until real ids exist (Roblox shows the real price)
	order: number, -- shop list order
	badge: string?, -- small tag on the shop row ("PASS", "+28%")
}

local Products: { [string]: Product } = {
	DoubleGoo = {
		key = "DoubleGoo",
		kind = "gamepass",
		id = 0,
		displayName = "2x Goo",
		description = "Earn double Goo from every match.",
		priceRobux = 199,
		order = 3,
		badge = "PASS",
	},
	ExtraCash = {
		key = "ExtraCash",
		kind = "gamepass",
		id = 0,
		displayName = "Extra Starting Cash",
		description = "Start every match with +$150.",
		priceRobux = 99,
		order = 4,
		badge = "PASS",
	},
	VipSkins = {
		key = "VipSkins",
		kind = "gamepass",
		id = 0,
		displayName = "VIP Tower Skins",
		description = "Golden skins for all of your towers.",
		priceRobux = 299,
		order = 5,
		badge = "PASS",
	},
	FastForward = {
		key = "FastForward",
		kind = "gamepass",
		id = 0,
		displayName = "2x Speed",
		description = "Fast-forward matches to 2x speed (pass owners vote on it).",
		priceRobux = 149,
		order = 6,
		badge = "PASS",
	},
	GooSmall = {
		key = "GooSmall",
		kind = "devproduct",
		id = 0,
		displayName = "Bucket of Goo",
		description = "+250 Goo",
		goo = 250,
		priceRobux = 49,
		order = 1,
	},
	GooLarge = {
		key = "GooLarge",
		kind = "devproduct",
		id = 0,
		displayName = "Barrel of Goo",
		description = "+1000 Goo",
		goo = 1000,
		priceRobux = 149,
		order = 2,
		badge = "+28%",
	},
}

return Products
