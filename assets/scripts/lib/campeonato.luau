-- Campeonato: cinco pistas em sequência, pontos por chegada e a
-- classificação geral entre uma corrida e outra. Os pilotos são fixos do
-- começo ao fim (modelo, cor, nome); o grid de cada corrida sai da
-- classificação. Não sabe de física nem de tela: main.luau pergunta e
-- hud/ranking mostram.
local TRACADO = require("lib/tracado")

local M = {}

M.PISTAS = TRACADO.ordem -- caldeira, cinzas, obsidiana, anel, cume
M.VOLTAS = 3
-- Pontos por posição na corrida (estilo de kart: todo mundo pontua um pouco,
-- ganhar vale bem mais que chegar em 2º).
M.PONTOS = { 15, 12, 10, 8, 6, 4, 3, 2 }

M.etapa = 1
-- Apelidos dos adversários (o carro é homenagem ao rock; o piloto tem nome
-- de vulcão): dois pilotos podem ter o mesmo modelo, o nome os separa.
local APELIDOS = { "Magma", "Tefra", "Basalto", "Escória", "Pomes", "Lapilli", "Cratera" }
M.pilotos = {} -- [k] = { modelo, cor, rotulo, nome, pontos, jogador, dono }

-- `n` pilotos; os humanos ficam no fim (largam atrás na 1ª corrida).
-- `humanos[h] = { modelo, dono, nome }`: dono é o id do jogador na sala
-- (0 sozinho); `meu` é o dono desta máquina, o piloto que vira "VOCÊ".
function M.novo_sala(n: number, humanos, meu: number, fichas, cores)
    M.etapa = 1
    M.pilotos = {}
    local robos = n - #humanos
    for k = 1, n do
        local h = humanos[k - robos]
        local modelo = if h then h.modelo else (humanos[1].modelo + k - 1) % #fichas + 1
        local jogador = h ~= nil and h.dono == meu
        local apelido = APELIDOS[(k - 1) % #APELIDOS + 1]
        M.pilotos[k] = {
            modelo = modelo,
            cor = cores[(k - 1) % #cores + 1],
            nome = if jogador then "VOCÊ" elseif h then h.nome else apelido .. " · " .. fichas[modelo].curto,
            rotulo = if jogador then fichas[modelo].curto elseif h then h.nome else apelido,
            pontos = 0,
            jogador = jogador,
            dono = if h then h.dono else nil,
        }
    end
end

-- Sozinho: um humano, o último do grid.
function M.novo(n: number, modelo_jogador: number, fichas, cores)
    M.novo_sala(n, { { modelo = modelo_jogador, dono = 0, nome = "VOCÊ" } }, 0, fichas, cores)
end

function M.pista(): string
    return M.PISTAS[M.etapa]
end

function M.ultima(): boolean
    return M.etapa >= #M.PISTAS
end

-- Pilotos em ordem de classificação geral (pontos; empate: quem foi melhor
-- na última corrida, guardado em `ultima_pos`).
function M.classificacao()
    local ordem = {}
    for k = 1, #M.pilotos do
        ordem[k] = k
    end
    table.sort(ordem, function(a, b)
        local pa, pb = M.pilotos[a], M.pilotos[b]
        if pa.pontos ~= pb.pontos then
            return pa.pontos > pb.pontos
        end
        return (pa.ultima_pos or 99) < (pb.ultima_pos or 99)
    end)
    return ordem
end

-- Ordem do grid (pole primeiro): 1ª corrida na ordem dos pilotos (jogador
-- atrás); depois, a classificação geral invertida — o líder sai lá de trás
-- e tem que remontar, como nos campeonatos de kart.
function M.grid()
    if M.etapa == 1 then
        local g = {}
        for k = 1, #M.pilotos do
            g[k] = k
        end
        return g
    end
    local c = M.classificacao()
    local g = {}
    for k = #c, 1, -1 do
        g[#g + 1] = c[k]
    end
    return g
end

-- Fecha a corrida: `chegada[pos] = piloto`. Devolve os pontos ganhos por
-- piloto.
function M.pontuar(chegada)
    local ganho = {}
    for pos, k in chegada do
        local p = M.PONTOS[pos] or 0
        ganho[k] = p
        M.pilotos[k].pontos += p
        M.pilotos[k].ultima_pos = pos
    end
    return ganho
end

function M.avancar()
    M.etapa += 1
end

return M
