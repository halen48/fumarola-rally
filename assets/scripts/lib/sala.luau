-- Tela da sala (sala.css). Quem abre vê o endereço para passar aos outros e
-- quem já entrou; Enter/OK larga. Quem entra digita o IP (teclas numéricas,
-- espaço = ponto, ou o teclado da tela) e espera o anfitrião largar.
-- Devolve "voltar" ou "largar" de M.atualizar; o resto chega pela rede.
local REDE = require("lib/rede")

local M = {}

local modo = "" -- "anfitriao" | "digitar" | "conectando" | "esperando" | "erro"
local ip = ""
local aviso = ""

local TECLAS = { "1", "2", "3", "4", "5", "6", "7", "8", "9", "0" }

local function teclado(visivel: boolean)
    for _, k in TECLAS do
        ui.visible("#sala-k" .. k, visivel)
        ui.visible("#sala-k" .. k .. "-t", visivel)
    end
    for _, k in { "#sala-kp", "#sala-kx" } do
        ui.visible(k, visivel)
        ui.visible(k .. "-t", visivel)
    end
end

local function lista()
    local js = REDE.jogadores()
    for k = 1, REDE.MAX do
        local j = js[k]
        ui.text("#sala-j" .. k, if j then string.format("%d. %s", k, j.name) else "")
    end
    return #js
end

local function abrir_tela()
    ui.load("assets/ui/sala.css")
    for k = 1, REDE.MAX do
        ui.text("#sala-j" .. k, "")
    end
end

-- Abre a sala com o carro `modelo`. Sem rede (navegador) mostra o porquê.
function M.abrir_anfitriao(modelo: number)
    abrir_tela()
    teclado(false)
    local endereco, motivo = REDE.hospedar(modelo)
    if not endereco then
        modo = "erro"
        ui.text("#sala-titulo", "SALA")
        ui.text("#sala-rotulo", "não deu para abrir a sala")
        ui.text("#sala-ip", "")
        ui.text("#sala-estado", tostring(motivo or "sem rede neste aparelho") .. " (no navegador, abra a sala no PC e entre por aqui)")
        ui.visible("#sala-ok", false)
        ui.visible("#sala-ok-t", false)
        ui.text("#sala-dica", "Esc: voltar")
        return
    end
    modo = "anfitriao"
    ui.text("#sala-titulo", "SALA ABERTA")
    ui.text("#sala-rotulo", "os outros digitam este endereço")
    ui.text("#sala-ip", endereco)
    ui.text("#sala-ok-t", "LARGAR")
    ui.text("#sala-dica", "Enter / OK: largar com quem entrou      Esc: fechar a sala")
end

function M.abrir_convidado(modelo: number)
    abrir_tela()
    teclado(true)
    modo, ip, aviso = "digitar", "", ""
    M.modelo = modelo
    ui.text("#sala-titulo", "ENTRAR NA SALA")
    ui.text("#sala-rotulo", "IP de quem abriu a sala")
    ui.text("#sala-dica", "números e espaço (ponto)      Enter / OK: entrar      Esc: voltar")
end

-- Chamados pela rede (main.luau liga em REDE.quando).
function M.entrou()
    modo = "esperando"
end

function M.falhou(motivo: string)
    REDE.sair()
    modo, aviso = "digitar", "não entrou: " .. tostring(motivo)
    teclado(true)
end

function M.conectar(endereco: string)
    ip = endereco
    if REDE.entrar(ip, M.modelo) then
        modo, aviso = "conectando", ""
        teclado(false)
    else
        REDE.sair()
        aviso = "endereço inválido"
    end
end

local function digitar()
    for _, k in TECLAS do
        if input.pressed(k) or ui.clicked("#sala-k" .. k) then
            ip ..= k
        end
    end
    if input.pressed("space") or ui.clicked("#sala-kp") then
        ip ..= "."
    end
    if (input.pressed("backspace") or ui.clicked("#sala-kx")) and #ip > 0 then
        ip = string.sub(ip, 1, -2)
    end
    ip = string.sub(ip, 1, 21)
    ui.text("#sala-ip", if ip == "" then "_" else ip)
    ui.text("#sala-estado", aviso)
    if (input.pressed("enter") or input.pressed("pad_a") or ui.clicked("#sala-ok")) and #ip >= 7 then
        M.conectar(ip)
    end
end

function M.atualizar(dt: number)
    local volta = input.pressed("escape") or input.pressed("pad_b") or ui.clicked("#sala-volta")
    if volta then
        REDE.sair()
        return "voltar"
    end
    if modo == "digitar" then
        digitar()
    elseif modo == "conectando" then
        ui.text("#sala-estado", "conectando a " .. ip .. "…")
    elseif modo == "esperando" then
        local n = lista()
        ui.text("#sala-titulo", "NA SALA")
        ui.text("#sala-estado", string.format("%d na sala — esperando quem abriu largar", n))
        ui.visible("#sala-ok", false)
        ui.visible("#sala-ok-t", false)
        ui.text("#sala-dica", "Esc: sair da sala")
    elseif modo == "anfitriao" then
        -- Com relay o endereço chega depois.
        local endereco = REDE.endereco()
        if endereco ~= "" then
            ui.text("#sala-ip", endereco)
        end
        local n = lista()
        ui.text("#sala-estado", if n <= 1 then "esperando os outros entrarem" else string.format("%d na sala", n))
        if input.pressed("enter") or input.pressed("pad_a") or ui.clicked("#sala-ok") then
            return "largar"
        end
    end
    return nil
end

return M
