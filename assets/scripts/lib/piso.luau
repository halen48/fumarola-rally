-- Amostra as qualidades do chão sob cada corpo e guarda nas colunas piso_*.
-- world.ground_layers monta uma tabela por chamada, então cada corpo é
-- amostrado a cada QUADROS passos, em rodízio (16 carros → 4 por passo).
local DADOS = require("lib/piso_dados")

local M = {}

local QUADROS = 4
local passo = 0

-- Só o nome do arquivo: a cena pode guardar o caminho inteiro.
local function qualidades(camadas)
    local ader, calor, arrasto, soma = 0, 0, 0, 0
    for textura, peso in camadas do
        local d = DADOS.camadas[string.match(textura, "[^/\\]+$") or textura]
        if d and peso > 0 then
            ader += d.aderencia * peso
            calor += d.calor * peso
            arrasto += d.arrasto * peso
            soma += peso
        end
    end
    local p = DADOS.padrao
    if soma <= 0 then
        return p.aderencia, p.calor, p.arrasto
    end
    -- O que a pintura não cobre é chão padrão.
    local resto = math.max(0, 1 - soma)
    return ader + p.aderencia * resto, calor + p.calor * resto, arrasto + p.arrasto * resto
end

function M.amostrar(C)
    passo += 1
    for i = 1 + passo % QUADROS, C.n, QUADROS do
        local a, c, r = qualidades(world.ground_layers(C.px[i], C.pz[i]))
        C.piso_ader[i], C.piso_calor[i], C.piso_arrasto[i] = a, c, r
    end
end

-- Objetos do mapa que agem: tag "fonte" mais as qualidades em tag
-- ("calor:30", "impulso:20"), lidos uma vez. O impulso empurra para a frente
-- quem passa por cima; o calor aquece. Qualquer objeto com a tag age igual.
local fontes = { x = {}, z = {}, r = {}, calor = {}, impulso = {}, n = 0 }

function M.ler_fontes()
    for _, o in objects.with_tag("fonte") do
        local n = fontes.n + 1
        fontes.n = n
        fontes.x[n], fontes.z[n] = o.position.x, o.position.z
        fontes.r[n] = math.max(o.scale.x, o.scale.z) * 1.2 -- a peça de 1 m escalada: o raio dela no chão
        fontes.calor[n], fontes.impulso[n] = 0, 0
        for _, t in o:tags() do
            local k, v = string.match(t, "^(%a+):(%d+)$")
            if k == "calor" or k == "impulso" then
                fontes[k][n] = tonumber(v)
            end
        end
    end
end

-- Ação das fontes sobre os corpos (n_fontes × n_corpos, os dois pequenos).
function M.agir(C, dt: number)
    for f = 1, fontes.n do
        local fx, fz, rr = fontes.x[f], fontes.z[f], fontes.r[f] * fontes.r[f]
        for i = 1, C.n do
            local dx, dz = C.px[i] - fx, C.pz[i] - fz
            if dx * dx + dz * dz < rr then
                C.calor[i] += fontes.calor[f] * C.sofre_calor[i] * dt
                C.vel[i] += fontes.impulso[f] * C.sofre_empurrao[i] * dt
            end
        end
    end
end

return M
