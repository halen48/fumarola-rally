-- HUD: lê as colunas e escreve nos widgets de hud.css. Volta, posição, tempo, velocidade, turbo, calor, a
-- ordem da corrida no topo (cartões que deslizam quando alguém passa) e o
-- minimapa (contorno da pista + um quadrado por carro).
local PISTA = require("lib/pista")

local M = {}

local VAGAS, PONTOS = 8, 72
-- Retângulo do minimapa na tela, em % (igual ao #mm-fundo do CSS), com margem.
local MM_X, MM_Y, MM_L, MM_A, MARGEM = 80, 64, 18, 32, 1.2
local CORES = { -- quadrado de cada carro no minimapa: a cor da equipe
    vermelho = vector.create(0.95, 0.25, 0.2), azul = vector.create(0.25, 0.5, 1),
    verde = vector.create(0.3, 0.85, 0.35), amarelo = vector.create(1, 0.85, 0.2),
}

local LARGURA_VAGA = 12.5 -- % da faixa #ordem por cartão (igual ao CSS)
local DESLIZA = 7          -- 1/s: o cartão corre até a vaga nova
local CLARAO = 0.6         -- s de brilho no cartão de quem acabou de passar
local KMH = 2.5            -- escala de jogo: 82 u/s dão 205 km/h (Top Gear mostra 200+)

local minx, minz, escala = 0, 0, 1
local rotulos = {}
local comprimento = 1
local vaga_de, x_cartao, clarao = {}, {}, {}

local function relogio(s: number)
    if s == math.huge then
        return ""
    end
    return string.format("%d:%05.2f", s // 60, s % 60)
end

local function no_mapa(x: number, z: number)
    return MM_X + MARGEM + (x - minx) * escala, MM_Y + MM_A - MARGEM - (z - minz) * escala * (16 / 9)
end

-- `rotulo[i]`: nome curto; `cor[i]`: cor da equipe; `retrato[i]`:
-- {folha, u0, v0, u1, v1} do quadro que vai no cartão.
local minimapa -- abaixo

function M.iniciar(C, rotulo, cor, retrato)
    ui.load("assets/ui/hud.css")
    rotulos = rotulo
    comprimento = math.max(1, world.ribbon_length(PISTA.nome))
    for k = 1, VAGAS do
        ui.visible("#vaga-" .. k, k <= C.n)
        for _, parte in { "ret", "pos", "nome", "gap" } do
            ui.visible("#vaga-" .. k .. "-" .. parte, k <= C.n)
        end
        -- Cartão k é o do carro k; ele desliza entre as vagas.
        if k <= C.n then
            local r = retrato[k]
            ui.image("#vaga-" .. k .. "-ret", r[1])
            ui.image_rect("#vaga-" .. k .. "-ret", r[2], r[3], r[4], r[5])
            ui.text("#vaga-" .. k .. "-nome", rotulo[k])
            vaga_de[k], x_cartao[k], clarao[k] = k, (k - 1) * LARGURA_VAGA, 0
        end
    end
    minimapa()
    for k = 1, VAGAS do
        ui.visible("#mm-c" .. k, k <= C.n)
        if k <= C.n and cor[k] then
            ui.color("#mm-c" .. k, CORES[cor[k]] or vector.create(1, 1, 1))
        end
    end
end

-- Contorno: amostra a faixa e ajusta a caixa dela no retângulo do minimapa.
-- No toque o canto de baixo é dos botões Turbo/OK: o minimapa sobe para logo
-- abaixo da faixa de posições. O navegador só sabe que a tela é de toque
-- depois do primeiro toque, então M.atualizar refaz isto quando muda.
minimapa = function()
    MM_Y = if input.touch() then 13 else 64
    ui.place("#mm-fundo", MM_X, MM_Y)
    local xs, zs = {}, {}
    local maxx, maxz = -math.huge, -math.huge
    minx, minz = math.huge, math.huge
    for k = 1, PONTOS do
        local p = PISTA.ponto((k - 1) / PONTOS)
        if p then
            xs[k], zs[k] = p.position.x, p.position.z
            minx, maxx = math.min(minx, xs[k]), math.max(maxx, xs[k])
            minz, maxz = math.min(minz, zs[k]), math.max(maxz, zs[k])
        end
    end
    local util_l, util_a = MM_L - 2 * MARGEM, (MM_A - 2 * MARGEM) * (9 / 16)
    escala = math.min(util_l / math.max(1, maxx - minx), util_a / math.max(1, maxz - minz))
    -- Largada e chegada: o quadrado xadrez no ponto 0 da faixa, onde está o arco.
    if xs[1] then
        local l, t = no_mapa(xs[1], zs[1])
        ui.place("#mm-chegada", l - 0.4, t - 0.65)
    end
    for k = 1, PONTOS do
        if xs[k] then
            local l, t = no_mapa(xs[k], zs[k])
            ui.place("#mm-p" .. k, l, t)
        else
            ui.visible("#mm-p" .. k, false)
        end
    end
end

function M.atualizar(C, eu: number, voltas: number, ordem, dt: number)
    if (MM_Y == 13) ~= input.touch() then
        minimapa()
    end
    ui.text("#hud-volta", string.format("VOLTA %d/%d", math.min(C.volta[eu] + 1, voltas), voltas))
    ui.text("#hud-pos", string.format("%dº", C.colocacao[eu]))
    ui.text("#hud-tempo", relogio(C.t_volta[eu]))
    ui.text("#hud-melhor", if C.t_melhor[eu] < math.huge then "melhor " .. relogio(C.t_melhor[eu]) else "")
    ui.text("#hud-vel", string.format("%d km/h", math.floor(math.abs(C.vel[eu]) * KMH + 0.5)))
    ui.value("#hud-turbo", C.turbo[eu])
    ui.value("#hud-calor", math.min(1, C.calor[eu] / 100))
    ui.text("#hud-aviso", if C.superaq[eu] == 1 then "SUPERAQUECIDO"
        elseif C.chegou[eu] > 0 then string.format("%dº LUGAR", C.colocacao[eu]) else "")
    ui.text("#hud-dica", if C.chegou[eu] > 0 then if input.touch() then "OK: classificação" else "Enter: classificação" else "")
    M.ordem(C, eu, ordem, dt)
    for i = 1, math.min(VAGAS, C.n) do
        local l, t = no_mapa(C.px[i], C.pz[i])
        ui.place("#mm-c" .. i, l - 0.2, t - 0.4)
    end
end

-- A fila: cada cartão corre para a vaga da colocação atual; quem ganhou
-- posição acende. Distância ao líder em segundos pela velocidade de cada um.
function M.ordem(C, eu: number, ordem, dt: number)
    local lider = ordem[1]
    local prog_lider = if lider then C.volta[lider] + C.t[lider] else 0
    local f = math.min(1, DESLIZA * dt)
    for pos = 1, math.min(VAGAS, #ordem) do
        local i = ordem[pos]
        if pos < vaga_de[i] then
            clarao[i] = CLARAO
        end
        vaga_de[i] = pos
        x_cartao[i] += ((pos - 1) * LARGURA_VAGA - x_cartao[i]) * f
        clarao[i] = math.max(0, clarao[i] - dt)
        local sel = "#vaga-" .. i
        ui.place(sel, x_cartao[i], 0)
        ui.text(sel .. "-pos", tostring(pos))
        if i == eu then
            ui.text(sel .. "-nome", "VOCÊ")
        end
        local gap = ""
        if pos > 1 then
            local metros = (prog_lider - C.volta[i] - C.t[i]) * comprimento
            gap = string.format("+%.1fs", metros / math.max(15, math.abs(C.vel[i])))
        end
        ui.text(sel .. "-gap", gap)
        local brilho = clarao[i] / CLARAO
        local base = if i == eu then vector.create(0.55, 0.28, 0.08) else vector.create(0.16, 0.1, 0.07)
        ui.color(sel, base + (vector.create(0.95, 0.75, 0.3) - base) * brilho, 0, 0.9)
    end
end

function M.contagem(texto: string)
    ui.text("#hud-aviso", texto)
end

return M
