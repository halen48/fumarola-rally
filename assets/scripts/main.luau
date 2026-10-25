-- Fumarola Rally: o laço da corrida. Cada parte mora em lib/ e faz uma coisa:
--   corpos   colunas SoA do estado     fisica   passo fixo, puro
--   piso     qualidades do chão         ia       piloto automático
--   corrida  voltas e colocação         visual   sprite de cada corpo
--   camera_corrida, hud, rede, som, menu
--
-- Estados: "menu" (carro) → ["sala" (corrida em rede)] → "carregando" (mapa
-- da etapa) → "corrida" → "ranking" (pontos; Enter vai para a próxima etapa)
-- → ... → depois da 5ª etapa o ranking final volta ao menu. Ver
-- lib/campeonato.luau. Em rede quem decide etapa, chegada e fim é o
-- anfitrião (lib/rede.luau); cada máquina age quando o anúncio chega.
local CORPOS = require("lib/corpos")
local FISICA = require("lib/fisica")
local PISO = require("lib/piso")
local IA = require("lib/ia")
local CORRIDA = require("lib/corrida")
local VISUAL = require("lib/visual")
local CAMERA = require("lib/camera_corrida")
local HUD = require("lib/hud")
local REDE = require("lib/rede")
local PISTA = require("lib/pista")
local TRACADO = require("lib/tracado")
local SOM = require("lib/som")
local MENU = require("lib/menu")
local CENARIO = require("lib/cenario")
local CAMP = require("lib/campeonato")
local RANKING = require("lib/ranking")
local SALA = require("lib/sala")

-- Teste/bancada: quem testa grava teste_config.luau antes de abrir o jogo
-- (o jogador vira IA e a corrida fecha sozinha). Fora do teste não existe.
local ok, TESTE = pcall(require, "teste_config")
TESTE = if ok and type(TESTE) == "table" then TESTE else {}

local PASSO = 1 / 60
local CARROS = TESTE.carros or 6
-- Nível de cada adversário na ordem do grid (1..3, ver lib/ia.luau): a
-- maioria no topo, para o jogador ter que suar.
local NIVEL = { 3, 2, 3, 3, 2 }
local CORES = { "vermelho", "azul", "verde", "amarelo" }
-- Um corpo por modelo de carro (carro_<n>_*.png); o nome é homenagem ao rock.
local FICHAS = {
    { nome = "Highway Star", curto = "Highway", raio = 4.5, potencia = 1.1, pneu = 0.9, massa = 0.9 },   -- rápido e solto
    { nome = "Green Machine", curto = "Green M.", raio = 4.5, potencia = 1.05, pneu = 1.0, massa = 1.0 }, -- equilibrado
    { nome = "Panama", curto = "Panama", raio = 4.5, potencia = 1.0, pneu = 1.05, massa = 1.0 },         -- cola na curva
    { nome = "Space Truckin'", curto = "Truckin'", raio = 5, potencia = 0.9, pneu = 1.1, massa = 1.3, sofre_calor = 0.7 }, -- pesado, aguenta calor
}

local C = CORPOS.novo(16)
local acumulado, relogio, largada = 0, 0, 3.5
local eu = 1
local estado, alvo = "menu", nil
local seguir, espera = false, 0 -- jogador pediu a próxima pista; nova tentativa a cada 1 s
local rotulos, cores, retratos = {}, {}, {}
local piloto_de = {}  -- [corpo] = piloto do campeonato
local dono_de = {}    -- [corpo] = id na sala do humano que dirige (nil: IA)
local modelo_menu = 1
local fim_pedido = false -- anfitrião já anunciou a chegada desta etapa
local largou = false     -- anfitrião: todos montaram a pista e o relógio anda
local espera_prontos = 0
local retrato_piloto = {}

local function entrada_jogador()
    local e = {
        steer = (if input.down("right") or input.down("D") or input.down("pad_right") then 1 else 0)
            - (if input.down("left") or input.down("A") or input.down("pad_left") then 1 else 0),
        -- No toque o acelerador é automático (um dedo no analógico, outro no
        -- turbo); puxar o analógico para baixo freia. Sem virar, o carro vai
        -- reto até o muro e fica preso nele, como no teclado.
        throttle = if input.touch() or input.down("up") or input.down("W") or input.down("pad_a") then 1 else 0,
        brake = input.down("down") or input.down("S") or input.down("pad_b"),
        turbo = input.down("space") or input.down("pad_rb"),
    }
    return e
