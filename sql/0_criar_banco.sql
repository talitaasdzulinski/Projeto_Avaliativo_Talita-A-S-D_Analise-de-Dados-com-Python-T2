-- ===========================================================================
-- FASE 0 - CRIAR O BANCO E AS TABELAS (Viagens a Servico / Projeto Avaliativo)
-- ===========================================================================
-- COMO USAR (passo a passo):
--   1) Abra o MySQL Workbench e conecte no seu servidor (Local instance).
--   2) Abra uma aba de query (SQL) em branco.
--   3) Copie TODO o conteudo deste arquivo (Ctrl+A, Ctrl+C aqui).
--   4) Cole na aba de query do Workbench (Ctrl+V).
--   5) Clique no raio (ou aperte Ctrl+Shift+Enter) para EXECUTAR tudo.
--   6) Pronto! O banco 'transparencia' e as 8 tabelas estarao criados.
--      Agora siga para a Fase 1 (python 1_extrair.py).
--
-- IMPORTANTE: rode este script UMA vez, ANTES dos scripts Python. Os scripts
-- Python NAO criam tabelas: eles apenas inserem/transformam os dados.
-- O nome do banco (transparencia) deve ser o MESMO do .env (MYSQL_DATABASE).
-- ===========================================================================

-- 1) BANCO DE DADOS ---------------------------------------------------------
CREATE DATABASE IF NOT EXISTS transparencia
    CHARACTER SET utf8mb4
    COLLATE utf8mb4_general_ci;

USE transparencia;


