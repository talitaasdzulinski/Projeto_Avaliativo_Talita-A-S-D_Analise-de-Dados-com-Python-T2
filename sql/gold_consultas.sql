-- ===========================================================================
-- CONSULTAS DA CAMADA GOLD - Viagens a Servico (Projeto Avaliativo)
-- ===========================================================================
-- Este arquivo guarda, em SQL puro, a camada Gold agregada e as consultas que
-- respondem as perguntas de negocio. As mesmas consultas sao executadas pelo
-- notebook 3_analise.ipynb; aqui elas ficam versionadas e podem ser rodadas
-- direto no MySQL Workbench.
--
-- Pre-requisito: 0_criar_banco.sql, 1_extrair.py e 2_transformar.py ja rodados.
-- ===========================================================================

USE transparencia;

-- ===========================================================================
-- CAMADA GOLD AGREGADA (JOIN + GROUP BY)
-- ===========================================================================

-- ---- Forma 1: TABELA ------------
DROP TABLE IF EXISTS gold_orgao_gastos;
CREATE TABLE gold_orgao_gastos AS
SELECT
    v.nome_orgao_superior        AS orgao,
    COUNT(DISTINCT v.id_viagem)  AS qtd_viagens,
    COUNT(*)                     AS qtd_pagamentos,
    SUM(p.valor)                 AS total_pago,
    AVG(p.valor)                 AS ticket_medio
FROM silver_viagem v
JOIN silver_pagamento p ON p.id_viagem = v.id_viagem
GROUP BY v.nome_orgao_superior;

-- ---- Forma 2: VIEW -------
DROP VIEW IF EXISTS vw_gold_orgao_gastos;
CREATE VIEW vw_gold_orgao_gastos AS
SELECT
    v.nome_orgao_superior        AS orgao,
    COUNT(DISTINCT v.id_viagem)  AS qtd_viagens,
    COUNT(*)                     AS qtd_pagamentos,
    SUM(p.valor)                 AS total_pago,
    AVG(p.valor)                 AS ticket_medio
FROM silver_viagem v
JOIN silver_pagamento p ON p.id_viagem = v.id_viagem
GROUP BY v.nome_orgao_superior;

-- ===========================================================================
-- PERGUNTAS DE NEGOCIO
-- ===========================================================================

-- P1) Os 5 orgaos com maior custo total.
SELECT
    nome_orgao_superior  AS orgao,
    COUNT(*)             AS qtd_viagens,
    SUM(valor_total)     AS custo_total,
    AVG(valor_total)     AS custo_medio
FROM silver_viagem
GROUP BY nome_orgao_superior
ORDER BY custo_total DESC
LIMIT 5;


-- P2) Os 3 destinos com maior custo medio por viagem.
--     O SELECT DISTINCT interno evita contar o valor da mesma viagem uma vez
--     por trecho. O HAVING descarta destinos com poucas viagens (outliers).
SELECT
    CONCAT(d.destino_cidade, '/', d.destino_uf) AS destino,
    COUNT(*)                                    AS qtd_viagens,
    AVG(d.valor_total)                          AS custo_medio
FROM (
    SELECT DISTINCT
        t.destino_cidade,
        t.destino_uf,
        v.id_viagem,
        v.valor_total
    FROM silver_trecho t
    JOIN silver_viagem v ON v.id_viagem = t.id_viagem
    WHERE t.destino_cidade IS NOT NULL
      AND t.destino_uf     IS NOT NULL
) AS d
GROUP BY destino
HAVING COUNT(*) >= 30
ORDER BY custo_medio DESC
LIMIT 3;


-- P3) A viagem de maior duracao e o seu custo total.
SELECT
    id_viagem,
    nome_orgao_superior,
    cargo,
    data_inicio,
    data_fim,
    duracao_dias,
    valor_total
FROM silver_viagem
ORDER BY duracao_dias DESC, valor_total DESC
LIMIT 10;


-- P4) O tipo de pagamento com maior valor medio.
SELECT
    tipo_pagamento,
    COUNT(*)    AS qtd_pagamentos,
    AVG(valor)  AS valor_medio,
    SUM(valor)  AS valor_total
FROM silver_pagamento
GROUP BY tipo_pagamento
ORDER BY valor_medio DESC;


-- P5) O meio de transporte mais usado nos trechos.
SELECT
    meio_transporte,
    COUNT(*) AS qtd_trechos
FROM silver_trecho
WHERE meio_transporte IS NOT NULL
GROUP BY meio_transporte
ORDER BY qtd_trechos DESC;


-- P6) A UF de destino que aparece em mais trechos.
SELECT
    destino_uf,
    COUNT(*)                  AS qtd_trechos,
    COUNT(DISTINCT id_viagem) AS qtd_viagens
FROM silver_trecho
WHERE destino_uf IS NOT NULL
GROUP BY destino_uf
ORDER BY qtd_trechos DESC
LIMIT 10;


-- P7) O orgao que mais pagou no total (lendo a camada Gold ja agregada).
SELECT
    orgao,
    qtd_viagens,
    qtd_pagamentos,
    total_pago,
    ticket_medio
FROM gold_orgao_gastos
ORDER BY total_pago DESC
LIMIT 10;
