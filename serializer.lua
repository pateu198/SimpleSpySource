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
    assertTypeOf(name, "string")
    local metadata = { bottomStr = "" }
    if string.match(name, variablePattern) then
        return string.format("local %s = %s", name, typeToString(value) .. metadata.bottomStr)
    else
        return string.format("local t = %s", typeToString(value))
    end
end

--- Wrapper for `types`
function typeToString(value, metadata)
    metadata = metadata or {}
    local out = types[getTypeOf(value)]
    return out and out(value, metadata) or string.format("nil --[[UnhandledType: %s, UserdataSubclass: %s]]", getTypeOf(value))
end

---- TYPE HANDLING ----

-- Primitive/Immutable

function types.string(value)
    local i = 1
    local char = string.sub(value, i, i)
    local buildStr = ""
    while char ~= "" do
        if char == '"' then
            buildStr = buildStr .. '\\"'
        elseif char == "\\" then
            buildStr = buildStr .. "\\\\"
        elseif char == "\n" then
            buildStr = buildStr .. "\\n"
        elseif char == "\t" then
            buildStr = buildStr .. "\\t"
        elseif string.byte(char) > 126 or string.byte(char) < 32 then
            buildStr = buildStr .. string.format("\\%d", string.byte(char))
        else
            buildStr = buildStr .. char
        end
        i = i + 1
        char = string.sub(value, i, i)
    end
    return string.format('"%s"', buildStr)
end

function types.boolean(value)
    return value and "true" or "false"
end

function types.number(value)
    if value ~= value then
        return "0/0 --[[NaN]]"
    else
        return string.format("%g", value)
    end
end

function types.vector(value)
    return string.format("Vector3.new(%s, %s, %s)", types.number(value.X), types.number(value.Y), types.number(value.Z))
end

-- Non-Primitives

-- Userdata Subclasses

types.Vector3 = types.vector -- Vector3 being replaced

return {
    config = function(_, k, v)
        assertTypeOf(k, "string")
        settings[k] = v
    end,
    ---@param varName string
    serialize = function(_, v, varName)
        return valueToVar(v, varName)
    end
}