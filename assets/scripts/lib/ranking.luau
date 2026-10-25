-- Quadro de pontos entre as corridas (ranking.css). Primeiro aparece a ordem
-- de chegada com os pontos ganhos; depois o total de cada um conta até o
-- novo valor e as linhas deslizam para a ordem do campeonato — a leitura dos
-- campeonatos de kart. Enter/A (ou tocar) segue quando a conta acabou.
local M = {}

local LINHAS = 8
local TOPO, PASSO_Y = 20, 9.2   -- % da tela: 1ª linha e distância entre linhas
local MOSTRA = 1.2              -- s só com a chegada
local CONTA = 1.0               -- s da contagem do total
local DESLIZA = 6               -- 1/s: a linha corre até a vaga nova

local camp
local chegada, ganho, retratos = {}, {}, {}
local antes = {}                -- total de cada piloto antes desta corrida
local vaga_corrida, vaga_geral = {}, {}
local y_linha = {}
local relogio = 0
local final = false

local COR_LINHA = vector.create(0.165, 0.102, 0.071)
local COR_VOCE = vector.create(0.55, 0.27, 0.08)

local function ordinal(n: number)
    return string.format("%dº", n)
end

-- `chegada[pos] = piloto`, `ganho[piloto] = pontos`, `retratos[piloto] =
-- {folha, u0, v0, u1, v1}`. `titulo`/`sub` no topo; `fim` = última etapa.
function M.abrir(c, chegada_, ganho_, retratos_, titulo: string, sub: string, fim: boolean)
    camp, chegada, ganho, retratos, final = c, chegada_, ganho_, retratos_, fim
    relogio = 0
    ui.load("assets/ui/ranking.css")
    ui.text("#rk-titulo", titulo)
    ui.text("#rk-sub", sub)
    ui.text("#rk-dica", "")
    vaga_corrida, vaga_geral, antes = {}, {}, {}
    for pos, k in chegada do
        vaga_corrida[k] = pos
        antes[k] = camp.pilotos[k].pontos - (ganho[k] or 0)
    end
    for pos, k in camp.classificacao() do
        vaga_geral[k] = pos
    end
    for linha = 1, LINHAS do
        local k = chegada[linha]
        local sel = "#rk-" .. linha
        ui.visible(sel, k ~= nil)
        if k then
            local p = camp.pilotos[k]
            y_linha[linha] = TOPO + (linha - 1) * PASSO_Y
            ui.place(sel, 22, y_linha[linha])
            ui.color(sel, if p.jogador then COR_VOCE else COR_LINHA, 0)
            ui.text(sel .. "-pos", ordinal(linha))
            ui.text(sel .. "-nome", p.nome)
            ui.text(sel .. "-ganho", string.format("+%d", ganho[k] or 0))
            ui.text(sel .. "-total", tostring(antes[k]))
            local r = retratos[k]
            if r then
                ui.image(sel .. "-ret", r[1])
                ui.image_rect(sel .. "-ret", r[2], r[3], r[4], r[5])
            end
        end
    end
end

-- Devolve true quando o jogador pede para seguir (`auto`: teste, segue
-- sozinho 1,5 s depois da conta).
function M.atualizar(dt: number, auto: boolean?): boolean
    relogio += dt
    local f = math.clamp((relogio - MOSTRA) / CONTA, 0, 1)
    local pronto = relogio > MOSTRA + CONTA
    for linha = 1, LINHAS do
        local k = chegada[linha]
        if k then
            local sel = "#rk-" .. linha
            local total = antes[k] + math.floor((ganho[k] or 0) * f + 0.5)
            ui.text(sel .. "-total", tostring(total))
            -- Depois da conta, a linha vai para a vaga do campeonato.
            local vaga = if pronto then vaga_geral[k] else vaga_corrida[k]
            local alvo = TOPO + (vaga - 1) * PASSO_Y
            y_linha[linha] += (alvo - y_linha[linha]) * math.min(1, DESLIZA * dt)
            ui.place(sel, 22, y_linha[linha])
            if pronto then
                ui.text(sel .. "-pos", ordinal(vaga))
            end
        end
    end
    if pronto then
        ui.text("#rk-dica", string.format("%s: %s", if input.touch() then "toque" else "Enter",
            if final then "voltar ao menu" else "próxima pista"))
        if auto then
            return relogio > MOSTRA + CONTA + 1.5
        end
        return input.pressed("enter") or input.pressed("space") or input.pressed("pad_a") or ui.clicked("#rk-fundo")
    end
    return false
end

return M