-- ===========================================================================
-- 2) CAMADA RAW  (replica do CSV: TODAS as colunas sao VARCHAR / texto)
--    Sem PK/FK: a Raw guarda o dado bruto, exatamente como veio do arquivo.
--    A ordem das colunas bate com a ordem do CSV (o 1_extrair.py insere "na
--    ordem", com INSERT INTO tabela VALUES (...)). Inclui colunas que a
--    Silver nao usa (ex.: cpf_viajante, funcao, dados de volta da passagem),
--    pois a Raw replica o CSV inteiro.
-- ===========================================================================
-- Colunas e ordem conferidas diretamente contra o cabecalho real dos CSVs
-- (2025_Viagem.csv, 2025_Pagamento.csv, 2025_Passagem.csv, 2025_Trecho.csv).
-- Pagamento, Passagem e Trecho NAO tem coluna de ID propria no CSV: a
-- primeira coluna real e sempre id_viagem. O ID proprio (AUTO_INCREMENT)
-- so nasce na Silver.
DROP TABLE IF EXISTS raw_viagem;
CREATE TABLE raw_viagem (
    id_viagem              VARCHAR(20),
    num_proposta           VARCHAR(20),
    situacao               VARCHAR(50),
    viagem_urgente         VARCHAR(5),
    justificativa_urgencia VARCHAR(4000),
    cod_orgao_superior     VARCHAR(20),
    nome_orgao_superior    VARCHAR(255),
    cod_orgao_solicitante  VARCHAR(20),
    nome_orgao_solicitante VARCHAR(255),
    cpf_viajante           VARCHAR(20),
    nome_viajante          VARCHAR(255),
    cargo                  VARCHAR(255),
    funcao                 VARCHAR(255),
    descricao_funcao       VARCHAR(255),
    data_inicio            VARCHAR(10),
    data_fim               VARCHAR(10),
    destinos               VARCHAR(4000),
    motivo                 VARCHAR(4000),
    valor_diarias          VARCHAR(30),
    valor_passagens        VARCHAR(30),
    valor_devolucao        VARCHAR(30),
    valor_outros_gastos    VARCHAR(30)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS raw_pagamento;
CREATE TABLE raw_pagamento (
    id_viagem           VARCHAR(20),
    num_proposta        VARCHAR(20),
    cod_orgao_superior  VARCHAR(20),
    nome_orgao_superior VARCHAR(255),
    cod_orgao_pagador   VARCHAR(20),
    nome_orgao_pagador  VARCHAR(255),
    cod_ug_pagadora     VARCHAR(20),
    nome_ug_pagadora    VARCHAR(255),
    tipo_pagamento      VARCHAR(50),
    valor               VARCHAR(30)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS raw_passagem;
CREATE TABLE raw_passagem (
    id_viagem            VARCHAR(20),
    num_proposta         VARCHAR(20),
    meio_transporte      VARCHAR(50),
    pais_origem_ida      VARCHAR(60),
    uf_origem_ida        VARCHAR(40),
    cidade_origem_ida    VARCHAR(80),
    pais_destino_ida     VARCHAR(60),
    uf_destino_ida       VARCHAR(40),
    cidade_destino_ida   VARCHAR(80),
    pais_origem_volta    VARCHAR(60),
    uf_origem_volta      VARCHAR(40),
    cidade_origem_volta  VARCHAR(80),
    pais_destino_volta   VARCHAR(60),
    uf_destino_volta     VARCHAR(40),
    cidade_destino_volta VARCHAR(80),
    valor_passagem       VARCHAR(30),
    taxa_servico         VARCHAR(30),
    data_emissao         VARCHAR(10),
    hora_emissao         VARCHAR(10)
) ENGINE=InnoDB;

DROP TABLE IF EXISTS raw_trecho;
CREATE TABLE raw_trecho (
    id_viagem         VARCHAR(20),
    num_proposta      VARCHAR(20),
    sequencia_trecho  VARCHAR(10),
    origem_data       VARCHAR(10),
    origem_pais       VARCHAR(60),
    origem_uf         VARCHAR(40),
    origem_cidade     VARCHAR(80),
    destino_data      VARCHAR(10),
    destino_pais      VARCHAR(60),
    destino_uf        VARCHAR(40),
    destino_cidade    VARCHAR(80),
    meio_transporte   VARCHAR(50),
    numero_diarias    VARCHAR(30),
    missao            VARCHAR(5)
) ENGINE=InnoDB;


-- ===========================================================================
-- 3) CAMADA SILVER  (dados tipados + integridade referencial)
--    silver_viagem e a tabela principal (PRIMARY KEY = id_viagem).
--    As demais apontam para ela com FOREIGN KEY (id_viagem).
--
--    Ordem importa: por causa da FK, derrubamos as filhas ANTES da principal,
--    e criamos a principal ANTES das filhas.
-- ===========================================================================
DROP TABLE IF EXISTS silver_pagamento;
DROP TABLE IF EXISTS silver_passagem;
DROP TABLE IF EXISTS silver_trecho;
DROP TABLE IF EXISTS silver_viagem;

-- ---- Tabela principal ----
CREATE TABLE silver_viagem (
    id_viagem            VARCHAR(20)  NOT NULL,
    num_proposta         VARCHAR(20),
    situacao             VARCHAR(50),
    viagem_urgente       VARCHAR(5),
    cod_orgao_superior   VARCHAR(20),
    nome_orgao_superior  VARCHAR(255) NOT NULL,   -- constraint extra 1: NOT NULL
    nome_viajante        VARCHAR(255),
    cargo                VARCHAR(255),
    data_inicio          DATE,
    data_fim             DATE,
    destinos             VARCHAR(4000),
    motivo               VARCHAR(4000),
    valor_diarias        DECIMAL(10,2),
    valor_passagens      DECIMAL(10,2),
    valor_devolucao      DECIMAL(10,2),
    valor_outros_gastos  DECIMAL(10,2),
    valor_total          DECIMAL(12,2),            -- calculado
    duracao_dias         INT,                       -- calculado
    PRIMARY KEY (id_viagem),
    -- constraint extra 2: diarias nunca podem ser negativas
    CONSTRAINT chk_viagem_diarias CHECK (valor_diarias >= 0)
) ENGINE=InnoDB;

-- ---- Tabela dependente: passagem ----
CREATE TABLE silver_passagem (
    id_passagem         INT NOT NULL AUTO_INCREMENT,
    id_viagem           VARCHAR(20) NOT NULL,
    meio_transporte     VARCHAR(50),
    pais_origem_ida     VARCHAR(60),
    uf_origem_ida       VARCHAR(40),
    cidade_origem_ida   VARCHAR(80),
    pais_destino_ida    VARCHAR(60),
    uf_destino_ida      VARCHAR(40),
    cidade_destino_ida  VARCHAR(80),
    valor_passagem      DECIMAL(10,2),
    taxa_servico        DECIMAL(10,2),
    data_emissao        DATE,
    PRIMARY KEY (id_passagem),
    FOREIGN KEY (id_viagem) REFERENCES silver_viagem(id_viagem),
    -- constraints extras: valor e taxa nunca negativos
    CONSTRAINT chk_passagem_valor CHECK (valor_passagem >= 0),
    CONSTRAINT chk_passagem_taxa  CHECK (taxa_servico >= 0)
) ENGINE=InnoDB;

-- ---- Tabela dependente: pagamento ----
CREATE TABLE silver_pagamento (
    id_pagamento        INT NOT NULL AUTO_INCREMENT,
    id_viagem           VARCHAR(20) NOT NULL,
    num_proposta        VARCHAR(20),
    nome_orgao_pagador  VARCHAR(255),
    nome_ug_pagadora    VARCHAR(255),
    tipo_pagamento      VARCHAR(50) NOT NULL,      -- constraint extra 1: NOT NULL
    valor               DECIMAL(10,2),
    PRIMARY KEY (id_pagamento),
    FOREIGN KEY (id_viagem) REFERENCES silver_viagem(id_viagem),
    -- constraint extra 2: valor nunca pode ser negativo
    CONSTRAINT chk_pagamento_valor CHECK (valor >= 0)
) ENGINE=InnoDB;

-- ---- Tabela dependente: trecho ----
CREATE TABLE silver_trecho (
    id_trecho         INT NOT NULL AUTO_INCREMENT,
    id_viagem         VARCHAR(20) NOT NULL,
    sequencia_trecho  INT,
    origem_data       DATE,
    origem_uf         VARCHAR(40),
    origem_cidade     VARCHAR(80),
    destino_data      DATE,
    destino_uf        VARCHAR(40),
    destino_cidade    VARCHAR(80),
    meio_transporte   VARCHAR(50),
    numero_diarias    DECIMAL(10,2),
    PRIMARY KEY (id_trecho),
    FOREIGN KEY (id_viagem) REFERENCES silver_viagem(id_viagem),
    -- constraint extra 1: numero de diarias nunca pode ser negativo
    CONSTRAINT chk_trecho_diarias CHECK (numero_diarias >= 0),
    -- constraint extra 2: nao pode haver dois trechos com a mesma sequencia
    -- dentro da mesma viagem
    CONSTRAINT uq_trecho UNIQUE (id_viagem, sequencia_trecho)
) ENGINE=InnoDB;


-- ===========================================================================
-- 4) RESUMO DAS CONSTRAINTS EXTRAS (alem de PK/FK) - ja nos CREATE TABLE acima
-- ---------------------------------------------------------------------------
--   silver_viagem    -> NOT NULL em nome_orgao_superior ; CHECK valor_diarias >= 0
--   silver_pagamento -> CHECK valor >= 0 ; NOT NULL em tipo_pagamento
--   silver_passagem  -> CHECK valor_passagem >= 0 ; CHECK taxa_servico >= 0
--   silver_trecho    -> CHECK numero_diarias >= 0 ; UNIQUE (id_viagem, sequencia_trecho)
-- ===========================================================================