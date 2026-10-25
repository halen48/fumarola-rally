-- Corrida em rede: sala por IP com o net.* do motor (eventos confiáveis e em
-- ordem). O anfitrião simula a corrida inteira, IA inclusive; cada convidado
-- só manda o próprio volante e desenha o que o anfitrião manda, 20 vezes por
-- segundo, nas MESMAS colunas de C. Desenho, HUD e som não sabem se a
-- partida é local ou em rede.
--
-- As decisões (campeonato montado, etapa, chegada, fim) saem do anfitrião
-- com net.send, que chega a todos, ele mesmo incluído: cada máquina age no
-- mesmo tratador, na mesma ordem. Sem o módulo de rede `papel` fica
-- "sozinho" e nada daqui roda.
local M = {}

-- No navegador não há UDP: net.host falha e net.join entra pela ponte
-- WebSocket do PC que abriu a sala. O jogo não precisa saber onde roda.
local net = (_G :: any).net

M.VERSAO = "fumarola-1"
M.PORTA = 41920
M.MAX = 4 -- humanos na sala
M.papel = "sozinho" -- "sozinho" | "anfitriao" | "convidado"
-- Tratadores do jogo (main.luau): camp, etapa, fim, acabou (decisões do
-- anfitrião) e entrou, chegou, saiu, falhou (a sala).
M.quando = {}
M.carros = {} -- [dono] = modelo escolhido (no anfitrião; [0] no convidado)

local entradas = {} -- [dono] = entrada mais recente (no anfitrião)
local prontos = {} -- [dono] = etapa que ele já carregou (no anfitrião)
local marca_batida = {} -- [i] = bateu desde o último envio
local passos = 0
local desde = 0 -- s desde o último estado (no convidado)

-- 12 floats + 4 bytes por carro: px py pz yaw vel lat giro t t_volta
-- t_melhor chegou calor | turbo (0..255) volta superaq turbo_on+2*batida.
local FORMATO = "<ffffffffffffBBBB"
local ENVIO = 3 -- passos de 1/60 s entre estados: 20 por segundo

function M.disponivel(): boolean
    return net ~= nil
end

function M.em_rede(): boolean
    return M.papel ~= "sozinho"
end

-- Id deste jogador na sala (0 sozinho).
function M.meu(): number
    return if M.em_rede() then net.my_id() else 0
end

function M.jogadores()
    return if net then net.players() else {}
end

-- Abre a sala. Devolve "ip:porta" para os outros digitarem, ou nil e o motivo.
function M.hospedar(modelo: number)
    local endereco, motivo = net.host({ max_players = M.MAX, port = M.PORTA, name = "Anfitrião", version = M.VERSAO })
    if not endereco then
        return nil, motivo
    end
    M.papel = "anfitriao"
    M.carros = { [net.my_id()] = modelo }
    return endereco
end

function M.endereco(): string
    return if net then net.address() else ""
end

-- Entra na sala de `ip` (com ou sem ":porta"). A resposta chega em
-- M.quando.entrou / M.quando.falhou.
function M.entrar(ip: string, modelo: number): boolean
    M.papel = "convidado"
    M.carros = { [0] = modelo }
    return net.join(ip, { name = "Convidado", version = M.VERSAO })
end

-- Ainda ligado à sala (o convidado perde o anfitrião: volta ao menu).
function M.conectado(): boolean
    return net ~= nil and net.state() ~= "offline"
end

-- Convidado avisa que a pista da etapa `n` já está montada.
function M.pronto(n: number)
    if M.papel == "convidado" then
        net.ask("pronto", { e = n })
    end
end

-- Anfitrião: todos os humanos em `donos` já montaram a etapa `n`.
function M.todos_prontos(donos, n: number): boolean
    for _, d in donos do
        if d ~= net.my_id() and (prontos[d] or 0) < n then
            return false
        end
    end
    return true
end

function M.sair()
    if net and M.em_rede() then
        net.leave()
    end
    M.papel = "sozinho"
end

-- Convidado: o volante vai para o anfitrião quando muda, e a cada 1/20 s
-- mesmo parado.
local ultima, repete = "", 0
function M.enviar(e)
    if M.papel ~= "convidado" then
        return
    end
    local s = string.format("%d%d%d%d", e.steer + 1, e.throttle, if e.brake then 1 else 0, if e.turbo then 1 else 0)
    repete += 1
    if s ~= ultima or repete >= ENVIO then
        ultima, repete = s, 0
        net.ask("entrada", { v = s })
    end
end

-- Entrada do humano dono do corpo, no anfitrião (nil: ainda não chegou).
function M.entrada_de(dono: number)
    return entradas[dono]
end

-- Quem simula: sozinho e o anfitrião, tudo; o convidado, nada.
function M.simulo(): boolean
    return M.papel ~= "convidado"
end

