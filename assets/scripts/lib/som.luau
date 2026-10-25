-- Som da corrida: música da pista, motor do jogador (tom pela velocidade),
-- turbo, bipes da largada, batida no muro, volta fechada, chiado do chão
-- quente e o fecho da vitória. Tudo lê as colunas de C.
local M = {}

local motor = 0
local turbo_antes = false
local bipe_antes = -1
local venceu = false
local chiado = 0
local volta_antes = 0
local batida_t = -1

-- Uma vez por etapa: zera o estado e troca os laços da etapa anterior.
function M.iniciar(musica: string?)
    if motor ~= 0 then
        audio.stop(motor)
        audio.stop(chiado)
    end
    turbo_antes, bipe_antes, venceu = false, -1, false
    volta_antes, batida_t = 0, -1
    if musica then
        audio.music("assets/musica/" .. musica .. ".ogg", { loop = true }, 1.5)
    end
    motor = audio.loop("assets/sounds/motor_loop.ogg", 0.35)
    -- Começa mudo; o volume segue o calor do chão sob o carro.
    chiado = audio.loop("assets/sounds/lava_chiado_loop.ogg", 0)
end

-- Antes de trocar de pista: a carga do mapa para o quadro (e, no navegador,
-- o áudio junto), então tudo some antes em vez de engasgar no meio.
function M.calar(segundos: number)
    audio.stop_music(segundos)
    if motor ~= 0 then
        audio.set_volume(motor, 0, segundos)
        audio.set_volume(chiado, 0, segundos)
    end
end

-- `contagem`: segundos que faltam para a largada (≤ 0 já largou).
-- Chamado antes do desenho: o desenho zera C.batida depois das faíscas.
function M.atualizar(C, eu: number, e, contagem: number, relogio: number)
    local s = math.ceil(contagem)
    if contagem > 0 and s ~= bipe_antes and s <= 3 then
        audio.play("assets/sounds/bipe_contagem.ogg", 0.7, if s == 1 then 1.5 else 1)
        bipe_antes = s
    end
    -- O tom do motor sobe com a velocidade; superaquecido ele "engasga" mais grave.
    local v = math.abs(C.vel[eu]) / 62
    audio.set_pitch(motor, (0.7 + v * 0.9) * (if C.superaq[eu] == 1 then 0.85 else 1))
    local turbo = e.turbo and C.turbo[eu] > 0
    if turbo and not turbo_antes then
        audio.play("assets/sounds/turbo_whoosh.ogg", 0.6)
    end
    turbo_antes = turbo
    -- Raspar no muro dispara a batida a cada passo; uma por 0,25 s basta.
    if C.batida[eu] == 1 and relogio - batida_t > 0.25 then
        batida_t = relogio
        audio.play("assets/sounds/batida.ogg", 0.4 + 0.5 * math.min(math.abs(C.vel[eu]) / 40, 1))
    end
    -- Brasa (calor 18) já chia baixo; lava (60) chia alto.
    audio.set_volume(chiado, math.min(C.piso_calor[eu] / 60, 1) * 0.6, 0.2)
    if C.volta[eu] > volta_antes then
        volta_antes = C.volta[eu]
        if C.chegou[eu] == 0 then
            audio.play("assets/sounds/chegada_jingle.ogg", 0.6)
        end
    end
    if C.chegou[eu] > 0 and not venceu then
        venceu = true
        audio.stop_music(0.5)
        audio.play("assets/musica/vitoria.ogg", 0.9)
    end
end

return M
