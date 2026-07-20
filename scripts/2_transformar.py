"""
2_transformar.py  -  FASE 2: Transformacao e Camada SILVER
----------------------------------------------------------
Pega os dados "sujos" da camada RAW (tudo texto) e preenche as tabelas SILVER
(ja criadas, com PK/FK e constraints, pelo 0_criar_banco.sql) com os dados
limpos e tipados.

A receita e simples: rodamos alguns comandos SQL, em ordem.
  1. Esvaziamos as tabelas SILVER (para nao duplicar se rodar de novo).
  2. Copiamos da RAW para a SILVER, convertendo os tipos.
  3. Calculamos as colunas derivadas (valor_total e duracao_dias).
  4. Conferimos a quantidade de linhas em cada tabela.

------------------------------------------------------------------------------
COMO CONVERTEMOS O TEXTO DA CAMADA RAW (esse padrao se repete no SQL abaixo):

  - Dinheiro: "1272,97" (texto)  ->  1272.97 (numero DECIMAL)
      tira o ponto de milhar, troca a virgula por ponto e faz CAST:
      CAST(REPLACE(REPLACE(NULLIF(TRIM(coluna), ''), '.', ''), ',', '.') AS DECIMAL(10,2))

  - Data: "01/03/2025" (texto)  ->  2025-03-01 (tipo DATE)
      STR_TO_DATE(NULLIF(TRIM(coluna), ''), '%d/%m/%Y')

  Obs.: NULLIF(coluna, '') transforma um campo vazio em NULL (vazio no banco).
        E o que resolve as datas de emissao em branco da tabela de passagens.
------------------------------------------------------------------------------

ORDEM DE CARGA: silver_viagem e a tabela principal (PRIMARY KEY id_viagem).
As outras tres apontam para ela com FOREIGN KEY. Por isso:
  - para APAGAR, comecamos pelas filhas e terminamos na principal;
  - para INSERIR, comecamos pela principal e depois as filhas.
"""

import banco


# ---------------------------------------------------------------------------
# 1) Esvaziar as tabelas SILVER (idempotencia).
#    A ordem importa por causa da FK: apagamos a filha (itens) antes da principal.
# ---------------------------------------------------------------------------
LIMPAR_SILVER = [
    "DELETE FROM silver_pagamento",
    "DELETE FROM silver_passagem",
    "DELETE FROM silver_trecho",
    "DELETE FROM silver_viagem",
]


# ---------------------------------------------------------------------------
# 2) Copiar RAW -> SILVER convertendo os tipos.
# ---------------------------------------------------------------------------
# A Raw tem colunas que a Silver nao usa (cpf_viajante, funcao, orgao
# solicitante, justificativa da urgencia). Por isso listamos coluna a coluna.
# Obs.: nome_orgao_superior e NOT NULL na Silver, entao usamos so TRIM (sem
# NULLIF) para nao transformar um texto vazio em NULL e quebrar a constraint.
SQL_VIAGEM = """
INSERT INTO silver_viagem (
    id_viagem, num_proposta, situacao, viagem_urgente,
    cod_orgao_superior, nome_orgao_superior, nome_viajante, cargo,
    data_inicio, data_fim, destinos, motivo,
    valor_diarias, valor_passagens, valor_devolucao, valor_outros_gastos
)
SELECT
    TRIM(id_viagem),
    NULLIF(TRIM(num_proposta), ''),
    NULLIF(TRIM(situacao), ''),
    NULLIF(TRIM(viagem_urgente), ''),
    NULLIF(TRIM(cod_orgao_superior), ''),
    TRIM(nome_orgao_superior),
    NULLIF(TRIM(nome_viajante), ''),
    NULLIF(TRIM(cargo), ''),
    STR_TO_DATE(NULLIF(TRIM(data_inicio), ''), '%d/%m/%Y'),
    STR_TO_DATE(NULLIF(TRIM(data_fim), ''), '%d/%m/%Y'),
    NULLIF(TRIM(destinos), ''),
    NULLIF(TRIM(motivo), ''),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor_diarias),       ''), '.', ''), ',', '.') AS DECIMAL(10,2)),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor_passagens),     ''), '.', ''), ',', '.') AS DECIMAL(10,2)),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor_devolucao),     ''), '.', ''), ',', '.') AS DECIMAL(10,2)),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor_outros_gastos), ''), '.', ''), ',', '.') AS DECIMAL(10,2))
FROM raw_viagem
"""

# Nas tres tabelas filhas, o WHERE ... IN (SELECT id_viagem FROM silver_viagem)
# garante a integridade referencial: so entra o registro cuja viagem existe.
SQL_PAGAMENTO = """
INSERT INTO silver_pagamento (
    id_viagem, num_proposta, nome_orgao_pagador, nome_ug_pagadora,
    tipo_pagamento, valor
)
SELECT
    TRIM(id_viagem),
    NULLIF(TRIM(num_proposta), ''),
    NULLIF(TRIM(nome_orgao_pagador), ''),
    NULLIF(TRIM(nome_ug_pagadora), ''),
    TRIM(tipo_pagamento),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor), ''), '.', ''), ',', '.') AS DECIMAL(10,2))
FROM raw_pagamento
WHERE TRIM(id_viagem) IN (SELECT id_viagem FROM silver_viagem)
"""