end

-- A faixa da pista, com barreiras nas bordas.
local ESCALA_PECA = 8

-- Linha de chegada em t = 0 (onde a volta conta): faixa xadrez em peças de
-- chão lado a lado (cada uma na altura do chão, para não flutuar na rampa),
-- o arco por cima e uma bandeira de cada lado.
local XADREZ = 8 -- peças na largura; com 4 casas cada, o xadrez emenda
local ARCO_LARGURA = 1.866 -- vão do portal_largada.glb em metros (eixo X)

local function peca(arquivo: string, x: number, z: number, y_extra: number, giro: number, escala: vector,
    chata: boolean?)
    local y = world.ground_height(x, z)
    if chata then
        -- O chão desenhado não bate com ground_height no meio das amostras:
        -- a peça chata vai na altura do canto mais alto, senão afunda.
        local r = escala.x * 0.5
        for _, c in { { -r, -r }, { r, -r }, { r, r }, { -r, r } } do
            y = math.max(y, world.ground_height(x + c[1], z + c[2]))
        end
    end
    local o = objects.spawn(arquivo, vector.create(x, y + y_extra, z))
    if o then
        o.rotation = vector.create(0, giro, 0)
        o.scale = escala
    end
end

local function montar_largada()
    local p = PISTA.ponto(0)
    if not p then
        return
    end
    local tx, tz = p.tangent.x, p.tangent.z
    -- Com este giro o eixo X da peça fica atravessado na pista.
    local giro = math.deg(math.atan2(tx, tz))
    -- Duas fileiras: com uma só (6,5 m), da câmera baixa a faixa virava um fio.
    local lado = p.width / XADREZ
    for fila = -1, 0 do
        local f = (fila + 0.5) * lado
        for k = 0, XADREZ - 1 do
            local d = (k + 0.5) * lado - p.width * 0.5
            peca("assets/props/linha_chegada.glb", p.position.x + tz * d + tx * f, p.position.z - tx * d + tz * f,
                0.15, giro, vector.create(lado, 1, lado), true)
        end
    end
    local vao = p.width + 16
    local s = vao / ARCO_LARGURA
    -- Arco fino (0,33 m de peça -> 3 m) e alto (~30 m): grosso como o vão, a
    -- câmera atrás do carro atravessava 12 m de pedra.
    peca("assets/props/portal_largada.glb", p.position.x, p.position.z, 0, giro, vector.create(s, s * 0.9, 9))
    for _, sinal in { -1, 1 } do
        local d = (p.width * 0.5 + 12) * sinal
        peca("assets/props/bandeira_chegada.glb", p.position.x + tz * d, p.position.z - tx * d, 0, giro,
            vector.create(12, 12, 12))
    end
end

local function montar_pista()
    local pontos, ficha = TRACADO.pontos(world.map())
    if not pontos then
        return
    end
    world.ribbon(PISTA.nome, pontos, { closed = true, width = ficha.largura, step = 4, lift = 0.2 })
    local comprimento = world.ribbon_length(PISTA.nome)
    local passos = math.floor(comprimento / 22)
    for k = 0, (if TESTE.sem_barreira then 0 else passos) - 1 do
        local p = PISTA.ponto(k / passos)
        if p then
            local tx, tz = p.tangent.x, p.tangent.z
            for _, lado in { -1, 1 } do
                local d = (p.width * 0.5 + 4) * lado
                local x, z = p.position.x + tz * d, p.position.z - tx * d
                local o = objects.spawn("assets/props/barreira.glb", vector.create(x, world.ground_height(x, z), z))
                if o then
                    -- As peças CC0 vêm em metro; o mapa mede o carro em ~9 unidades.
                    -- O comprimento da peça é o eixo X dela: +90° deita ao longo da pista.
                    o.rotation = vector.create(0, math.deg(math.atan2(tx, tz)) + 90, 0)
                    o.scale = vector.create(ESCALA_PECA, ESCALA_PECA, ESCALA_PECA)
                end
            end
        end
    end
    montar_largada()
    ui.message(ficha.titulo, 4)
    SOM.iniciar(ficha.musica)
