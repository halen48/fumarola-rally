-- A pista é a faixa "pista" que o jogo monta com world.ribbon. A consulta é do motor e pura
-- (world.ribbon_query): devolve t (0..1), s (metros), edge (distância à
-- borda, < 0 fora), normal (para dentro), tangent, width e height.
local M = {}

M.nome = "pista"

function M.consulta(x: number, z: number)
    local q = (world :: any).ribbon_query
    if not q then
        return nil -- motor sem faixa: o carro anda pelo chão, sem borda
    end
    return q(M.nome, vector.create(x, 0, z))
end

-- Ponto da linha central em t (IA e largada).
function M.ponto(t: number)
    local p = (world :: any).ribbon_point
    if not p then
        return nil
    end
    return p(M.nome, t % 1)
end

return M
