-- Traçado das pistas: os pontos de controle de cada laço (fechado, o
-- primeiro é a largada). O jogo monta a faixa com eles (world.ribbon).
local M = {}

-- Pontos em metros no mapa. Menor raio de curva da linha central 84-156 m
-- (meia largura: 26 m), sem a pista se cruzar (menor aproximação entre
-- trechos: 235 m).
local PONTOS = {
    caldeira = {
        { 964.0350120017239, 578.2443924848913 }, { 905.0802564619016, 730.3928394892794 }, { 806.6518775451475, 873.8653205077128 },
        { 678.9688838150116, 951.0736291581713 }, { 515.6940429679048, 943.1906609109499 }, { 378.8912693703577, 863.9397082090106 },
        { 291.69376978597063, 737.5063131766211 }, { 264.13101404944086, 600.5604936773125 }, { 315.28268764987354, 460.63001357524627 },
        { 410.04085252658115, 324.1987790526787 }, { 530.0346157622956, 242.7893134325458 }, { 678.7050765518909, 252.3285957398868 },
        { 828.3657601886838, 330.8650187075539 }, { 935.9404131264162, 444.5969874691818 },
    },
    cinzas = {
        { 1168.4589720936797, 694.6989671967381 }, { 1144.56230371538, 795.5454363997057 }, { 1070.2404415161957, 888.793551255279 },
        { 954.8817276473311, 975.9289756091543 }, { 783.7350831188648, 1040.2081033730765 }, { 587.504441185546, 1064.1238994048638 },
        { 446.36984676907235, 1016.390346055318 }, { 353.68300035467087, 909.4432457278183 }, { 265.73148445536594, 797.9178526954507 },
        { 187.44785487439833, 685.5185512791056 }, { 194.33025980869456, 576.5896199812263 }, { 313.03695065509544, 498.5280403272029 },
        { 467.35589642841387, 455.05306732428744 }, { 616.8387032652315, 431.30038062615847 }, { 789.8975549632225, 417.97213294416713 },
        { 946.1877247129914, 435.93513672765795 }, { 1061.83412716534, 505.11521017372394 }, { 1143.8109599082043, 596.4151848975998 },
    },
}

-- Pontos em fração do mapa (0..1). Menor raio de curva da linha central
-- >= 40 m (meia largura: 26 m) e trechos que não são vizinhos a >= 110 m um
-- do outro (faixa de 52 m + acostamento de 9 m de cada lado nunca se tocam).
local FORMAS = {
    -- Feijão: reta longa embaixo (largada no meio dela), curvão à direita,
    -- S em cima, grampo de raio 64 no canto e a volta por dentro do recorte.
    obsidiana = {
        { 0.4909, 0.8500 }, { 0.7182, 0.8455 }, { 0.8364, 0.8182 }, { 0.8955, 0.7273 }, { 0.8455, 0.6000 }, { 0.8000, 0.4727 },
        { 0.8182, 0.3455 }, { 0.7955, 0.2591 }, { 0.7273, 0.1927 }, { 0.6273, 0.2073 }, { 0.5364, 0.1764 }, { 0.4500, 0.2073 },
        { 0.3727, 0.1827 }, { 0.2955, 0.1827 }, { 0.2545, 0.2000 }, { 0.2373, 0.2409 }, { 0.2545, 0.2818 }, { 0.2955, 0.2991 },
        { 0.3727, 0.3000 }, { 0.4409, 0.3318 }, { 0.4773, 0.4045 }, { 0.4455, 0.4864 }, { 0.3636, 0.5364 }, { 0.2909, 0.6091 },
        { 0.2318, 0.7000 }, { 0.2182, 0.7818 }, { 0.2636, 0.8455 },
    },
    -- Anel em volta do lago de lava: raio 380 m com duas ondas (4 e 7 por
    -- volta) que puxam a pista ora para a beira da lava, ora para o paredão.
    anel = {
        { 0.7936, 0.5000 }, { 0.8150, 0.5843 }, { 0.7429, 0.6400 }, { 0.6686, 0.6686 }, { 0.6229, 0.7129 }, { 0.5671, 0.7500 },
        { 0.5000, 0.7779 }, { 0.4186, 0.8043 }, { 0.3493, 0.7614 }, { 0.3314, 0.6686 }, { 0.3057, 0.6121 }, { 0.2393, 0.5700 },
        { 0.2064, 0.5000 }, { 0.2150, 0.4236 }, { 0.2436, 0.3521 }, { 0.3157, 0.3157 }, { 0.3907, 0.3107 }, { 0.4350, 0.2579 },
        { 0.5000, 0.1907 }, { 0.5793, 0.2036 }, { 0.6371, 0.2621 }, { 0.6843, 0.3157 }, { 0.7079, 0.3800 }, { 0.7314, 0.4379 },
    },
    -- Subida em zigue-zague pela encosta sul do cone (três grampos de raio
    -- 64), ombro a leste do cume e descida longa e rápida pela encosta leste.
    cume = {
        { 0.5714, 0.9129 }, { 0.4071, 0.9129 }, { 0.3750, 0.8993 }, { 0.3614, 0.8671 }, { 0.3750, 0.8350 }, { 0.4071, 0.8214 },
        { 0.4857, 0.8193 }, { 0.5857, 0.8193 }, { 0.6179, 0.8057 }, { 0.6314, 0.7736 }, { 0.6179, 0.7414 }, { 0.5857, 0.7279 },
        { 0.5071, 0.7257 }, { 0.3964, 0.7257 }, { 0.3643, 0.7121 }, { 0.3507, 0.6800 }, { 0.3643, 0.6479 }, { 0.3964, 0.6343 },
        { 0.4857, 0.6257 }, { 0.5714, 0.5857 }, { 0.6250, 0.5143 }, { 0.6536, 0.4286 }, { 0.7036, 0.3607 }, { 0.7714, 0.3500 },
        { 0.8143, 0.4286 }, { 0.8143, 0.5929 }, { 0.7750, 0.7679 }, { 0.6893, 0.9000 },
    },
}
local function desenho(tamanho, forma)
    local pts = {}
    for k = 1, #forma do
        pts[k] = { forma[k][1] * tamanho, forma[k][2] * tamanho }
    end
    return pts
end
-- As pistas do jogo, na ordem do campeonato. O nome de exibição homenageia
-- o rock que inspirou cada uma (só o título, nenhum som, letra ou marca).
M.ordem = { "caldeira", "cinzas", "obsidiana", "anel", "cume" }
M.pistas = {
    caldeira = { titulo = "Running with the Devil", musica = "corrida_caldeira", tamanho = 1200, largura = 52,
                 pontos = PONTOS.caldeira },
    cinzas = { titulo = "Smoke on the Water", musica = "corrida_cinzas", tamanho = 1400, largura = 52,
               pontos = PONTOS.cinzas },
    obsidiana = { titulo = "Paint It Black", musica = "corrida_obsidiana", tamanho = 1100, largura = 52,
                  forma = FORMAS.obsidiana },
    anel = { titulo = "Ring of Fire", musica = "corrida_anel", tamanho = 1400, largura = 52,
             forma = FORMAS.anel },
    cume = { titulo = "Stairway to Heaven", musica = "corrida_cume", tamanho = 1400, largura = 52,
             forma = FORMAS.cume },
}

-- Pontos de controle da pista e a ficha dela; nil para um mapa que não é pista.
function M.pontos(mapa: string)
    local p = M.pistas[mapa]
    if not p then
        return nil
    end
    if p.forma then
        return desenho(p.tamanho, p.forma), p
    end
    return p.pontos, p
end

return M
