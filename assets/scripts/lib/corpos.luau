-- Corpos da corrida em colunas (SoA). A substância é só o índice i; tudo o
-- que o corpo É, TEM, FAZ e SOFRE mora numa coluna. Um sistema lê só as
-- colunas que usa e varre de 1 a n: linear, sem tabela por carro.
--
-- Categorias:
--   quantidade  massa, raio
--   qualidade   potencia, pneu (aderência própria), calor (temperatura)
--   lugar       px, py, pz, t (0..1 na pista), s (metros na volta)
--   situação    yaw (graus), vel (m/s ao longo do yaw), lat (deriva lateral),
--               giro (graus/s da curva), batida (1 no passo em que bateu
--               no muro), turbo_on (1 enquanto queima turbo)
--   tempo       volta, t_volta, t_melhor, chegou
--   paixão      sofre_calor, sofre_empurrao (1/massa)
--   posse       turbo (carga 0..1)
--   relação     colocacao
--   piso_*      qualidades do chão sob o corpo (amostradas por piso.luau)
local M = {}

local COLUNAS = {
    "massa", "raio", "potencia", "pneu", "calor",
    "px", "py", "pz", "t", "s",
    "yaw", "vel", "lat", "giro", "batida", "turbo_on",
    "volta", "t_volta", "t_melhor", "chegou",
    "sofre_calor", "sofre_empurrao",
    "turbo", "colocacao",
    "cp", "superaq", "borda",
    "piso_ader", "piso_calor", "piso_arrasto",
    -- quadro anterior, para o desenho interpolar entre passos fixos
    "ax", "az", "ayaw",
}

function M.novo(capacidade: number)
    local C = { n = 0, nome = table.create(capacidade, "") }
    for _, k in COLUNAS do
        C[k] = table.create(capacidade, 0)
    end
    return C
end

-- `ficha`: só o que difere do padrão (quantidade e qualidade do carro).
function M.adicionar(C, nome: string, x: number, z: number, yaw: number, ficha)
    local i = C.n + 1
    C.n = i
    C.nome[i] = nome
    C.massa[i] = ficha.massa or 1
    C.raio[i] = ficha.raio or 3
    C.potencia[i] = ficha.potencia or 1
    C.pneu[i] = ficha.pneu or 1
    C.sofre_calor[i] = ficha.sofre_calor or 1
    C.sofre_empurrao[i] = 1 / C.massa[i]
    C.px[i], C.pz[i], C.yaw[i] = x, z, yaw
    C.ax[i], C.az[i], C.ayaw[i] = x, z, yaw
    C.t_melhor[i] = math.huge
    C.piso_ader[i] = 1
    C.borda[i] = 99
    return i
end

return M