end

-- Grid na ordem que o campeonato pede (pole primeiro): cada piloto mantém o
-- carro e a cor do campeonato inteiro.
local function montar_grid()
    local grid = CAMP.grid()
    local meu = 1
    for k, piloto in grid do
        -- Duas filas atrás da linha de chegada; k = 1 é a pole.
        local t = 1 - 0.004 * (k + 1)
        local p = PISTA.ponto(t)
        local x, z, yaw = 0, -10 * k, 0
        if p then
            local lado = if k % 2 == 0 then 0.25 else -0.25
            local tx, tz = p.tangent.x, p.tangent.z
            x = p.position.x + tz * lado * p.width
            z = p.position.z - tx * lado * p.width
            yaw = math.deg(math.atan2(tx, tz))
        end
        local pl = CAMP.pilotos[piloto]
        local i = CORPOS.adicionar(C, "carro_" .. k, x, z, yaw, FICHAS[pl.modelo])
        C.t[i] = t
        piloto_de[i] = piloto
        dono_de[i] = if pl.dono and pl.dono ~= 0 then pl.dono else nil
        cores[i] = pl.cor
        rotulos[i] = pl.rotulo
        local sprite = string.format("assets/sprites/carros/carro_%d_%s.png", pl.modelo, pl.cor)
        VISUAL.criar(C, i, sprite)
        retratos[i] = { VISUAL.retrato(sprite) }
        retrato_piloto[piloto] = retratos[i]
        if pl.jogador then
            meu = i
        end
    end
    return meu
end

-- Troca de pista (e a largada saindo do menu): som em fade, cena escurece e
-- o aviso aparece; só depois world.load_map / montar a corrida, que param o
-- quadro até a pista estar montada. Assim a tela
-- congela já escura e calada, e a corrida nova clareia (iniciar_corrida).
local SAIDA = 0.6 -- s do fade antes de carregar
local saida = 0
local function trocar_mapa(m: string)
    alvo, estado, saida = m, "saindo", SAIDA
    SOM.calar(SAIDA * 0.8)
    fx.dim(vector.create(0, 0, 0), 1, SAIDA * 0.8)
    for _, aviso in { "#rk-dica", "#sala-estado", "#menu-dica" } do
        if ui.has(aviso) then
            ui.text(aviso, if m == world.map() then "montando a largada…" else "carregando a próxima pista…")
        end
    end
end

local function iniciar_corrida()
    fx.dim(nil, 0, 0.5)
    -- Analógico e botões de toque só na corrida (menu e quadro são de tocar).
    input.touch_pad(input.touch())
    C = CORPOS.novo(16)
    acumulado, relogio = 0, 0
    CORRIDA.voltas = TESTE.voltas or CAMP.VOLTAS
    piloto_de, dono_de = {}, {}
    fim_pedido, largou, espera_prontos = false, not REDE.em_rede(), 0
    montar_pista()
    CENARIO.fumarolas()
    local meu = montar_grid()
    PISO.ler_fontes()
    REDE.receber_em(C)
    REDE.pronto(CAMP.etapa)
    eu = meu
    VISUAL.foco = eu
    HUD.iniciar(C, rotulos, cores, retratos)
    CAMERA.iniciar(C.px[eu], C.py[eu], C.pz[eu], C.yaw[eu])
    estado = "corrida"
end

