-- lua-placeholders-namespace.lua
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

require('lua-placeholders-types')

local namespace = {
    strict = false,
    recipe_file = nil,
    recipe_loaded = false,
    payload_file = nil,
    payload_loaded = false
}

function namespace.parse_filename(path)
    local abs_path = kpse.find_file(path)
    local filename = abs_path:match('([^/]+)$')
    local name = filename and filename:match('^(.+)%.[^.]+$') or filename
    return name, abs_path
end

function namespace:new(_o)
    local o = {
        recipe_file = _o.recipe_file,
        payload_file = _o.payload_file,
        strict = _o.strict,
        values = {}
    }
    setmetatable(o, self)
    self.__index = self
    return o
end

function namespace:load_recipe(params)
    for key, opts in pairs(params) do
        local param = base_param.define(key, opts)
        if param then
            self.values[key] = param
        end
    end
    self.recipe_loaded = true
end

function namespace:load_payload(values)
    if self.recipe_loaded then
        if values then
            for key, value in pairs(values) do
                if self.values[key] then
                    local param = self.values[key]
                    param:load(key, value)
                else
                    texio.write_nl('Warning: passed an unknown key ' .. key)
                end
                texio.write_nl('Info: loaded key ' .. key)
            end
        else
            texio.write_nl('Warning: Payload file was empty')
        end
        self.payload_loaded = true
    end
end

function namespace:param(key)
    if not self.recipe_loaded then
        tex.error('Error: Recipe was not loaded yet...')
        return nil
    end
    if not self.payload_loaded then
        if self.strict then
            tex.error('Error: Payload was not loaded yet...')
            return nil
        else
            texio.write_nl('Warning: Payload was not loaded yet...')
        end
    end
    return self.values[key]
end

return namespace
