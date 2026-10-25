-- Câmera de corrida: perseguição baixa, atrás do carro, com o horizonte e o
-- céu no terço de cima (a leitura de jogo de corrida, não a de tabuleiro
-- isométrico). Ela não cola: gira atrás do carro com atraso — numa curva o
-- carro vira dentro do quadro antes de a câmera alcançar, e é isso que dá a
-- leitura da curva — e se afasta um pouco com a velocidade.
local M = {}

local PITCH = 13        -- graus: baixo, o horizonte entra no quadro
local PITCH_VEL = -3    -- ainda mais baixa no máximo (sensação de velocidade)
local DIST = 56         -- unidades (carro ~9 de altura): perto, sem colar
local DIST_VEL = 0.3    -- afasta com a velocidade
local ALTURA_ALVO = 6   -- mira acima do carro: ele fica no terço de baixo
local ATRASO = 1.6      -- 1/s: quanto do ângulo ela recupera por segundo (2,4 colava atrás e o carro parecia ir reto)
local ADIANTE = 0.25    -- s de antecipação do alvo
local SUAVE_ALVO = 9    -- 1/s: o alvo segue o carro sem tremer
local VMAX = 82 -- = FISICA.VMAX

local yaw_cam = 0
local ax, ay, az = 0, 0, 0

function M.iniciar(x: number, y: number, z: number, yaw: number)
    camera.free(true)
    camera.see_through(10, 0.35)
    yaw_cam = yaw
    ax, ay, az = x, y + ALTURA_ALVO, z
end

function M.seguir(x: number, y: number, z: number, yaw: number, vel: number, dt: number)
    local d = (yaw - yaw_cam + 180) % 360 - 180
    yaw_cam += d * math.min(1, ATRASO * dt)
    local r = math.rad(yaw)
    local tx, tz = x + math.sin(r) * vel * ADIANTE, z + math.cos(r) * vel * ADIANTE
    local f = math.min(1, SUAVE_ALVO * dt)
    ax += (tx - ax) * f
    ay += (y + ALTURA_ALVO - ay) * f
    az += (tz - az) * f
    local v = math.min(1, math.abs(vel) / VMAX)
    camera.set_target(vector.create(ax, ay, az))
    -- O yaw de órbita do motor põe a câmera atrás de quem olha para yaw_cam.
    camera.set_orbit(-yaw_cam - 90, PITCH + PITCH_VEL * v, DIST + math.abs(vel) * DIST_VEL)
    -- Carro nítido, horizonte amaciado: o tilt-shift do HD-2D com a câmera baixa.
    world.set_focus(vector.create(x, y, z), 0.05, true, 60, 2.5)
end

return M