on.start(function()
    characters.set_shadow("lights")
    CENARIO.look()
    -- O "jogador" do motor não aparece nem anda: ele acompanha o carro, para
    -- o LOD, a sombra e o streaming do motor centrarem onde a ação está.
    player.hide(true)
    player.freeze(true)
    if TESTE.sala == "digitar" then
        SALA.abrir_convidado(2)
        estado = "sala"
    elseif TESTE.sala then
        -- Teste da sala com dois motores na mesma máquina (o net confere que
        -- os scripts são iguais, então o teste_config também): o primeiro
        -- abre a sala; o segundo não consegue a porta e entra nela.
        SALA.abrir_anfitriao(1)
        if REDE.papel ~= "anfitriao" then
            SALA.abrir_convidado(2)
            SALA.conectar(TESTE.ip or "127.0.0.1")
        end
        estado = "sala"
    elseif TESTE.auto then
        CAMP.novo(CARROS, 1, FICHAS, CORES)
        -- O teste corre a etapa do mapa aberto.
        for k, nome in CAMP.PISTAS do
            if nome == world.map() then
                CAMP.etapa = k
            end
        end
        iniciar_corrida()
    else
        MENU.abrir(FICHAS, CORES[(CARROS - 1) % #CORES + 1])
    end
end)

local PARADO = { steer = 0, throttle = 0, brake = true, turbo = false }
local minha = PARADO

-- Entrada de quem dirige o corpo i (sozinho ou no anfitrião). Depois da
-- bandeira ninguém para no meio da pista: quem chegou (humano também) segue
-- no piloto automático enquanto a classificação aparece.
local function entrada_de(i: number)
    if C.chegou[i] == 0 then
        if i == eu then
            return minha
        end
        local dono = dono_de[i]
        if dono then
            -- Humano de outra máquina; sem notícia dele (caiu), o carro para.
            return REDE.entrada_de(dono) or PARADO
        end
    end
    return IA.entrada(C, i, NIVEL[(i - 1) % #NIVEL + 1])
end

-- Anfitrião: o relógio só anda quando todos os humanos montaram a pista
-- (ou depois de 30 s, para quem caiu na carga não prender a sala).
local function todos_montaram(): boolean
    if largou then
        return true
    end
    local donos = {}
    for i = 1, C.n do
        if dono_de[i] then
            donos[#donos + 1] = dono_de[i]
        end
    end
    espera_prontos += PASSO
    largou = REDE.todos_prontos(donos, CAMP.etapa) or espera_prontos > 30
    return largou
end

local function passo_fixo()
    minha = if TESTE.auto then IA.entrada(C, eu, 3) else entrada_jogador()
    if not todos_montaram() then
        return
    end
    relogio += PASSO
    local correndo = relogio > largada
    PISO.amostrar(C)
    for i = 1, C.n do
        local e = if correndo then entrada_de(i) else PARADO
        local t_antes = C.t[i]
        FISICA.passo(C, i, e, PASSO)
        if correndo then
            CORRIDA.contar(C, i, t_antes, PASSO, relogio)
        end
    end
    PISO.agir(C, PASSO)
    FISICA.colisoes(C)
    REDE.publicar(C, relogio)
end

-- Simulação, desenho, câmera e som: roda na corrida e atrás do ranking (os
-- carros seguem andando enquanto os pontos aparecem).
local function simular(dt: number)
    local a
    if REDE.simulo() then
        acumulado = math.min(acumulado + dt, 0.25) -- engasgo longo não vira avalanche de passos
        while acumulado >= PASSO do
            passo_fixo()
            acumulado -= PASSO
        end
        a = acumulado / PASSO
    else
        -- Convidado: manda o volante e desenha o que o anfitrião mandou.
        minha = if TESTE.auto then IA.entrada(C, eu, 3) else entrada_jogador()
        REDE.enviar(minha)
        relogio = REDE.relogio()
        PISO.amostrar(C)
        a = REDE.fracao(dt)
    end
    SOM.atualizar(C, eu, minha, largada - relogio, relogio)
    VISUAL.desenhar(C, a, dt)
    player.set_position(vector.create(C.px[eu], C.py[eu], C.pz[eu]))
    CAMERA.seguir(C.px[eu], C.py[eu], C.pz[eu], C.yaw[eu], C.vel[eu], dt)
end

-- Fecha a etapa: chegada pela colocação (quem não cruzou fica pela distância
-- percorrida), pontos no campeonato e o quadro de pontos.
-- `chegada[pos] = piloto`: em rede vem do anfitrião, para todos pontuarem igual.
local function chegada_agora()
    local chegada = {}
    for pos, i in CORRIDA.colocar(C) do
        chegada[pos] = piloto_de[i]
    end
    return chegada
end

local function fechar_etapa(chegada)
    input.touch_pad(false)
    local ganho = CAMP.pontuar(chegada)
    local ficha = TRACADO.pistas[CAMP.pista()]
    local titulo, sub
    if CAMP.ultima() then
        local campeao = CAMP.pilotos[CAMP.classificacao()[1]]
        titulo = if campeao.jogador then "VOCÊ É O CAMPEÃO!" else "CAMPEÃO: " .. campeao.nome
        sub = string.format("fim do campeonato — %d pistas", #CAMP.PISTAS)
    else
        titulo = string.format("ETAPA %d/%d", CAMP.etapa, #CAMP.PISTAS)
        sub = if ficha then ficha.titulo else CAMP.pista()
    end
    if TESTE.auto then
        local meu = 0
        for pos, k in chegada do
            if CAMP.pilotos[k].jogador then
                meu = pos
            end
        end
        log(string.format("ETAPA %d %s pos=%d pontos=%d", CAMP.etapa, CAMP.pista(), meu,
            CAMP.pilotos[#CAMP.pilotos].pontos))
    end
    RANKING.abrir(CAMP, chegada, ganho, retrato_piloto, titulo, sub, CAMP.ultima())
    estado = "ranking"
end

-- Etapa `n` (todos ao mesmo tempo, em rede).
local function ir_para_etapa(n: number)
    CAMP.etapa = n
    trocar_mapa(CAMP.pista())
end

-- Falso enquanto a próxima pista não existe: no navegador as pistas 2..5
-- descem com o jogo rodando, e na rede lenta o jogador pode fechar a 1ª
-- etapa antes. world.preload_map dá falso para mapa que não está lá (e,
-- quando está, já adianta a leitura).
local function proxima_etapa(): boolean
    if REDE.em_rede() then
        -- Só o anfitrião chega aqui; o anúncio volta para ele também.
        if CAMP.ultima() then
            REDE.anunciar("acabou", {})
        else
            REDE.anunciar("etapa", { n = CAMP.etapa + 1 })
        end
        return true
    end
    if CAMP.ultima() then
        game.restart() -- de volta ao menu, tudo limpo
        return true
    end
    if not world.preload_map(CAMP.PISTAS[CAMP.etapa + 1]) then
        return false
    end
    CAMP.avancar()
    trocar_mapa(CAMP.pista())
    return true
end

local function quadro_corrida(dt: number)
    -- No navegador o toque só se revela no primeiro dedo: o painel acompanha.
    input.touch_pad(input.touch())
    simular(dt)
    local ordem = CORRIDA.colocar(C)
    HUD.atualizar(C, eu, CORRIDA.voltas, ordem, dt)
    if relogio < largada then
        HUD.contagem(tostring(math.ceil(largada - relogio)))
    end
    if not largou and REDE.papel == "anfitriao" then
        HUD.contagem("…")
    end
    if REDE.papel == "convidado" and not REDE.conectado() then
        ui.message("a sala fechou", 4)
        REDE.sair()
        game.restart()
        return
    end
    -- A etapa acaba quando todos cruzaram, ou quando o jogador cruzou e pede
    -- (em rede: quando os humanos cruzaram e quem abriu a sala pede).
    local todos, humanos = true, true
    for i = 1, C.n do
        if C.chegou[i] == 0 then
            todos = false
            if dono_de[i] or i == eu then
                humanos = false
            end
        end
    end
    if REDE.papel == "anfitriao" then
        local pede = input.pressed("enter") or input.pressed("pad_a") or input.pressed("escape")
        if not fim_pedido and (todos or (humanos and pede)) then
            fim_pedido = true
            local chegada = chegada_agora()
            local dados = {}
            for pos, k in chegada do
                dados[pos] = k
            end
            REDE.anunciar("fim", dados)
        end
    elseif REDE.papel == "sozinho" and C.chegou[eu] > 0 then
        if TESTE.auto and not TESTE._dito then
            TESTE._dito = true
            log(string.format("VOLTAS %d OK melhor=%.2f pos=%d", C.volta[eu], C.t_melhor[eu], C.colocacao[eu]))
        end
        local pede = input.pressed("enter") or input.pressed("pad_a") or input.pressed("escape")
        if todos or pede then
            fechar_etapa(chegada_agora())
        end
    end
end

local function carregar_etapa()
    trocar_mapa(CAMP.pista())
end

-- Anfitrião larga: o carro de cada um que está na sala, em ordem de id.
local function anunciar_campeonato()
    local js = REDE.jogadores()
    table.sort(js, function(a, b)
        return a.id < b.id
    end)
    local dados = {}
    for k, j in js do
        if k <= REDE.MAX then
            dados[k] = string.format("%d,%d", REDE.carros[j.id] or modelo_menu, j.id)
        end
    end
    REDE.anunciar("camp", dados)
end

-- Anúncios do anfitrião: chegam a todos, ele incluído.
REDE.quando.camp = function(d)
    if estado ~= "sala" or type(d) ~= "table" then
        return
    end
    local humanos = {}
    for k = 1, REDE.MAX do
        local m, dono = string.match(tostring(d[k] or ""), "^(%d+),(%d+)$")
        if m then
            humanos[#humanos + 1] = { modelo = tonumber(m), dono = tonumber(dono), nome = "J" .. k }
        end
    end
    if #humanos > 0 then
        CAMP.novo_sala(math.max(CARROS, #humanos), humanos, REDE.meu(), FICHAS, CORES)
        ir_para_etapa(1)
    end
end

REDE.quando.etapa = function(d)
    if type(d) == "table" and type(d.n) == "number" and estado == "ranking" then
        ir_para_etapa(d.n)
    end
end

REDE.quando.fim = function(d)
    if estado ~= "corrida" or type(d) ~= "table" then
        return
    end
    local chegada = {}
    for pos = 1, #CAMP.pilotos do
        if type(d[pos]) == "number" then
            chegada[#chegada + 1] = d[pos]
        end
    end
    fechar_etapa(chegada)
end

REDE.quando.acabou = function()
    REDE.sair()
    game.restart()
end

REDE.quando.entrou = function()
    SALA.entrou()
end

REDE.quando.falhou = function(motivo)
    if estado == "sala" then
        SALA.falhou(motivo)
    else
        ui.message("a sala caiu: " .. tostring(motivo), 4)
        REDE.sair()
        game.restart()
    end
end

on.update(function(dt)
    if estado == "menu" then
        local modelo, modo = MENU.atualizar(FICHAS, dt)
        if modelo then
            modelo_menu = modelo
            if modo == "criar" then
                SALA.abrir_anfitriao(modelo)
                estado = "sala"
            elseif modo == "entrar" then
                SALA.abrir_convidado(modelo)
                estado = "sala"
            else
                CAMP.novo(CARROS, modelo, FICHAS, CORES)
                carregar_etapa()
            end
        end
    elseif estado == "sala" then
        local r = SALA.atualizar(dt)
        if TESTE.sala and REDE.papel == "anfitriao" and #REDE.jogadores() >= (TESTE.humanos or 2) then
            r = "largar"
        end
        if r == "voltar" then
            MENU.abrir(FICHAS, CORES[(CARROS - 1) % #CORES + 1])
            estado = "menu"
        elseif r == "largar" then
            anunciar_campeonato()
        end
    elseif estado == "saindo" then
        -- Espera o fade e um quadro já com o aviso na tela.
        saida -= dt
        if saida <= 0 then
            -- Na mesma pista (a 1ª, onde fica o menu) não há mapa a carregar,
            -- mas montar o grid e a pista também para o quadro.
            if alvo == world.map() then
                iniciar_corrida()
            else
                estado = "carregando"
                world.load_map(alvo)
            end
        end
    elseif estado == "carregando" then
        if world.map() == alvo and not world.warping() then
            iniciar_corrida()
        end
    elseif estado == "ranking" then
        simular(dt)
        if RANKING.atualizar(dt, TESTE.campeonato) and REDE.papel ~= "convidado" then
            seguir, espera = true, 0
        end
        if REDE.papel == "convidado" then
            ui.text("#rk-dica", "esperando quem abriu a sala seguir")
        end
        if seguir then
            espera -= dt
            if espera <= 0 then
                espera = 1
                if proxima_etapa() then
                    seguir = false
                end
            end
            if seguir then
                ui.text("#rk-dica", "baixando a próxima pista…")
            end
        end
    else
        quadro_corrida(dt)
    end
end)
