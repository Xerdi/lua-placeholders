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
    version = "2.0.1",
    date = "2026/05/09",
    comment = 'Lua Placeholders — for specifying and inserting document parameters',
    author = 'Erik Nijenhuis',
    license = 'free'
}

local api = {
    namespaces = {},
    parameters = {},
    strict = false,
}

-- Stack of active lookup contexts.  A frame is pushed by anything that wants
-- nested key lookups to resolve against an in-progress structure rather than
-- the top-level namespace: \fortablerow (one frame per iteration, advancing
-- the active entry per row), \forlistitem on a list of objects (same shape
-- as a table iteration, one entry per item's fields), and the \paramobject
-- environment (a single fixed entry for the object's fields).
--
-- Each frame holds:
--     entries  -- array of key->cell maps to walk through
--     current  -- the entry currently bound (consulted by get_param)
--
-- Frames are popped by api.pop_ctx (after \fortablerow / \forlistitem) or
-- api.exit_object (\end{paramobject}).  Stack form means nested contexts
-- (e.g. \paramobject inside another \paramobject) compose naturally.
local ctx_stack = {}
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

-- LaTeX hook system (lthooks) is preloaded in LaTeX2e but absent from plain
-- LuaTeX.  Detect once at module load; \NewHook / \UseOneTimeHook emissions
-- below are gated on this so the same Lua core works in both engines without
-- leaking the hook arguments into the document as text.
local has_hooks = token.is_defined('NewHook') and token.is_defined('UseOneTimeHook')

-- Look up a parameter by key.  When invoked from inside any active context
-- (table row, object env, list-of-object iteration), the topmost frame's
-- current entry shadows the top-level namespace.  This is what lets a cell
-- whose type is itself complex (list, object, table) keep that type:
-- \forlistitem, \paramfield, \paramobject, \fortablerow find the cell here
-- instead of only looking at the namespace.
local function get_param(key, namespace)
    local frame = ctx_stack[#ctx_stack]
    if frame and frame.current and frame.current[key] then
        return frame.current[key]
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
    if has_hooks then
        tex.print('\\NewHook{namespace/' .. name .. '}')
        tex.print('\\NewHook{namespace/' .. name .. '/loaded}')
        tex.print('\\UseOneTimeHook{namespace/' .. name .. '}')
    end

    if namespace.payload_file and not namespace.payload_loaded then
        local raw_payload = load_resource(namespace.payload_file)
        if raw_payload.namespace then
            namespace:load_payload(raw_payload.parameters)
        else
            namespace:load_payload(raw_payload)
        end
        if has_hooks then
            tex.print('\\UseOneTimeHook{namespace/' .. name .. '/loaded}')
        end
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
        if has_hooks then
            tex.print('\\UseOneTimeHook{namespace/' .. name .. '/loaded}')
        end
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
        tex.sprint(token.create('paramhastrue'))
    else
        tex.sprint(token.create('paramhasfalse'))
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
    if not object then
        tex.error('lua-placeholders: no such object "' .. tostring(object_key) .. '"')
        return
    end
    -- Push the object's fields as a context so nested lookups
    -- (\paramfield, \forlistitem on a sub-list, \paramobject on a sub-object)
    -- resolve against this object before falling back to the namespace.
    table.insert(ctx_stack, { entries = { object.fields }, current = object.fields })
    -- Bind primitive fields as direct \field macros, scoped to the \begin
    -- \end paramobject group (no 'global' here, unlike bind_ctx, since the
    -- env's TeX group handles cleanup naturally — \name reverts to its
    -- previous meaning after \end{paramobject}).  Complex fields are reachable
    -- via the type-specific commands once they hit get_param.
    -- The trailing \paramfieldterm is a TeX-side hook: \xspace under LaTeX
    -- (so authors can write \name without {} and not gobble the space),
    -- empty under plain LuaTeX where xspace isn't loaded.
    for key, param in pairs(object.fields) do
        if param.type ~= 'list' and param.type ~= 'object' and param.type ~= 'table' then
            local val = param:val()
            if val ~= nil then
                token.set_macro(key, val .. '\\paramfieldterm')
            else
                token.set_macro(key, '\\paramplaceholder{' .. (param.placeholder or key) .. '}\\paramfieldterm')
            end
        end
    end
end

function api.exit_object()
    table.remove(ctx_stack)
end

function api.for_item(list_key, namespace, csname)
    local param = get_param(list_key, namespace)
    if not param then
        tex.error('lua-placeholders: no such list "' .. tostring(list_key) .. '"')
        return
    end
    if not token.is_defined(csname) then
        tex.error('lua-placeholders: undefined item macro \\' .. tostring(csname))
        return
    end
    local list = param:val()
    if #list == 0 then return end

    local item_type = param.item_type and param.item_type.type
    if item_type == 'object' then
        -- Each item is an object; treat its fields as one entry in a context
        -- frame and let the user's csname access them via direct \field
        -- macros or nested type-specific commands.  csname takes no arguments
        -- here.
        local entries = {}
        for _, item in ipairs(list) do
            table.insert(entries, item.fields)
        end
        table.insert(ctx_stack, { entries = entries })
        for i = 1, #entries do
            tex.sprint('\\directlua{lua_placeholders.bind_ctx(' .. i .. ')}')
            tex.sprint('\\' .. csname)
        end
        tex.sprint('\\directlua{lua_placeholders.pop_ctx()}')
    elseif item_type == 'list' or item_type == 'table' then
        -- Each item is itself a complex type with no natural field name.
        -- Bind it under the synthetic key 'self' so the user's csname can
        -- reach the current item with e.g. \fortablerow{self}{...} or
        -- \forlistitem{self}{...}.  csname takes no arguments here.
        local entries = {}
        for _, item in ipairs(list) do
            table.insert(entries, { self = item })
        end
        table.insert(ctx_stack, { entries = entries })
        for i = 1, #entries do
            tex.sprint('\\directlua{lua_placeholders.bind_ctx(' .. i .. ')}')
            tex.sprint('\\' .. csname)
        end
        tex.sprint('\\directlua{lua_placeholders.pop_ctx()}')
    else
        -- Primitive item: csname takes the value as a single argument.
        local tok = token.create(csname)
        for _, item in ipairs(list) do
            if param.values then
                tex.sprint(tok, '{', item:val(), '}')
            else
                tex.sprint(tok, '{', lua_placeholders_toks.placeholder_format, '{', item:val(), '}}')
            end
        end
    end
end

-- Synthesise a single placeholder row from a column spec when there is no
-- payload to iterate over.  Each cell exposes a :val() method matching the
-- shape produced by base_param:load(), so bind_ctx can treat it the same
-- as a real row.  Complex-typed columns are returned as the column itself
-- (which is a real list_param/object_param/table_param) so that the user's
-- row macro can still call \forlistitem / \paramfield / \fortablerow on
-- them and reach a real param --- iteration just produces an empty body.
local function placeholder_row(columns)
    local row = {}
    for col_key, col in pairs(columns) do
        if col.type == 'list' or col.type == 'object' or col.type == 'table' then
            row[col_key] = col
        elseif col.default ~= nil then
            -- Reuse the column's own :val() (handles \numprint, etc.)
            row[col_key] = col
        else
            local txt = '\\paramplaceholder{' .. (col.placeholder or col_key) .. '}'
            row[col_key] = { val = function() return txt end }
        end
    end
    return row
end

-- Called by TeX between each iteration.  Advances the topmost context frame
-- to entry idx and binds every leaf-typed cell to a global control sequence
-- via token.set_macro.  Setting macros by name bypasses TeX's catcode rules
-- at definition time (so cells whose keys contain '_' work even if the user
-- hasn't switched on \ExplSyntaxOn yet); however the user's iteration macro
-- still has to reference them with the right catcodes, hence the
-- \ExplSyntaxOn idiom.
function api.bind_ctx(idx_str)
    local frame = ctx_stack[#ctx_stack]
    if not frame then
        tex.error('lua-placeholders: bind_ctx called outside of \\fortablerow / \\forlistitem')
        return
    end
    local idx = tonumber(idx_str)
    local entry = frame.entries[idx]
    if not entry then
        tex.error('lua-placeholders: ctx entry ' .. tostring(idx) .. ' out of range')
        return
    end
    -- Stash the entry so get_param resolves \param / \forlistitem /
    -- \paramfield / ... references against its cells before falling back to
    -- the namespace.
    frame.current = entry
    for col_key, cell in pairs(entry) do
        -- list/object/table cells aren't flattened: the type is preserved on
        -- the frame and the user reaches them via the type-specific commands
        -- (\forlistitem, \paramfield, \paramobject, \fortablerow).
        -- Everything else, including synthetic placeholder cells, becomes a
        -- plain control sequence the iteration macro can drop in directly.
        if cell.type ~= 'list' and cell.type ~= 'object' and cell.type ~= 'table' then
            local val = cell:val()
            if val == nil then
                val = '\\paramplaceholder{' .. (cell.placeholder or col_key) .. '}'
            end
            token.set_macro(col_key, val, 'global')
        end
    end
end

function api.pop_ctx()
    table.remove(ctx_stack)
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

    -- Push the prepared rows as a context frame.  Each row is then
    -- materialised one at a time by an interleaved \directlua call so that
    -- the user's row macro always sees the current row's column bindings
    -- and never the previous row's.
    table.insert(ctx_stack, { entries = rows })
    for i = 1, #rows do
        tex.sprint('\\directlua{lua_placeholders.bind_ctx(' .. i .. ')}')
        tex.sprint('\\' .. csname)
    end
    tex.sprint('\\directlua{lua_placeholders.pop_ctx()}')
end

return lua_placeholders
