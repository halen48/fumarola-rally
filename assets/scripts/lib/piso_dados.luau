-- Qualidades do piso por camada pintada (o nome do arquivo da textura é só a
-- chave do dado; o código nunca pergunta "é lava?", pergunta "quanto calor?").
--   aderencia  0..1, multiplica o pneu (tração e curva)
--   calor      graus por segundo que o piso passa a quem sofre calor
--   arrasto    perda de velocidade por segundo (cinza fofa, cascalho)
return {
    padrao = { aderencia = 0.85, calor = 0, arrasto = 0.05 },
    camadas = {
        ["basalto.png"] = { aderencia = 1.0, calor = 0, arrasto = 0.02 },
        ["cascalho.png"] = { aderencia = 0.7, calor = 0, arrasto = 0.25 },
        ["cinza.png"] = { aderencia = 0.55, calor = 0, arrasto = 0.35 },
        ["brasa.png"] = { aderencia = 0.8, calor = 18, arrasto = 0.05 },
        ["lava.png"] = { aderencia = 0.4, calor = 60, arrasto = 0.6 },
    },
}
