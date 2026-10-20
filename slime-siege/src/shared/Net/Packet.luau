--!strict
-- Compact binary encoding for the 10 Hz enemy snapshot (positions + render events).
-- One buffer per snapshot keeps remote traffic small with 300+ slimes on screen.

local SlimeData = require(script.Parent.Parent.Data.SlimeData)

local Packet = {}

-- Event record types
Packet.SPAWN = 1 -- u32 id, u8 kind, u8 camo, u16 distance
Packet.POP = 2 -- u32 id, u16 towerUid
Packet.LEAK = 3 -- u32 id
Packet.ATTACK = 4 -- u16 towerUid, u8 visual, i16 x, i16 z
Packet.CHAIN = 5 -- i16 x1, i16 z1, i16 x2, i16 z2
Packet.CLEAR = 6

local DIST_SCALE = 16 -- 1/16 stud precision, up to 4096 studs of path
local POS_SCALE = 8 -- 1/8 stud precision, +-4096 studs

Packet.KINDS = { "Green", "Blue", "Yellow", "Pink", "Black", "Metal", "Rainbow", "Boss" }
Packet.KIND_INDEX = {} :: { [string]: number }
for i, kind in Packet.KINDS do
	assert(SlimeData[kind], `Packet kind {kind} missing from SlimeData`)
	Packet.KIND_INDEX[kind] = i
end

Packet.VISUALS = {
	"dart",
	"bomb",
	"frost",
	"blades",
	"hotblades",
	"orb",
	"firebolt",
	"firewall",
	"phoenix",
	"cluster",
}
Packet.VISUAL_INDEX = {} :: { [string]: number }
for i, v in Packet.VISUALS do
	Packet.VISUAL_INDEX[v] = i
end

export type Writer = { buf: buffer, cursor: number }

function Packet.writer(initialSize: number?): Writer
	return { buf = buffer.create(initialSize or 256), cursor = 0 }
end

local function ensure(w: Writer, bytes: number)
	local size = buffer.len(w.buf)
	if w.cursor + bytes > size then
		local newSize = size * 2
		while w.cursor + bytes > newSize do
			newSize *= 2
		end
		local grown = buffer.create(newSize)
		buffer.copy(grown, 0, w.buf, 0, w.cursor)
		w.buf = grown
	end
end

local function u8(w: Writer, v: number)
	ensure(w, 1)
	buffer.writeu8(w.buf, w.cursor, v)
	w.cursor += 1
end

local function u16(w: Writer, v: number)
	ensure(w, 2)
	buffer.writeu16(w.buf, w.cursor, math.clamp(math.floor(v), 0, 65535))
	w.cursor += 2
end

local function i16(w: Writer, v: number)
	ensure(w, 2)
	buffer.writei16(w.buf, w.cursor, math.clamp(math.floor(v + 0.5), -32768, 32767))
	w.cursor += 2
end

local function u32(w: Writer, v: number)
	ensure(w, 4)
	buffer.writeu32(w.buf, w.cursor, v)
	w.cursor += 4
end

function Packet.finish(w: Writer): buffer
	local out = buffer.create(w.cursor)
	buffer.copy(out, 0, w.buf, 0, w.cursor)
	return out
end

-- Layout: u16 eventCount, events..., u16 enemyCount, (u32 id, u16 distance, u8 flags)...
-- flags: bit0 frozen/stunned, bit1 slowed
export type EnemyView = { id: number, distance: number, frozen: number, stunned: number, slow: number }

