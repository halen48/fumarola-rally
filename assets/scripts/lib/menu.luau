-- Menu de entrada: só a escolha do carro (o campeonato decide as pistas), com
-- a câmera dando a volta no mapa atrás do painel. Setas/direcional trocam o
-- carro, Enter/A corre; no toque, as setas da tela trocam e tocar no carro
-- corre. Devolve o modelo escolhido e o modo ("sozinho", "criar" ou "entrar"
-- a sala da corrida em rede) quando o jogador decide.
local TRACADO = require("lib/tracado")
local REDE = require("lib/rede")

local M = {}

local escolha = 1
local orbita = 0
local relogio = 0
local cor_carro = "azul"

local GIRO = 5        -- direções da folha por segundo: o carro dá a volta em 1,6 s
local RECORTE = 0.08  -- fração cortada de cada borda do quadro do carro

-- Barras da ficha: a faixa de valores das fichas vira 0,15..1.
local function barra(v: number, lo: number, hi: number)
    return 0.15 + 0.85 * math.clamp((v - lo) / (hi - lo), 0, 1)
end

local function texto(fichas)
    local f = fichas[escolha]
    ui.text("#menu-carro", f.nome)
    ui.value("#ficha-vel", barra(f.potencia, 0.85, 1.12))
    ui.value("#ficha-curva", barra(f.pneu, 0.85, 1.12))
    ui.value("#ficha-peso", barra(f.massa, 0.8, 1.35))
end

local function previa(dt: number)
    relogio += dt
    -- Uma linha da folha por direção (8 linhas), o 1º quadro da linha, sem a
    -- borda vazia do quadro.
    local folha = string.format("assets/sprites/carros/carro_%d_%s_par_8dir.png", escolha, cor_carro)
    local dir = math.floor(relogio * GIRO) % 8
    local u, v, cw, ch = 0, dir / 8, 1 / 5, 1 / 8
    ui.image("#menu-carro-img", folha)
    ui.image_rect("#menu-carro-img", u + cw * RECORTE, v + ch * RECORTE, u + cw * (1 - RECORTE), v + ch * (1 - RECORTE))
end

-- `cor`: a cor que o carro do jogador vai ter (a prévia mostra ela).
function M.abrir(fichas, cor: string?)
    cor_carro = cor or cor_carro
    ui.load("assets/ui/menu.css")
    audio.music("assets/musica/menu.ogg", { loop = true }, 1)
    camera.free(true)
    input.touch_pad(false) -- o motor começa com o painel à mostra
    -- Sem o módulo de rede (navegador) não há sala.
    for _, b in { "#menu-criar", "#menu-criar-t", "#menu-entrar", "#menu-entrar-t" } do
        ui.visible(b, REDE.disponivel())
    end
    texto(fichas)
end

function M.atualizar(fichas, dt: number)
    -- Câmera passeando sobre o mapa atrás do painel.
    orbita = (orbita + 6 * dt) % 360
    local p = TRACADO.pistas[world.map()]
    local c = if p then p.tamanho / 2 else 500
    camera.set_target(vector.create(c, world.ground_height(c, c), c))
    camera.set_orbit(orbita, 52, 700)

    local delta = 0
    if input.pressed("left") or input.pressed("A") or input.pressed("pad_left") or ui.clicked("#menu-seta-e") then
        delta = -1
    elseif input.pressed("right") or input.pressed("D") or input.pressed("pad_right") or ui.clicked("#menu-seta-d") then
        delta = 1
    end
    if delta ~= 0 then
        escolha = (escolha - 1 + delta) % #fichas + 1
    end
    texto(fichas)
    -- No navegador o toque só se revela no primeiro dedo.
    if input.touch() then
        ui.text("#menu-dica", "« » escolher o carro      toque no carro: correr")
    end
    previa(dt)
    if input.pressed("enter") or input.pressed("space") or input.pressed("pad_a") or ui.clicked("#menu-garagem") then
        return escolha, "sozinho"
    end
    if REDE.disponivel() then
        if input.pressed("C") or input.pressed("pad_x") or ui.clicked("#menu-criar") then
            return escolha, "criar"
        end
        if input.pressed("E") or input.pressed("pad_y") or ui.clicked("#menu-entrar") then
            return escolha, "entrar"
        end
    end
    return nil, nil
end

return M
