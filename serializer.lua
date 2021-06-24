local Players = game:GetService("Players")
local settings = {
    indentSpaces = 4,
    maxTableSize = 1000,
    maxStringSize = 10000,
    useTaskScheduler = false,
    scheduleFunc = function(f) coroutine.wrap(f)() end,
    handleUserdataKeysAsStrings = true,
    useSafeToString = true,
}
local variablePattern = "^[%a_]+[%w_]*$"
local getNilString = "function getnil(name, class) for _, v in pairs(getnilinstances()) do if v.Name == name and v.ClassName == class then return v end end end"
local types = {}

--- Gets the type of `x`, returns tuple with true as second index if userdata subclass
function getTypeOf(x)
    if typeof then
        return typeof(x), (typeof(x) ~= type(x) and true or false)
    else
        return type(x), false
    end
end

--- Asserts the type of `x` matches at least one of the elements in `...`
function assertTypeOf(x, ...)
    local tuple = {...}
    local valid = false
    local xType = getTypeOf(x)
    for _, type in pairs(tuple) do
        if getTypeOf(type) == "string" and xType == type then
            valid = true
            break
        end
    end
    assert(valid, string.format("%s expected, got %s", #tuple > 1 and table.concat(tuple, " | ") or tuple[1], getTypeOf(x)))
end

--- Converts any value to a variable
--- @param value any
--- @param name string
function valueToVar(value, name)
    assertTypeOf(name, "string", "nil")
    local metadata = { top = {}, bottom = {} }
    local serialized = typeToString(value, metadata)
    if name and string.match(name, variablePattern) then
        return string.format("%s\nlocal %s = %s\n%s", table.concat(metadata.top, "\n"), name, serialized, table.concat(metadata.bottom, "\n"))
    else
        return string.format("%s\nlocal var = %s\n%s", table.concat(metadata.top, "\n"), serialized, table.concat(metadata.bottom, "\n"))
    end
end

--- Wrapper for `types`
function typeToString(value, metadata)
    local type, userdataSubclass = getTypeOf(value)
    local out = types[type]
    return out and out(value, metadata) or string.format("nil --[[UnhandledType: %s, UserdataSubclass: %s]]", type, types.boolean(userdataSubclass))
end

--- Multi-purpose function for parsing lua indices (object.index/object["index"])
function parseIndex(index)
    assertTypeOf(index, "string")
    if string.match(index, variablePattern) then
        return string.format(".%s", index)
    else
        return string.format("[%s]", types.string(index))
    end
end

-- TYPE HANDLING --

-- Primitive/Immutable

function types.string(value, metadata)
    local buildStr = {}
    local i = 1
    local char = string.sub(value, i, i)
    local indentStr
    while char ~= "" do
        if char == '"' then
            buildStr[i] = '\\"'
        elseif char == "\\" then
            buildStr[i] = "\\\\"
        elseif char == "\n" then
            buildStr[i] = "\\n"
        elseif char == "\t" then
            buildStr[i] = "\\t"
        elseif string.byte(char) > 126 or string.byte(char) < 32 then
            buildStr[i] = string.format("\\%d", string.byte(char))
        else
            buildStr[i] = char
        end
        i = i + 1
        char = string.sub(value, i, i)
        if i % 200 == 0 then
            -- TODO: add indentation and indent to metadata
            indentStr = indentStr or string.rep(" ", metadata.indentation + metadata.indent)
            table.move({'"\n', indentStr, '... "'}, 1, 3, i, buildStr)
            i += 3
        end
    end
    return metadata and metadata.stringNoQuotes and table.concat(buildStr) or string.format('"%s"', table.concat(buildStr))
end

function types.boolean(value)
    return value and "true" or "false"
end

function types.number(value)
    if value ~= value then
        return "0/0 --[[NaN]]"
    elseif value == math.huge then
        return "math.huge"
    else
        return string.format("%g", value)
    end
end

function types.vector(value)
    return string.format("Vector3.new(%s, %s, %s)", types.number(value.X), types.number(value.Y), types.number(value.Z))
end

types["nil"] = function()
    return "nil"
end

-- Non-Primitives

function types.thread(value)
    return string.format("nil --[[Type: Thread, Status: %s]]", types.string(coroutine.status(value)))
end

types["function"] = function(value)
    return string.format("nil --[[Type: Function, Address: %s]]", string.sub(tostring(value), 10, -1))
end

function types.userdata(value)
    return string.format("newproxy(%s) --[[Type: Userdata, MetatableLocked: %s]]", types.boolean(getmetatable(value) ~= nil and true or false), types.boolean(getmetatable(value) ~= nil and type(getmetatable(value)) ~= "table" and true or false))
end

-- Userdata Subclasses

types.Vector3 = types.vector -- Vector3 being replaced

function types.Instance(value, metadata)
    local pathBuilder = {}
    while value do
        if not value.Parent then
            table.insert(pathBuilder, string.format("getnil(%s, %s)", types.string(value.Name), types.string(value.ClassName)))
            if metadata and metadata.top then
                metadata.InstanceUseNilspace = true
                table.insert(metadata.top, getNilString)
            end
            break
        elseif value.Parent == game then
            if value == workspace then
                table.insert(pathBuilder, "workspace")
            elseif game:GetService(value.ClassName) then
                table.insert(pathBuilder, string.format('game:GetService("%s")', value.ClassName))
            else
                table.insert(pathBuilder, parseIndex(value.Name))
                table.insert(pathBuilder, string.format("game"))
            end
            break
        elseif value.Parent:IsA("Player") then
            table.insert(pathBuilder, parseIndex(value.Name))
            table.insert(pathBuilder, 'game:GetService("Players").LocalPlayer')
            break
        elseif value.Parent:IsA("Model") then
            local player = Players:GetPlayerFromCharacter(value.Parent)
            if player then
                table.insert(pathBuilder, parseIndex(value.Name))
                table.insert(pathBuilder, string.format('game:GetService("Players")%s.Character', player == Players.LocalPlayer and ".LocalPlayer" or parseIndex(player.Name)))
                break
            end
        end
        table.insert(pathBuilder, parseIndex(value.Name))
        value = value.Parent
    end
    local out = ""
    for i = #pathBuilder, 1, -1 do
        out = out .. pathBuilder[i]
    end
    return out
end

return {
    config = function(_, k, v)
        assertTypeOf(k, "string")
        settings[k] = v
    end,
    ---@param varName string
    serialize = function(_, v, varName)
        return valueToVar(v, varName)
    end,
    types = types
}