function Packet.encodeSnapshot(events: { { [string]: any } }, enemies: { EnemyView }): buffer
	local w = Packet.writer(64 + #enemies * 7 + #events * 8)
	local countAt = w.cursor
	u16(w, 0)
	local count = 0
	for _, e in events do
		local t = e.t
		if t == "spawn" then
			u8(w, Packet.SPAWN)
			u32(w, e.id)
			u8(w, Packet.KIND_INDEX[e.slime] or 1)
			u8(w, if e.camo then 1 else 0)
			u16(w, e.distance * DIST_SCALE)
		elseif t == "pop" then
			u8(w, Packet.POP)
			u32(w, e.id)
			u16(w, e.tower)
		elseif t == "leak" then
			u8(w, Packet.LEAK)
			u32(w, e.id)
		elseif t == "attack" then
			u8(w, Packet.ATTACK)
			u16(w, e.tower)
			u8(w, Packet.VISUAL_INDEX[e.visual] or 1)
			i16(w, e.x * POS_SCALE)
			i16(w, e.z * POS_SCALE)
		elseif t == "chain" then
			u8(w, Packet.CHAIN)
			i16(w, e.x1 * POS_SCALE)
			i16(w, e.z1 * POS_SCALE)
			i16(w, e.x2 * POS_SCALE)
			i16(w, e.z2 * POS_SCALE)
		elseif t == "clear" then
			u8(w, Packet.CLEAR)
		else
			continue
		end
		count += 1
		if count >= 65535 then
			break
		end
	end
	buffer.writeu16(w.buf, countAt, count)

	u16(w, #enemies)
	for _, enemy in enemies do
		u32(w, enemy.id)
		u16(w, enemy.distance * DIST_SCALE)
		local flags = 0
		if enemy.frozen > 0 or enemy.stunned > 0 then
			flags += 1
		end
		if enemy.slow < 1 then
			flags += 2
		end
		u8(w, flags)
	end
	return Packet.finish(w)
end

export type DecodedEvent = {
	t: number,
	id: number,
	kind: string?,
	camo: boolean?,
	distance: number?,
	tower: number?,
	visual: string?,
	x: number?,
	z: number?,
	x2: number?,
	z2: number?,
}

export type DecodedEnemy = { id: number, distance: number, flags: number }

-- Decodes into caller-owned arrays to avoid per-snapshot allocations of the outer tables.
function Packet.decodeSnapshot(buf: buffer, events: { DecodedEvent }, enemies: { DecodedEnemy })
	table.clear(events)
	table.clear(enemies)
	local len = buffer.len(buf)
	if len < 4 then
		return
	end
	local c = 0
	local eventCount = buffer.readu16(buf, c)
	c += 2
	for _ = 1, eventCount do
		local t = buffer.readu8(buf, c)
		c += 1
		if t == Packet.SPAWN then
			table.insert(events, {
				t = t,
				id = buffer.readu32(buf, c),
				kind = Packet.KINDS[buffer.readu8(buf, c + 4)],
				camo = buffer.readu8(buf, c + 5) == 1,
				distance = buffer.readu16(buf, c + 6) / DIST_SCALE,
			})
			c += 8
		elseif t == Packet.POP then
			table.insert(events, { t = t, id = buffer.readu32(buf, c), tower = buffer.readu16(buf, c + 4) })
			c += 6
		elseif t == Packet.LEAK then
			table.insert(events, { t = t, id = buffer.readu32(buf, c) })
			c += 4
		elseif t == Packet.ATTACK then
			table.insert(events, {
				t = t,
				id = 0,
				tower = buffer.readu16(buf, c),
				visual = Packet.VISUALS[buffer.readu8(buf, c + 2)],
				x = buffer.readi16(buf, c + 3) / POS_SCALE,
				z = buffer.readi16(buf, c + 5) / POS_SCALE,
			})
			c += 7
		elseif t == Packet.CHAIN then
			table.insert(events, {
				t = t,
				id = 0,
				x = buffer.readi16(buf, c) / POS_SCALE,
				z = buffer.readi16(buf, c + 2) / POS_SCALE,
				x2 = buffer.readi16(buf, c + 4) / POS_SCALE,
				z2 = buffer.readi16(buf, c + 6) / POS_SCALE,
			})
			c += 8
		elseif t == Packet.CLEAR then
			table.insert(events, { t = t, id = 0 })
		else
			return -- corrupt packet; drop the rest
		end
	end
	local enemyCount = buffer.readu16(buf, c)
	c += 2
	for _ = 1, enemyCount do
		if c + 7 > len then
			return
		end
		table.insert(enemies, {
			id = buffer.readu32(buf, c),
			distance = buffer.readu16(buf, c + 4) / DIST_SCALE,
			flags = buffer.readu8(buf, c + 6),
		})
		c += 7
	end
end

return Packet
