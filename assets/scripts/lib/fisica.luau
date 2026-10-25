-- Física arcade de um corpo, um passo fixo. Função pura sobre as colunas:
-- mesma entrada, mesmo resultado. A rede (net.sync_table) chama este mesmo
-- passo no servidor e na re-simulação do cliente; por isso nada aqui lê
-- relógio, sorteio nem estado fora de C.
--
-- `e`: entrada do quadro { steer = -1..1, throttle = 0..1, brake = bool, turbo = bool }
local PISTA = require("lib/pista")

local M = {}

M.VMAX = 82 -- igual ao VMAX abaixo: IA, câmera, visual e HUD medem por ele

-- Mais rápido que a primeira versão (VMAX 62, ACEL 38): o autor pediu
-- velocidade de Top Gear; a pista foi alargada para 52 junto.
local ACEL = 50          -- u/s² com potência 1
local FREIO = 90
local VMAX = 82
local GIRO = 135         -- graus/s no máximo
local CALOR_DISSIPA = 12 -- graus/s perdidos
local CALOR_TURBO = 30
local SUPERAQ_LIGA, SUPERAQ_DESLIGA = 100, 55
local MURO = 6           -- quanto além da borda o corpo pode ir

function M.passo(C, i: number, e, dt: number)
    C.ax[i], C.az[i], C.ayaw[i] = C.px[i], C.pz[i], C.yaw[i]

    -- Qualidade de tração: a do pneu (o que o carro tem) × a do piso (o que
    -- o chão tem). Nenhum dos dois sabe o nome do outro.
    local grip = C.pneu[i] * C.piso_ader[i]

    -- Posse: o turbo é carga que se gasta; gastar aquece.
    local turbo = e.turbo and C.turbo[i] > 0
    C.turbo_on[i] = if turbo then 1 else 0
    if turbo then
        C.turbo[i] = math.max(0, C.turbo[i] - 0.5 * dt)
    else
        C.turbo[i] = math.min(1, C.turbo[i] + 0.08 * dt)
    end

    -- Paixão: sofrer calor. Quem passa do limite perde potência até esfriar.
    local calor = C.calor[i] + (C.piso_calor[i] * C.sofre_calor[i]
        + (if turbo then CALOR_TURBO else 0) - CALOR_DISSIPA) * dt
    calor = math.max(0, calor)
    C.calor[i] = calor
    if calor > SUPERAQ_LIGA then
        C.superaq[i] = 1
    elseif calor < SUPERAQ_DESLIGA then
        C.superaq[i] = 0
    end
    local potencia = C.potencia[i] * (if C.superaq[i] == 1 then 0.55 else 1) * (if turbo then 1.4 else 1)

    local vel = C.vel[i]
    vel += e.throttle * ACEL * potencia * (0.5 + 0.5 * grip) * dt
    if e.brake then
        vel -= FREIO * grip * dt
    end
    vel -= vel * C.piso_arrasto[i] * dt
    vel = math.clamp(vel, -10, VMAX * (if turbo then 1.25 else 1))

    -- Curva cresce com a velocidade até 15 u/s; tração baixa curva menos e
    -- deriva mais (a deriva lateral é o "drift").
    local giro = e.steer * GIRO * math.min(1, math.abs(vel) / 15) * (0.6 + 0.4 * grip)
    local yaw = C.yaw[i] + giro * dt
    C.giro[i] = giro
    local lat = C.lat[i] + e.steer * vel * 0.02 * (1 - grip) - C.lat[i] * 4 * grip * dt

    local r = math.rad(yaw)
    local fx, fz = math.sin(r), math.cos(r)
    local x = C.px[i] + (fx * vel + fz * lat) * dt
    local z = C.pz[i] + (fz * vel - fx * lat) * dt

    -- Lugar na pista e borda: fora da faixa arrasta, além do muro volta.
    local q = PISTA.consulta(x, z)
    if q then
        C.t[i], C.s[i], C.borda[i] = q.t, q.s, q.edge
        if q.edge < -MURO then
            local volta = -q.edge - MURO
            x += q.normal.x * volta
            z += q.normal.z * volta
            if math.abs(vel) > 12 then
                C.batida[i] = 1
            end
            vel *= 0.6
            lat = 0
        elseif q.edge < 0 then
            vel -= vel * 0.8 * dt
        end
        C.py[i] = q.height
    else
        C.py[i] = world.ground_height(x, z)
    end

    C.px[i], C.pz[i], C.yaw[i], C.vel[i], C.lat[i] = x, z, yaw, vel, lat
end

-- Corpos se empurram: círculos, O(n²) com n ≤ 16. Quem sofre mais empurrão
-- (menos massa) recua mais; quem vem atrás é quem freia.
function M.colisoes(C)
    local px, pz, raio, se = C.px, C.pz, C.raio, C.sofre_empurrao
    for i = 1, C.n - 1 do
        for j = i + 1, C.n do
            local dx, dz = px[j] - px[i], pz[j] - pz[i]
            local rr = raio[i] + raio[j]
            local d2 = dx * dx + dz * dz
            if d2 < rr * rr and d2 > 1e-6 then
                local d = math.sqrt(d2)
                local sobra = (rr - d) / (d * (se[i] + se[j]))
                px[i] -= dx * sobra * se[i]
                pz[i] -= dz * sobra * se[i]
                px[j] += dx * sobra * se[j]
                pz[j] += dz * sobra * se[j]
                -- Só quem bate por trás perde: fica na velocidade do da frente
                -- (um pouco abaixo). Antes os dois perdiam 3% por passo de
                -- contato, e no bolo da largada todo mundo travava junto.
                -- Lado a lado (o outro a mais de 60° da frente) é só empurrão.
                local ri = math.rad(C.yaw[i])
                local proj = (dx * math.sin(ri) + dz * math.cos(ri)) / d
                if math.abs(proj) > 0.5 then
                    local atras, frente = if proj > 0 then i else j, if proj > 0 then j else i
                    C.vel[atras] = math.min(C.vel[atras], C.vel[frente] * 0.95)
                end
            end
        end
    end
end

return M
