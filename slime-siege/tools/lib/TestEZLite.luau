--!strict
-- Minimal TestEZ-compatible runner for headless CI in Lune. Specs are written against the real
-- TestEZ API (describe / it / expect / beforeEach / afterEach), so the same files also run in
-- Studio with roblox/testez (see src/server/TestRunner.server.luau).

local TestEZLite = {}

type Node = {
	name: string,
	children: { Node },
	tests: { { name: string, fn: () -> () } },
	beforeEach: { () -> () },
	afterEach: { () -> () },
}

local function newNode(name: string): Node
	return { name = name, children = {}, tests = {}, beforeEach = {}, afterEach = {} }
end

local function fmt(v: any): string
	if type(v) == "string" then
		return string.format("%q", v)
	end
	return tostring(v)
end

-- TestEZ calls matchers with a dot (`expect(x).to.equal(y)`), so matchers are closures.
local CHAIN_WORDS = { to = true, be = true, been = true, have = true, was = true, at = true }

local function newExpectation(value: any, negated: boolean): any
	local self: { [string]: any } = {}

	local function check(ok: boolean, message: string)
		if negated then
			ok = not ok
			message = "NOT: " .. message
		end
		if not ok then
			error(message, 3)
		end
	end

	self.equal = function(expected: any)
		check(value == expected, `Expected {fmt(expected)}, got {fmt(value)}`)
		return self
	end
	self.ok = function()
		check(value ~= nil and value ~= false, `Expected value to be ok, got {fmt(value)}`)
		return self
	end
	self.near = function(expected: number, epsilon: number?)
		local eps = epsilon or 1e-7
		check(
			type(value) == "number" and math.abs(value - expected) <= eps,
			`Expected {fmt(value)} to be near {expected} (±{eps})`
		)
		return self
	end
	self.a = function(typeName: string)
		check(typeof(value) == typeName, `Expected type {typeName}, got {typeof(value)}`)
		return self
	end
	self.an = self.a
	self.throw = function(substring: string?)
		local ok, err = pcall(value)
		local matched = not ok and (substring == nil or string.find(tostring(err), substring, 1, true) ~= nil)
		check(matched, `Expected function to throw{if substring then " " .. substring else ""}`)
		return self
	end

	return setmetatable(self, {
		__index = function(_, key: string): any
			if CHAIN_WORDS[key] then
				return self
			elseif key == "never" then
				return newExpectation(value, not negated)
			end
			error(`unknown expectation {key}`, 2)
		end,
	})
end

local function makeExpect()
	return function(value: any)
		return newExpectation(value, false)
	end
end

export type Result = { passed: number, failed: number, failures: { string } }

local root = newNode("root")
local stack = { root }
local function current(): Node
	return stack[#stack]
end

-- Installs describe/it/expect/... into the table used as the specs' global environment.
function TestEZLite.install(globalsTarget: { [string]: any })
	globalsTarget.describe = function(name: string, fn: () -> ())
		local node = newNode(name)
		table.insert(current().children, node)
		table.insert(stack, node)
		fn()
		table.remove(stack)
	end
	globalsTarget.it = function(name: string, fn: () -> ())
		table.insert(current().tests, { name = name, fn = fn })
	end
	globalsTarget.itSKIP = function() end
	globalsTarget.describeSKIP = function() end
	globalsTarget.beforeEach = function(fn: () -> ())
		table.insert(current().beforeEach, fn)
	end
	globalsTarget.afterEach = function(fn: () -> ())
		table.insert(current().afterEach, fn)
	end
	globalsTarget.expect = makeExpect()
end

-- Each spec module returns a function (TestEZ convention); `specs` pairs it with a name.
function TestEZLite.run(specs: { { name: string, fn: () -> () } }): Result
	for _, spec in specs do
		local node = newNode(spec.name)
		table.insert(root.children, node)
		table.insert(stack, node)
		spec.fn()
		table.remove(stack)
	end

	local result: Result = { passed = 0, failed = 0, failures = {} }
	local function runNode(node: Node, path: string, befores: { () -> () }, afters: { () -> () }, depth: number)
		local myBefores = table.clone(befores)
		for _, f in node.beforeEach do
			table.insert(myBefores, f)
		end
		local myAfters = table.clone(node.afterEach)
		for _, f in afters do
			table.insert(myAfters, f)
		end
		print(string.rep("  ", depth) .. node.name)
		for _, test in node.tests do
			local ok, err = pcall(function()
				for _, f in myBefores do
					f()
				end
				test.fn()
				for _, f in myAfters do
					f()
				end
			end)
			if ok then
				result.passed += 1
				print(string.rep("  ", depth + 1) .. "[+] " .. test.name)
			else
				result.failed += 1
				local line = `{path} > {test.name}: {err}`
				table.insert(result.failures, line)
				print(
					string.rep("  ", depth + 1)
						.. "[-] "
						.. test.name
						.. "\n"
						.. string.rep("  ", depth + 3)
						.. tostring(err)
				)
			end
		end
		for _, child in node.children do
			runNode(child, path .. " > " .. child.name, myBefores, myAfters, depth + 1)
		end
	end
	for _, child in root.children do
		runNode(child, child.name, {}, {}, 0)
	end
	return result
end

return TestEZLite
