-- Desenho: cada corpo é um personagem de cena com sprite pré-renderizado. A
-- simulação anda em passo fixo; aqui interpolamos entre o passo anterior e o
-- atual pela fração `a` que sobrou do acumulador, para 60 Hz de física não
-- tremer numa tela de 144 Hz. Também é aqui que o carro "vive": quica com a
-- velocidade, levanta poeira, cospe chama no turbo e solta faísca no muro.
local M = {}

local INCLINA_GIRO = 1.6    -- graus de sprite por grau/s de curva (0,8 parecia ir reto)
local INCLINA_DERIVA = 2.5 -- graus por unidade/s de deriva
local INCLINA_MAX = 60     -- passa de uma direção da folha (22,5° em 16)
local QUIQUE = 0.35        -- unidades de sobe-e-desce na velocidade máxima
local VMAX = 82 -- = FISICA.VMAX

-- 16 direções com o motor lendo folhas de 8: cada carro é DOIS personagens,
-- um com as direções pares e outro com as ímpares (folhas _par_8dir e
-- _impar_8dir), e só o que tem a direção mais perto da câmera aparece. A
-- folha ímpar gira 22,5° a mais: virar o personagem 22,5° para o outro lado
-- faz o corte de 45° do motor cair nas linhas certas dela.
M.direcoes = 16

-- Quadros por direção na folha (colunas): o retrato da HUD corta um deles.
M.quadros = 5

local par, impar = {}, {}
local mostra_impar = {}
local poeira, turbo, faisca_t = {}, {}, {}
local ritmo = {} -- animação de roda que cada carro está tocando
local relogio = 0

-- Carro da câmera: a batida dele também treme a tela.
M.foco = 0

-- Rodas no ritmo da velocidade (animações "extra" da folha): parado balança, depois 110/60/30 ms.
local function ritmo_de(vel: number)
    local v = math.abs(vel)
    return if v < 2 then "parado" elseif v < 25 then "lento" elseif v < 55 then "medio" else "rapido"
end

local function lerp_angulo(a: number, b: number, f: number)
    local d = (b - a + 180) % 360 - 180
    return a + d * f
end

local function folha(sprite: string)
    return (string.gsub(sprite, "%.png$", if M.direcoes == 16 then "_par_8dir.png" else "_8dir.png"))
end

-- Retrato para a HUD: a folha e o retângulo (u0, v0, u1, v1) do 1º quadro da
-- linha 1 (o carro de três-quartos, de frente).
function M.retrato(sprite: string)
    return folha(sprite), 0, 1 / 8, 1 / M.quadros, 2 / 8
end

function M.criar(C, i: number, sprite: string)
    local pos = vector.create(C.px[i], C.py[i], C.pz[i])
    if M.direcoes == 16 then
        par[i], impar[i] = C.nome[i], C.nome[i] .. "_i"
        characters.add(par[i], folha(sprite), pos, C.yaw[i])
        characters.add(impar[i], (string.gsub(sprite, "%.png$", "_impar_8dir.png")), pos, C.yaw[i])
        characters.hide(impar[i])
        mostra_impar[i] = false
    else
        par[i] = C.nome[i]
        characters.add(par[i], folha(sprite), pos, C.yaw[i])
    end
    poeira[i] = vfx.play("poeira", pos)
    turbo[i] = nil
    ritmo[i] = nil
    faisca_t[i] = 0
end

local function efeitos(C, i: number, x: number, y: number, z: number, yaw: number)
    vfx.move(poeira[i], vector.create(x, y + 0.5, z))
    local r = math.rad(yaw)
    local tras = vector.create(x - math.sin(r) * 5, y + 2.5, z - math.cos(r) * 5)
    if C.turbo_on[i] == 1 then
        if not turbo[i] then
            turbo[i] = vfx.play("turbo", tras, 1, yaw)
            -- O tranco do turbo: o sprite incha um instante.
            characters.pop(par[i], 0.12, 0.2)
            if impar[i] then
                characters.pop(impar[i], 0.12, 0.2)
            end
        end
        vfx.move(turbo[i], tras, 1, yaw)
    elseif turbo[i] then
        vfx.stop(turbo[i])
        turbo[i] = nil
    end
    if C.batida[i] == 1 then
        C.batida[i] = 0
        if relogio - faisca_t[i] > 0.15 then
            faisca_t[i] = relogio
            vfx.play("faiscas_muro", vector.create(x, y + 2, z))
            characters.shake(par[i], 0.8, 0.25)
            if impar[i] then
                characters.shake(impar[i], 0.8, 0.25)
            end
            if i == M.foco then
                fx.shake_camera(1.2, 0.3)
            end
        end
    end
end

function M.desenhar(C, a: number, dt: number)
    relogio += dt
    local _, frente = camera.basis()
    local ang_cam = math.deg(math.atan2(frente.x, frente.z))
    for i = 1, C.n do
        local x = C.ax[i] + (C.px[i] - C.ax[i]) * a
        local z = C.az[i] + (C.pz[i] - C.az[i]) * a
        -- Quique: a suspensão trabalha mais rápido e mais alto com velocidade.
        local v = math.min(1, math.abs(C.vel[i]) / VMAX)
        local y = C.py[i] + math.abs(math.sin(relogio * (9 + 7 * v) + i * 1.7)) * QUIQUE * v
        -- O sprite mostra a curva: a câmera vem atrás do carro, então sem isto
        -- ele ficaria sempre de costas. Inclina pelo giro e pela deriva, como
        -- os jogos de corrida de sprite fazem (o carro "vira o nariz").
        local inclina = math.clamp(C.giro[i] * INCLINA_GIRO + C.lat[i] * INCLINA_DERIVA, -INCLINA_MAX, INCLINA_MAX)
        local yaw = lerp_angulo(C.ayaw[i], C.yaw[i], a)
        local face = yaw + inclina
        local pos = vector.create(x, y, z)
        if M.direcoes == 16 then
            -- Mesma conta do motor (Characters.cpp): 0 = de frente para a câmera.
            local d16 = math.floor((((ang_cam - face + 180) % 360) + 11.25) / 22.5) % 16
            local quer_impar = d16 % 2 == 1
            if quer_impar ~= mostra_impar[i] then
                mostra_impar[i] = quer_impar
                if quer_impar then
                    characters.hide(par[i])
                    characters.show(impar[i])
                else
                    characters.hide(impar[i])
                    characters.show(par[i])
                end
            end
            local nome = if quer_impar then impar[i] else par[i]
            characters.set_position(nome, pos)
            characters.face(nome, if quer_impar then face + 22.5 else face)
        else
            characters.set_position(par[i], pos)
            characters.face(par[i], face)
        end
        local quer = ritmo_de(C.vel[i])
        if quer ~= ritmo[i] then
            ritmo[i] = quer
            characters.play(par[i], quer, true)
            if impar[i] then
                characters.play(impar[i], quer, true)
            end
        end
        efeitos(C, i, x, C.py[i], z, yaw)
    end
end

return M
