-- Piloto automático: mira num ponto à frente na pista (t + antecipação),
-- acelera e freia pela curvatura. Devolve a mesma entrada que o teclado dá,
-- então a física não sabe quem dirige.
--
-- Cada carro tem a sua faixa (esquerda, meio, direita) em vez de todos
-- mirarem a linha central: com a mesma mira os seis viravam fila indiana e
-- passavam a corrida empurrando o da frente. Com carro na frente, na mesma
-- faixa e perto, desvia para o lado com mais espaço e ultrapassa.
local PISTA = require("lib/pista")
local FISICA = require("lib/fisica")

local M = {}

-- nivel 1..3: quanto antecipa e quanto arrisca na curva.
local ANTECIPA = { 0.012, 0.018, 0.024 }
local CORAGEM = { 0.92, 1.0, 1.08 } -- > 1 = reta no talo, curva no limite
local FAIXA = { -0.22, 0, 0.22 } -- fração da largura, a partir do centro
local OLHA = 40                   -- unidades à frente em que um carro atrapalha
local LADO_LIVRE = 11             -- desvio lateral para passar (carro ~9 de largura)
local BEIRA = 7                   -- folga da borda que a mira respeita

local function angulo(a: number)
    return (a + 180) % 360 - 180
end

-- Deslocamento lateral de (x, z) em relação ao centro da pista em t
-- (positivo para o lado (tz, -tx), o mesmo da largada).
local function lateral(t: number, x: number, z: number)
    local p = PISTA.ponto(t)
    if not p then
        return 0
    end
    return (x - p.position.x) * p.tangent.z - (z - p.position.z) * p.tangent.x
end

-- Faixa que o carro i quer agora: a dele, ou a de desvio se alguém na frente
-- está no caminho.
local function faixa(C, i: number, largura: number)
    local limite = largura / 2 - BEIRA
    local quer = FAIXA[(i - 1) % #FAIXA + 1] * largura
    local r = math.rad(C.yaw[i])
    local fx, fz = math.sin(r), math.cos(r)
    local meu = lateral(C.t[i], C.px[i], C.pz[i])
    local perto = OLHA
    for j = 1, C.n do
        if j ~= i then
            local dx, dz = C.px[j] - C.px[i], C.pz[j] - C.pz[i]
            local frente = dx * fx + dz * fz
            if frente > 0 and frente < perto then
                local dele = lateral(C.t[j], C.px[j], C.pz[j])
                if math.abs(dele - quer) < LADO_LIVRE then
                    perto = frente
                    -- Passa pelo lado em que já está (menos volante), ou
                    -- pelo outro se aquele não cabe.
                    local lado = if meu >= dele then 1 else -1
                    local alvo = dele + lado * LADO_LIVRE
                    if math.abs(alvo) > limite then
                        alvo = dele - lado * LADO_LIVRE
                    end
                    quer = alvo
                end
            end
        end
    end
    return math.clamp(quer, -limite, limite)
end

function M.entrada(C, i: number, nivel: number)
    local alvo = PISTA.ponto(C.t[i] + ANTECIPA[nivel])
    if not alvo then
        return { steer = 0, throttle = 0.6, brake = false, turbo = false }
    end
    local desvio = faixa(C, i, alvo.width)
    local ax = alvo.position.x + alvo.tangent.z * desvio
    local az = alvo.position.z - alvo.tangent.x * desvio
    local dx, dz = ax - C.px[i], az - C.pz[i]
    local erro = angulo(math.deg(math.atan2(dx, dz)) - C.yaw[i])
    -- A curvatura vem da pista: trocar de faixa não é curva para frear.
    local reta = math.deg(math.atan2(alvo.tangent.x, alvo.tangent.z))
    local curva = math.max(math.abs(angulo(reta - C.yaw[i])), math.abs(erro) * 0.5) / 45
    local vel_alvo = FISICA.VMAX * CORAGEM[nivel] * (1 - math.min(curva, 0.5))
    return {
        steer = math.clamp(erro / 25, -1, 1),
        throttle = if C.vel[i] < vel_alvo then 1 else 0,
        brake = C.vel[i] > vel_alvo + 8,
        -- Turbo só na reta e frio: o piloto também sofre calor.
        turbo = curva < 0.1 and C.calor[i] < 70 and C.turbo[i] > 0.3,
    }
end

return M