-- Anfitrião, depois de cada passo fixo: guarda as batidas e, a cada ENVIO
-- passos, manda o estado de todos os carros.
function M.publicar(C, relogio: number)
    if M.papel ~= "anfitriao" then
        return
    end
    for i = 1, C.n do
        if C.batida[i] == 1 then
            marca_batida[i] = true
        end
    end
    passos += 1
    if passos < ENVIO then
        return
    end
    passos = 0
    local dados = { r = relogio }
    for i = 1, C.n do
        dados[i] = string.pack(FORMATO, C.px[i], C.py[i], C.pz[i], C.yaw[i], C.vel[i], C.lat[i], C.giro[i], C.t[i],
            C.t_volta[i], C.t_melhor[i], C.chegou[i], C.calor[i],
            math.clamp(math.floor(C.turbo[i] * 255 + 0.5), 0, 255), C.volta[i], C.superaq[i],
            C.turbo_on[i] + (if marca_batida[i] then 2 else 0))
        marca_batida[i] = nil
    end
    net.send("estado", dados)
end

-- Convidado: fração entre o estado anterior e o último, para o desenho
-- interpolar como interpola entre passos fixos.
function M.fracao(dt: number): number
    desde += dt
    return math.clamp(desde / (ENVIO / 60), 0, 1)
end

local C_rede = nil -- colunas que recebem o estado (main.luau aponta)
local relogio_rede = 0

function M.receber_em(C)
    C_rede = C
end

-- Relógio da corrida do anfitrião (o convidado conta a largada por ele).
function M.relogio(): number
    return relogio_rede
end

local function aplicar(dados)
    local C = C_rede
    if not C then
        return
    end
    relogio_rede = dados.r or relogio_rede
    local tamanho = string.packsize(FORMATO)
    for i = 1, C.n do
        local s = dados[i]
        if type(s) == "string" and #s == tamanho then
            C.ax[i], C.az[i], C.ayaw[i] = C.px[i], C.pz[i], C.yaw[i]
            local px, py, pz, yaw, vel, lat, giro, t, t_volta, t_melhor, chegou, calor, turbo, volta, superaq, flags =
                string.unpack(FORMATO, s)
            C.px[i], C.py[i], C.pz[i], C.yaw[i] = px, py, pz, yaw
            C.vel[i], C.lat[i], C.giro[i], C.t[i] = vel, lat, giro, t
            C.t_volta[i], C.t_melhor[i], C.chegou[i], C.calor[i] = t_volta, t_melhor, chegou, calor
            C.turbo[i], C.volta[i], C.superaq[i] = turbo / 255, volta, superaq
            C.turbo_on[i] = flags % 2
            if flags >= 2 then
                C.batida[i] = 1
            end
        end
    end
    desde = 0
end

-- Decisões do anfitrião, para todos (ele incluído).
function M.anunciar(nome: string, dados)
    if M.papel == "anfitriao" then
        net.send(nome, dados)
    end
end

-- Tratadores: no topo do script, como on.*.
if net then
    net.on("carro", function(from, d)
        if M.papel == "anfitriao" and type(d) == "table" and type(d.m) == "number" then
            M.carros[from] = math.clamp(math.floor(d.m), 1, 4)
        end
    end, { from_client = true, max_bytes = 64 })
    net.on("pronto", function(from, d)
        if M.papel == "anfitriao" and type(d) == "table" and type(d.e) == "number" then
            prontos[from] = d.e
        end
    end, { from_client = true, max_bytes = 64 })
    net.on("entrada", function(from, d)
        local s = if type(d) == "table" then d.v else nil
        if M.papel ~= "anfitriao" or type(s) ~= "string" or #s ~= 4 then
            return
        end
        local a, b, c, e = string.byte(s, 1, 4)
        entradas[from] = {
            steer = math.clamp(a - 49, -1, 1), -- "0".."2" -> -1..1
            throttle = if b == 49 then 1 else 0,
            brake = c == 49,
            turbo = e == 49,
        }
    end, { from_client = true, max_bytes = 64 })
    net.on("estado", function(_, d)
        if M.papel == "convidado" and type(d) == "table" then
            aplicar(d)
        end
    end)
    for _, nome in { "camp", "etapa", "fim", "acabou" } do
        net.on(nome, function(_, d)
            local f = M.quando[nome]
            if f and M.em_rede() then
                f(d)
            end
        end)
    end
    net.on_join(function(id, nome)
        if M.papel == "convidado" and id == net.my_id() then
            net.ask("carro", { m = M.carros[0] })
            if M.quando.entrou then
                M.quando.entrou()
            end
        end
        if M.quando.chegou then
            M.quando.chegou(id, nome)
        end
    end)
    net.on_leave(function(id, motivo)
        entradas[id], prontos[id] = nil, nil
        if M.quando.saiu then
            M.quando.saiu(id, motivo)
        end
    end)
    net.on_fail(function(motivo)
        if M.quando.falhou then
            M.quando.falhou(motivo)
        end
    end)
end

return M
