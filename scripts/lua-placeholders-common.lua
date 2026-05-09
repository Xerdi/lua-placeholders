-- lua-placeholders-common.lua
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

function table.copy(t)
    local u = { }
    for k, v in pairs(t) do
        u[k] = v
    end
    return setmetatable(u, getmetatable(t))
end

lua_placeholders_toks = {
    -- Booleans are bridged through engine-agnostic wrappers so that the
    -- LaTeX side can use \newif-based flags (no ifthen dependency) and the
    -- plain-LuaTeX side can do the same with the same call shape.
    new_bool = token.create('paramnewbool'),
    set_bool = token.create('paramsetbool'),
    list_conj = token.create('paramlistconjunction'),
    placeholder_format = token.create('paramplaceholder'),
    unknown_format = token.create('paramnotfound')
}
