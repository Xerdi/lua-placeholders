-- lua-placeholders.lua
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

if not modules then
    modules = {}
end

modules.lua_placeholders = {
    version = "1.0.3",
    date = "2024/04/02",
    comment = 'Lua Placeholders — for specifying and inserting document parameters',
    author = 'Erik Nijenhuis',
    license = 'free'
}

local api = {
    namespaces = {},
    parameters = {},
    strict = false,
    toks = {
        is_set_true = token.create('has@param@true'),
        is_set_false = token.create('has@param@false'),
    }
}

-- Active \fortablerow iterations.  Each frame holds the prepared row data;
-- the topmost frame is consumed by api.set_row_macros between rows and
-- popped by api.pop_row_stack when the iteration finishes.  Stack form
-- naturally supports nested \fortablerow calls.
local row_stack = {}
local lua_placeholders = {}
local lua_placeholders_mt = {
    __index = api,
    __newindex = function()
        tex.error('Cannot override or set actions for this module...')
    end
}

setmetatable(lua_placeholders, lua_placeholders_mt)

local lua_placeholders_namespace = require('lua-placeholders-namespace')
local load_resource = require('lua-placeholders-parser')

-- Look up a parameter by key.  When invoked from inside a \fortablerow
-- iteration (i.e. the row stack is non-empty and the topmost frame has an
-- active row), cells of the active row shadow the namespace.  This is what
-- lets list/object cells keep their type: \forlistitem, \paramfield etc.
-- find the cell here instead of looking only at the top-level namespace.
local function get_param(key, namespace)
    local frame = row_stack[#row_stack]
    if frame and frame.current_row and frame.current_row[key] then
        return frame.current_row[key]
    end
    namespace = namespace or tex.jobname
    local _namespace = api.namespaces[namespace]
    return _namespace and _namespace:param(key)
end

function api.set_strict()
    api.strict = true
end

function api.recipe(path, namespace_name)
    if namespace_name == '' then
        namespace_name = nil
    end
    local filename, abs_path = lua_placeholders_namespace.parse_filename(path)
    local raw_recipe = load_resource(abs_path)
    local name = namespace_name or raw_recipe.namespace or filename
    local namespace = api.namespaces[name] or lua_placeholders_namespace:new { recipe_file = abs_path, strict = api.strict }
    if not api.namespaces[name] then
        api.namespaces[name] = namespace
    end
    if raw_recipe.namespace then
        namespace:load_recipe(raw_recipe.parameters)
    else
        namespace:load_recipe(raw_recipe)
    end
    -- The hooks need to be declared in order to work properly in every situation
    tex.print('\\NewHook{namespace/' .. name .. '}')
    tex.print('\\NewHook{namespace/' .. name .. '/loaded}')
    tex.print('\\UseOneTimeHook{namespace/' .. name .. '}')

    if namespace.payload_file and not namespace.payload_loaded then
        local raw_payload = load_resource(namespace.payload_file)
        if raw_payload.namespace then
            namespace:load_payload(raw_payload.parameters)
        else
            namespace:load_payload(raw_payload)
        end
        tex.print('\\UseOneTimeHook{namespace/' .. name .. '/loaded}')
    end
end

function api.payload(path, namespace_name)
    if namespace_name == '' then
        namespace_name = nil
    end
    local filename, abs_path = lua_placeholders_namespace.parse_filename(path)
    local raw_payload = load_resource(abs_path)
    local name = namespace_name or raw_payload.namespace or filename
    local namespace = api.namespaces[name] or lua_placeholders_namespace:new { payload_file = abs_path, strict = api.strict }
    if not api.namespaces[name] then
        api.namespaces[name] = namespace
    end
    if namespace.recipe_loaded then
        if raw_payload.namespace then
            namespace:load_payload(raw_payload.parameters)
        else
            namespace:load_payload(raw_payload)
        end
        tex.print('\\UseOneTimeHook{namespace/' .. name .. '/loaded}')
    end
end

function api.param_object(key, namespace)
    return get_param(key, namespace)
end

function api.param(key, namespace)
    local param = get_param(key, namespace)
    if param then
        param:print_val()
    elseif api.strict then
        tex.error('Error: Parameter not set "' .. key .. '" in namespace "' .. namespace .. '".')
    else
        tex.sprint(lua_placeholders_toks.unknown_format, '{', key, '}')
    end
end

function api.handle_param_is_set(key, namespace)
    local param = get_param(key, namespace)
    if param and param:is_set() then
        tex.sprint(token.create('has@param@true'))
    else
        tex.sprint(token.create('has@param@false'))
    end
end

function api.field(object_key, field, namespace)
    local param = get_param(object_key, namespace)
    if param then
        local object = param.fields or param.default or {}
        local f = object[field]
        if f then
            f:print_val()
        else
            tex.sprint(lua_placeholders_toks.unknown_format, '{', field, '}')
        end
    else
        tex.error('No such object', object_key)
    end
end

function api.with_object(object_key, namespace)
    local object = get_param(object_key, namespace)
    for key, param in pairs(object.fields) do
        local val = param:val()
        if val then
            token.set_macro(key, param:val() .. '\\xspace')
        else
            token.set_macro(key, '\\paramplaceholder{' .. (param.placeholder or key) .. '}\\xspace')
        end
    end
end

function api.for_item(list_key, namespace, csname)
    local param = get_param(list_key, namespace)
    local list = param:val()
    if #list > 0 then
        if token.is_defined(csname) then
            local tok = token.create(csname)
            for _, item in ipairs(list) do
                if param.values then
                    tex.sprint(tok, '{', item:val(), '}')
                else
                    tex.sprint(tok, '{', lua_placeholders_toks.placeholder_format, '{', item:val(), '}}')
                end
            end
        else
            tex.error('No such command ', csname or 'nil')
        end
    end
end

-- Synthesise a single placeholder row from a column spec when there is no
-- payload to iterate over.  Each cell exposes a :val() method matching the
-- shape produced by base_param:load(), so set_row_macros can treat it the
-- same as a real row.
local function placeholder_row(columns)
    local row = {}
    for col_key, col in pairs(columns) do
        if col.default ~= nil then
            -- Reuse the column's own :val() (handles \numprint, etc.)
            row[col_key] = col
        else
            local txt = '\\paramplaceholder{' .. (col.placeholder or col_key) .. '}'
            row[col_key] = { val = function() return txt end }
        end
    end
    return row
end

-- Called by TeX between each row.  Pulls the current frame off the stack
-- and binds every column of the requested row to a global control sequence
-- via token.set_macro.  Setting macros by name bypasses TeX's catcode rules
-- at definition time (so columns whose names contain '_' work even if the
-- user hasn't switched on \ExplSyntaxOn yet); however the user's row macro
-- still has to reference them with the right catcodes, hence the
-- \ExplSyntaxOn idiom.
function api.set_row_macros(idx_str)
    local frame = row_stack[#row_stack]
    if not frame then
        tex.error('lua-placeholders: row binder called outside of \\fortablerow')
        return
    end
    local idx = tonumber(idx_str)
    local row = frame.rows[idx]
    if not row then
        tex.error('lua-placeholders: row index ' .. tostring(idx) .. ' out of range')
        return
    end
    -- Stash the row so get_param resolves \param/\forlistitem/\paramfield/...
    -- references against this row's cells before falling back to the namespace.
    frame.current_row = row
    for col_key, cell in pairs(row) do
        -- list/object/table cells aren't flattened: the type is preserved on
        -- the row frame and the user reaches them via the type-specific
        -- commands (\forlistitem, \paramfield, \paramobject, \fortablerow).
        -- Everything else, including synthetic placeholder cells, becomes a
        -- plain control sequence the row macro can drop in directly.
        if cell.type ~= 'list' and cell.type ~= 'object' and cell.type ~= 'table' then
            local val = cell:val()
            if val == nil then
                val = '\\paramplaceholder{' .. (cell.placeholder or col_key) .. '}'
            end
            token.set_macro(col_key, val, 'global')
        end
    end
end

function api.pop_row_stack()
    table.remove(row_stack)
end

function api.with_rows(key, namespace, csname)
    local param = get_param(key, namespace)
    if not param then
        tex.error('lua-placeholders: no such parameter "' .. tostring(key) .. '"')
        return
    end
    if not token.is_defined(csname) then
        tex.error('lua-placeholders: undefined row macro \\' .. tostring(csname))
        return
    end

    local rows
    if param.values and #param.values > 0 then
        rows = param.values
    elseif param.columns then
        texio.write_nl('Warning: no values set for ' .. param.key)
        rows = { placeholder_row(param.columns) }
    elseif api.strict then
        tex.error('lua-placeholders: table parameter has no values and no columns')
        return
    else
        return
    end

    -- Push the prepared rows onto the stack.  Each row is then materialised
    -- one at a time by an interleaved \directlua call so that the user's row
    -- macro always sees the current row's column bindings and never the
    -- previous row's.
    table.insert(row_stack, { rows = rows })
    for i = 1, #rows do
        tex.sprint('\\directlua{lua_placeholders.set_row_macros(' .. i .. ')}')
        tex.sprint('\\' .. csname)
    end
    tex.sprint('\\directlua{lua_placeholders.pop_row_stack()}')
end

return lua_placeholders
