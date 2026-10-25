-- Cenário da corrida: o "look" HD-2D (diorama, entardecer, névoa quente) e as
-- fumarolas ao longo da pista. Uma fumarola é só uma peça com qualidades em
-- tag ("fonte", "calor:N"): quem passa por cima sofre calor (lib/piso.luau),
-- igual a qualquer outra coisa que tenha calor.
local PISTA = require("lib/pista")

local M = {}

local ESCALA = 8          -- peças CC0 vêm em metro; o carro mede ~9 unidades
local CADA = 170          -- metros entre fumarolas
local NA_PISTA = 3        -- uma em cada 3 fica dentro da pista (risco e atalho)

function M.look()
    -- Diorama do motor ajustado para a câmera baixa: o sol de fim de tarde fica
    -- à frente em boa parte da volta, então o brilho especular do basalto e os
    -- raios de sol entre a fumaça aparecem.
    world.set_look("diorama")
    world.set_look({
        saturation = 1.18, contrast = 1.14,
        god_ray_intensity = 0.32, god_ray_scattering = 0.14,
        vignette = 0.28, vignette_softness = 0.55,
        shadow_tint = vector.create(0.45, 0.5, 0.85), shadow_tint_strength = 0.2,
        highlight_tint = vector.create(1.0, 0.78, 0.5), highlight_tint_strength = 0.22,
    })
    world.set_weather("clear")
    world.set_time(17.0)
    world.set_fog({ color = vector.create(0.62, 0.42, 0.3), start = 700, ["end"] = 3200, opacity = 0.45 })
end

function M.fumarolas()
    local comprimento = world.ribbon_length(PISTA.nome)
    local n = math.floor(comprimento / CADA)
    for k = 1, n do
        local p = PISTA.ponto((k - 0.5) / n)
        if p then
            local tx, tz = p.tangent.x, p.tangent.z
            local lado = if k % 2 == 0 then 1 else -1
            -- Dentro da pista (perto da borda) ou do lado de fora, no acostamento.
            local d = if k % NA_PISTA == 0 then p.width * 0.3 * lado else (p.width * 0.5 + 16) * lado
            local x, z = p.position.x + tz * d, p.position.z - tx * d
            local pos = vector.create(x, world.ground_height(x, z), z)
            local o = objects.spawn("assets/props/base_fumarola.glb", pos)
            if o then
                o.scale = vector.create(ESCALA, ESCALA, ESCALA)
                o:add_tag("fonte")
                o:add_tag("calor:35")
            end
            vfx.play("fumarola", pos)
        end
    end
end

return M
