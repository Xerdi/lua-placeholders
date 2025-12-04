-- lua-placeholders-types.lua
-- Copyright 2024 E. Nijenhuis
--
-- This work may be distributed and/or modified under the
-- conditions of the LaTeX Project Public License, either version 1.3c
-- of this license or (at your option) any later version.
-- The latest version of this license is in
-- http://www.latex-project.org/lppl.txt
-- and version 1.3c or later is part of all distributions of LaTeX
-- version 2005/12/01 or later.
--
-- This work has the LPPL maintenance status ‘maintained’.
--
-- The Current Maintainer of this work is E. Nijenhuis.
--
-- This work consists of the files lua-placeholders.sty
-- lua-placeholders-manual.pdf lua-placeholders.lua
-- lua-placeholders-common.lua lua-placeholders-namespace.lua
-- lua-placeholders-parser.lua and lua-placeholders-types.lua

require('lua-placeholders-common')

function table.copy(t)
    local u = { }
    for k, v in pairs(t) do
        u[k] = v
    end
    return setmetatable(u, getmetatable(t))
end

base_param = {}
function base_param:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function base_param:is_set()
    return self and ((self.values or self.fields or self.value) ~= nil)
end

function base_param:raw_val()
    return self.value or self.values or self.default
end

function base_param:val()
    return self:raw_val()
end

function base_param:to_upper()
    local val = self:val()
    if type(val) == 'string' then
        return val:upper()
    elseif type(self.placeholder) == 'string' then
        return '[' .. self.placeholder:upper() .. ']'
    end
end

function base_param:print_val()
    local value = self:val()
    if value ~= nil then
        tex.sprint(value)
    else
        tex.sprint(lua_placeholders_toks.placeholder_format, '{', self.placeholder or self.key, '}')
    end
end

bool_param = base_param:new{
    type = 'bool'
}

function bool_param:new(key, _o)
    local o = {
        key = key,
        default = _o.default
    }
    setmetatable(o, self)
    self.__index = self
    tex.sprint(lua_placeholders_toks.new_bool, '{', o.key, '}')
    return o
end

function bool_param:raw_val()
    local value
    if self.value ~= nil then
        value = tostring(self.value)
    elseif self.default ~= nil then
        value = tostring(self.default)
    else
        value = 'false'
    end
    return value
end

function bool_param:set_bool(key)
    tex.sprint(lua_placeholders_toks.set_bool, '{', key, '}{', self:val(), '}')
end

str_param = base_param:new{
    type = 'string'
}

function str_param:new(key, _o)
    local o = {
        key = key,
        placeholder = _o.placeholder,
        default = _o.default
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function str_param:val()
    local value = self:raw_val()
    if value then
        if type(value) == 'table' and type(value.year) == 'number' then
          value = '\\printdateTeX{' .. value.year .. '/' .. value.month .. '/' .. value.day .. '}'
        end
        local formatted, _ = string.gsub(value, '\n', ' ')
        return formatted
    end
end

number_param = base_param:new{
    type = 'number'
}

function number_param:new(key, _o)
    local o = {
        key = key,
        placeholder = _o.placeholder,
        default = _o.default
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function number_param:raw_val()
    if self.value ~= nil or self.default ~= nil then
        return self.value or self.default
    end
end

function number_param:val()
    local val = self:raw_val()
    if val ~= nil then
        if token.is_defined('numprint') then
            return '\\numprint{' .. val .. '}'
        else
            texio.write_nl([[Warning: package 'numprint' not loaded. Outputting numbers as is.]])
            return val
        end
    end
end

function number_param:print_num()
    texio.write_nl('Warning: number_param:print_num is deprecated. Use number_param:print_val instead')
    self:print_val()
end

list_param = base_param:new{
    type = 'list'
}

function list_param:new(key, _o)
    local o = {
        key = key,
        item_type = base_param.define('list_item', { type = (_o["item type"] or 'string') }),
        default = {}
    }
    if _o.default then
        for _, default_val in ipairs(_o.default) do
            local v = table.copy(o.item_type)
            v:load('list_item', default_val)
            table.insert(o.default, v)
        end
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

function list_param:val()
    return self.values or self.default or {}
end

function list_param:print_val()
    local list = self:val()
    if #list > 0 then
        if not self.values then
            tex.sprint(lua_placeholders_toks.placeholder_format, '{')
        end
        tex.sprint(list[1]:val())
        for i = 2, #list do
            tex.sprint(lua_placeholders_toks.list_conj, list[i]:val())
        end
        if not self.values then
            tex.sprint('}')
        end
    end
end

object_param = base_param:new{
    type = 'object'
}

function object_param:new(key, _o)
    local o = {
        key = key,
        fields = {},
        default = _o.default
    }
    for _key, field in pairs(_o.fields) do
        o.fields[_key] = base_param.define(_key, field)
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

table_param = base_param:new{
    type = 'table'
}

function table_param:new(key, _o)
    local o = {
        key = key,
        columns = {}
    }
    for col_key, col in pairs(_o.columns) do
        o.columns[col_key] = base_param.define(col_key, col)
    end
    setmetatable(o, self)
    self.__index = self
    return o
end

function base_param.define(key, o)
    if o.type then
        if o.type == 'bool' then
            return bool_param:new(key, o)
        elseif o.type == 'string' then
            return str_param:new(key, o)
        elseif o.type == 'number' then
            return number_param:new(key, o)
        elseif o.type == 'list' then
            return list_param:new(key, o)
        elseif o.type == 'object' then
            return object_param:new(key, o)
        elseif o.type == 'table' then
            return table_param:new(key, o)
        else
            texio.write_nl('Warning: no such parameter type ' .. o.type)
        end
    else
        error('ERROR: parameter must have a "type" field')
    end
end

function base_param:load(key, value)
    if self.type == 'list' then
        self.values = {}
        for _, val in ipairs(value) do
            local param = table.copy(self.item_type)
            param:load('list-item', val)
            table.insert(self.values, param)
        end
    elseif self.type == 'table' then
        self.values = {}
        for _, row_vals in ipairs(value) do
            local row = {}
            for col_key, col in pairs(self.columns) do
                local cell = table.copy(col)
                cell:load(col.key, row_vals[col_key])
                row[col_key] = cell
            end
            table.insert(self.values, row)
        end
    elseif self.type == 'object' then
        for field_key, field in pairs(self.fields) do
            local field_val = value[field_key]
            if field_val then
                field:load(field_key, field_val)
            else
                texio.write_nl('Warning: Passed unknown field to object', field_key)
            end
        end
    else
        self.value = value
    end
    if self.type == 'bool' then
        self:set_bool(key)
    end
end