SQL_PASSAGEM = """
INSERT INTO silver_passagem (
    id_viagem, meio_transporte,
    pais_origem_ida, uf_origem_ida, cidade_origem_ida,
    pais_destino_ida, uf_destino_ida, cidade_destino_ida,
    valor_passagem, taxa_servico, data_emissao
)
SELECT
    TRIM(id_viagem),
    NULLIF(TRIM(meio_transporte), ''),
    NULLIF(TRIM(pais_origem_ida), ''),
    NULLIF(TRIM(uf_origem_ida), ''),
    NULLIF(TRIM(cidade_origem_ida), ''),
    NULLIF(TRIM(pais_destino_ida), ''),
    NULLIF(TRIM(uf_destino_ida), ''),
    NULLIF(TRIM(cidade_destino_ida), ''),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(valor_passagem), ''), '.', ''), ',', '.') AS DECIMAL(10,2)),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(taxa_servico),   ''), '.', ''), ',', '.') AS DECIMAL(10,2)),
    STR_TO_DATE(NULLIF(TRIM(data_emissao), ''), '%d/%m/%Y')
FROM raw_passagem
WHERE TRIM(id_viagem) IN (SELECT id_viagem FROM silver_viagem)
"""

SQL_TRECHO = """
INSERT INTO silver_trecho (
    id_viagem, sequencia_trecho,
    origem_data, origem_uf, origem_cidade,
    destino_data, destino_uf, destino_cidade,
    meio_transporte, numero_diarias
)
SELECT
    TRIM(id_viagem),
    CAST(NULLIF(TRIM(sequencia_trecho), '') AS UNSIGNED),
    STR_TO_DATE(NULLIF(TRIM(origem_data), ''), '%d/%m/%Y'),
    NULLIF(TRIM(origem_uf), ''),
    NULLIF(TRIM(origem_cidade), ''),
    STR_TO_DATE(NULLIF(TRIM(destino_data), ''), '%d/%m/%Y'),
    NULLIF(TRIM(destino_uf), ''),
    NULLIF(TRIM(destino_cidade), ''),
    NULLIF(TRIM(meio_transporte), ''),
    CAST(REPLACE(REPLACE(NULLIF(TRIM(numero_diarias), ''), '.', ''), ',', '.') AS DECIMAL(10,2))
FROM raw_trecho
WHERE TRIM(id_viagem) IN (SELECT id_viagem FROM silver_viagem)
"""


# ---------------------------------------------------------------------------
# 3) Calcular as colunas derivadas.
#    Agora que os valores ja sao numeros e as datas ja sao DATE, a conta fica
#    facil. COALESCE(coluna, 0) usa 0 quando o valor for NULL (vazio), para a
#    soma nao virar NULL inteira.
# ---------------------------------------------------------------------------
# REGRA DE NEGOCIO 1 - valor_total:
#   diarias + passagens + outros gastos - devolucao.
#   A devolucao e dinheiro que voltou aos cofres publicos; somar ela inflaria
#   o gasto real. Se quiser o total bruto (sem descontar), apague a linha do
#   valor_devolucao abaixo -- e registre a escolha no README.
#
# REGRA DE NEGOCIO 2 - duracao_dias:
#   DATEDIFF(fim, inicio) + 1, contando o dia de inicio.
#   Assim uma viagem que comeca e termina no mesmo dia dura 1 dia, e nao 0.
#   Para usar a diferenca pura, tire o "+ 1".
SQL_CALC_VIAGEM = """
UPDATE silver_viagem
SET valor_total = COALESCE(valor_diarias, 0)
                + COALESCE(valor_passagens, 0)
                + COALESCE(valor_outros_gastos, 0)
                - COALESCE(valor_devolucao, 0),
    duracao_dias = DATEDIFF(data_fim, data_inicio) + 1
"""


# ---------------------------------------------------------------------------
# 4) Conferencia final
# ---------------------------------------------------------------------------
TABELAS = [
    ("raw_viagem",    "silver_viagem"),
    ("raw_pagamento", "silver_pagamento"),
    ("raw_passagem",  "silver_passagem"),
    ("raw_trecho",    "silver_trecho"),
]


def contar(conexao, tabela):
    """Devolve quantas linhas existem na tabela."""
    cursor = conexao.cursor()
    cursor.execute(f"SELECT COUNT(*) FROM {tabela}")
    (total,) = cursor.fetchone()
    cursor.close()
    return total


# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------
def main():
    print("=== FASE 2: TRANSFORMACAO + CAMADA SILVER ===")
    try:
        conexao = banco.conectar()

        print("[1/4] Esvaziando as tabelas SILVER...")
        for comando in LIMPAR_SILVER:
            banco.executar(conexao, comando)

        print("[2/4] Copiando e convertendo RAW -> SILVER...")
        banco.executar(conexao, SQL_VIAGEM)
        print("      silver_viagem    OK")
        banco.executar(conexao, SQL_PAGAMENTO)
        print("      silver_pagamento OK")
        banco.executar(conexao, SQL_PASSAGEM)
        print("      silver_passagem  OK")
        banco.executar(conexao, SQL_TRECHO)
        print("      silver_trecho    OK")

        print("[3/4] Calculando valor_total e duracao_dias...")
        banco.executar(conexao, SQL_CALC_VIAGEM)

        print("[4/4] Conferindo as linhas carregadas (raw -> silver)...")
        for tabela_raw, tabela_silver in TABELAS:
            linhas_raw = contar(conexao, tabela_raw)
            linhas_silver = contar(conexao, tabela_silver)
            aviso = "" if linhas_raw == linhas_silver else "  <-- houve descarte"
            print(f"      {tabela_silver:<17} {linhas_silver} de {linhas_raw}{aviso}")

        conexao.close()
        print("=== Camada SILVER concluida com sucesso! ===")
    except Exception as erro:
        print("[ERRO] Algo deu errado:", erro)
        raise


if __name__ == "__main__":
    main()
