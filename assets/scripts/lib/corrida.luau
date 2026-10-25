-- Regras da corrida: volta, checkpoints, colocação e chegada.
-- A volta só conta com os 3 checkpoints do meio passados em ordem (máscara
-- em C.cp), então cortar caminho ou dar ré pela linha não vale.
local M = {}

M.voltas = 3
local CHECK = { 0.25, 0.5, 0.75 }
local TODOS = 7 -- bits 1|2|4

function M.contar(C, i: number, t_antes: number, dt: number, relogio: number)
    if C.chegou[i] > 0 then
        return
    end
    C.t_volta[i] += dt
    local t = C.t[i]
    for k, marca in CHECK do
        local bit = 2 ^ (k - 1)
        local tem = bit32.band(C.cp[i], bit) ~= 0
        if not tem and t_antes < marca and t >= marca and t - t_antes < 0.1 then
            C.cp[i] = bit32.bor(C.cp[i], bit)
        end
    end
    -- Cruzou a linha (t passou de perto de 1 para perto de 0) com os checkpoints.
    if t_antes > 0.9 and t < 0.1 and C.cp[i] == TODOS then
        C.volta[i] += 1
        C.t_melhor[i] = math.min(C.t_melhor[i], C.t_volta[i])
        C.t_volta[i] = 0
        C.cp[i] = 0
        if C.volta[i] >= M.voltas then
            C.chegou[i] = relogio
        end
    end
end

-- Colocação pela distância total (voltas + t); quem chegou fica pela hora.
function M.colocar(C)
    local ordem = table.create(C.n, 0)
    for i = 1, C.n do
        ordem[i] = i
    end
    local function chave(i)
        if C.chegou[i] > 0 then
            return 1e6 - C.chegou[i]
        end
        return C.volta[i] + C.t[i]
    end
    table.sort(ordem, function(a, b)
        return chave(a) > chave(b)
    end)
    for pos, i in ordem do
        C.colocacao[i] = pos
    end
    return ordem
end

return M
