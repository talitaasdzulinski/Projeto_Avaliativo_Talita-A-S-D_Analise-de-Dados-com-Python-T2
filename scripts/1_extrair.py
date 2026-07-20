"""
1_extrair.py  -  FASE 1: Extracao e Camada RAW
----------------------------------------------
Passo a passo simples:
  1. Garante que o arquivo viagens.zip esta na pasta data/
     (se nao estiver, baixa automaticamente do Google Drive usando o
     DRIVE_FILE_ID configurado no config.py).
  2. Le os 4 CSVs de dentro do .zip (viagem, pagamento, passagem, trecho).
  3. Insere os dados, SEM nenhuma alteracao, nas 4 tabelas RAW do MySQL.

A camada RAW e uma copia fiel do CSV: todas as colunas sao texto (VARCHAR).
As tabelas ja foram criadas pelo script 0_criar_banco.sql.
"""

import zipfile

import gdown
import pandas as pd

import config
import banco


# -------------------------------------------------------------------
# Passo 1 - Baixar o arquivo .zip do Google Drive
# -------------------------------------------------------------------

def baixar_zip():
    """Baixa o .zip do Drive (só se ele ainda não estiver na pasta data/)."""

    config.PASTA_DADOS.mkdir(exist_ok=True)
    destino = config.PASTA_DADOS / "viagens.zip"

    if destino.exists():
        print("[1/3] O arquivo já foi baixado antes - pulando o download.")
    else:
        print("[1/3] Baixando o arquivo do Google Drive...")
        gdown.download(id=config.DRIVE_FILE_ID, output=str(destino))

    return destino

# ---------------------------------------------------------------------------
# Passo 2 - Carregar um CSV dentro da sua tabela RAW
# ---------------------------------------------------------------------------
def carregar_csv(conexao, zip_aberto, nome_csv, tabela):
    """Le um CSV de dentro do zip e insere todas as linhas na tabela do MySQL.

    As colunas do CSV estao na MESMA ordem das colunas da tabela
    (definidas no 0_criar_banco.txt). Por isso conseguimos inserir "na ordem",
    sem precisar escrever o nome de cada coluna.
    """
    print("      Carregando", tabela, "...")

    # esvazia a tabela antes de carregar (assim, rodar de novo nao duplica dados)
    banco.executar(conexao, f"TRUNCATE TABLE {tabela}")

    total = 0
    with zip_aberto.open(nome_csv) as arquivo:
        # le o CSV em pedacos, para nao encher a memoria do PC (bases grandes)
        pedacos = pd.read_csv(
            arquivo,
            sep=";",                       # colunas separadas por ponto-e-virgula
            encoding="latin-1",            # acentuacao em latin-1
            dtype=str,                     # tudo como texto (camada RAW)
            keep_default_na=False,         # campo vazio continua "" (nao vira "NaN")
            chunksize=config.TAMANHO_BLOCO,
        )
        for pedaco in pedacos:
            linhas = pedaco.values.tolist()
            # um "%s" para cada coluna do CSV
            marcadores = ", ".join(["%s"] * len(pedaco.columns))
            comando = f"INSERT INTO {tabela} VALUES ({marcadores})"
            banco.inserir_em_lote(conexao, comando, linhas)
            total += len(linhas)

    print("      ->", total, "linhas em", tabela)


# ---------------------------------------------------------------------------
# Programa principal
# ---------------------------------------------------------------------------
def main():
    print("=== FASE 1: EXTRACAO + CAMADA RAW ===")
    try:
        conexao = banco.conectar()

        caminho_zip = baixar_zip()
        print("[2/3] Abrindo o arquivo zip...")
        print("[3/3] Carregando as 4 tabelas RAW...")
        with zipfile.ZipFile(caminho_zip) as zip_aberto:
            for arquivo in config.ARQUIVOS.values():
                carregar_csv(conexao, zip_aberto, arquivo["csv"], arquivo["tabela_raw"])

        conexao.close()
        print("=== Camada RAW concluida com sucesso! ===")
    except Exception as erro:
        print("[ERRO] Algo deu errado:", erro)
        raise


if __name__ == "__main__":
    main()
