"""
FarmTech Solutions - Opcional 1
Consulta previsao do tempo (OpenWeather) e recomenda suspender irrigacao se
for chover nas proximas horas.

Cultura: Araucaria angustifolia (pinheiro-do-parana) - viveiro em Curitiba/PR.
Faz sentido suspender a irrigacao quando chuva esta prevista porque:
  - solo encharcado (umidade > 75%) causa podridao radicular em arauc\u00e1ria jovem;
  - irrigar de manha e chover de tarde = desperdicio de agua e lixiviacao de
    nutrientes (N, P e K sao aplicados em fertilizacao separada).

Integracao com o ESP32 do Wokwi: MANUAL.
O script imprime uma linha final pronta pra copiar no Serial Monitor ou uma
flag (0/1) pra trocar no sketch; o ESP32 nao se conecta na internet neste
simulador.

Como rodar:
  1. Criar conta gratis em https://home.openweathermap.org/users/sign_up
  2. Pegar a API key em https://home.openweathermap.org/api_keys
     (a chave demora ~10 min pra ativar apos o cadastro)
  3. Exportar a chave como variavel de ambiente:
       Windows (PowerShell):  $env:OPENWEATHER_API_KEY = "sua_chave"
       Windows (cmd):         set OPENWEATHER_API_KEY=sua_chave
       Linux/macOS:           export OPENWEATHER_API_KEY=sua_chave
  4. Rodar:
       python openweather_check.py
     Ou passando cidade:
       python openweather_check.py "Curitiba,BR"
       python openweather_check.py "Sao Paulo,BR" --horas 6

Dependencias: nenhuma externa (so biblioteca padrao).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone

# -------------------------------------------------------------------------
# Configuracao
# -------------------------------------------------------------------------
CIDADE_PADRAO = "Curitiba,BR"
HORAS_JANELA_PADRAO = 12          # olha as proximas 12h de previsao
LIMIAR_POP = 0.50                 # >= 50% de probabilidade de chuva = suspende
LIMIAR_MM = 1.0                   # >= 1 mm em 3h tambem suspende
API_URL = "https://api.openweathermap.org/data/2.5/forecast"


# -------------------------------------------------------------------------
# Chamada da API
# -------------------------------------------------------------------------
def consulta_previsao(cidade: str, api_key: str) -> dict:
    """
    Consulta o endpoint /forecast do OpenWeather (previsao 5 dias / 3h).
    Retorna o JSON decodificado como dict. Lanca RuntimeError em caso de erro.
    """
    params = {
        "q": cidade,
        "appid": api_key,
        "units": "metric",
        "lang": "pt_br",
    }
    url = f"{API_URL}?{urllib.parse.urlencode(params)}"

    try:
        req = urllib.request.Request(url, headers={"User-Agent": "FarmTech/1.0"})
        with urllib.request.urlopen(req, timeout=15) as resp:
            corpo = resp.read().decode("utf-8")
            return json.loads(corpo)
    except urllib.error.HTTPError as e:
        # OpenWeather retorna 401 com JSON explicando se a chave esta invalida
        detalhe = ""
        try:
            detalhe = json.loads(e.read().decode("utf-8")).get("message", "")
        except Exception:
            pass
        raise RuntimeError(
            f"Erro HTTP {e.code} ao consultar OpenWeather: {detalhe or e.reason}"
        ) from e
    except urllib.error.URLError as e:
        raise RuntimeError(f"Falha de rede: {e.reason}") from e


# -------------------------------------------------------------------------
# Analise da previsao
# -------------------------------------------------------------------------
def analisa_chuva(previsao: dict, horas_janela: int) -> dict:
    """
    Recebe o JSON do OpenWeather e retorna um resumo da chuva prevista
    dentro da janela (proximas N horas), ja aplicando os limiares de decisao.
    """
    agora = datetime.now(timezone.utc)
    limite = agora.timestamp() + horas_janela * 3600

    blocos = previsao.get("list", [])
    blocos_janela = [b for b in blocos if b.get("dt", 0) <= limite]

    total_mm = 0.0
    max_pop = 0.0
    blocos_com_chuva = []

    for b in blocos_janela:
        pop = float(b.get("pop", 0.0))          # 0..1 - probabilidade de precip.
        mm = float(b.get("rain", {}).get("3h", 0.0))  # mm em 3h (se chover)
        descr = b.get("weather", [{}])[0].get("description", "")
        horario = datetime.fromtimestamp(b["dt"], tz=timezone.utc).astimezone()

        total_mm += mm
        if pop > max_pop:
            max_pop = pop

        if pop >= 0.30 or mm > 0.0:
            blocos_com_chuva.append(
                {
                    "quando": horario.strftime("%d/%m %Hh"),
                    "pop_pct": round(pop * 100),
                    "mm_3h": round(mm, 1),
                    "descricao": descr,
                }
            )

    vai_chover = (max_pop >= LIMIAR_POP) or (total_mm >= LIMIAR_MM)

    return {
        "cidade": f"{previsao.get('city', {}).get('name', '?')}, "
                  f"{previsao.get('city', {}).get('country', '?')}",
        "horas_janela": horas_janela,
        "blocos_analisados": len(blocos_janela),
        "max_pop_pct": round(max_pop * 100),
        "total_mm": round(total_mm, 1),
        "blocos_com_chuva": blocos_com_chuva,
        "vai_chover": vai_chover,
    }


def recomendacao(resumo: dict) -> tuple[str, str]:
    """Retorna (decisao, motivo) baseado no resumo."""
    if resumo["vai_chover"]:
        motivo = (
            f"chuva prevista: POP maxima {resumo['max_pop_pct']}% e "
            f"acumulado {resumo['total_mm']} mm nas proximas "
            f"{resumo['horas_janela']}h"
        )
        return "SUSPENDER", motivo
    motivo = (
        f"sem chuva relevante prevista (POP max {resumo['max_pop_pct']}%, "
        f"acumulado {resumo['total_mm']} mm)"
    )
    return "PROSSEGUIR", motivo


# -------------------------------------------------------------------------
# Relatorio no terminal
# -------------------------------------------------------------------------
def imprime_relatorio(resumo: dict) -> None:
    decisao, motivo = recomendacao(resumo)
    flag_irrigar = 0 if decisao == "SUSPENDER" else 1

    print()
    print("=" * 60)
    print(" FarmTech - Checagem de chuva (OpenWeather)")
    print("=" * 60)
    print(f" Cidade:         {resumo['cidade']}")
    print(f" Janela:         proximas {resumo['horas_janela']}h")
    print(f" Blocos 3h:      {resumo['blocos_analisados']} analisados")
    print(f" POP maxima:     {resumo['max_pop_pct']}%")
    print(f" Chuva total:    {resumo['total_mm']} mm")
    print("-" * 60)

    if resumo["blocos_com_chuva"]:
        print(" Blocos com chuva prevista:")
        for b in resumo["blocos_com_chuva"]:
            print(f"   - {b['quando']}  pop={b['pop_pct']}%  "
                  f"mm={b['mm_3h']}  ({b['descricao']})")
    else:
        print(" Nenhum bloco com chuva relevante.")
    print("-" * 60)
    print(f" RECOMENDACAO:  {decisao}")
    print(f" Motivo:        {motivo}")
    print("=" * 60)
    print()
    print(" Linha pronta pro Serial Monitor do Wokwi:")
    print(f"   CHUVA_PREVISTA={int(resumo['vai_chover'])}  "
          f"IRRIGAR_MANUAL={flag_irrigar}  "
          f"// {decisao}")
    print()


# -------------------------------------------------------------------------
# CLI
# -------------------------------------------------------------------------
def main() -> int:
    parser = argparse.ArgumentParser(
        description="Checa previsao do tempo e recomenda suspender irrigacao."
    )
    parser.add_argument(
        "cidade",
        nargs="?",
        default=CIDADE_PADRAO,
        help=f'cidade no formato "Nome,PaisISO" (padrao: {CIDADE_PADRAO})',
    )
    parser.add_argument(
        "--horas",
        type=int,
        default=HORAS_JANELA_PADRAO,
        help=f"janela em horas para checar chuva (padrao: {HORAS_JANELA_PADRAO})",
    )
    args = parser.parse_args()

    api_key = os.environ.get("OPENWEATHER_API_KEY", "").strip()
    if not api_key:
        print(
            "ERRO: variavel de ambiente OPENWEATHER_API_KEY nao definida.\n"
            "  Cadastro gratis: https://home.openweathermap.org/users/sign_up\n"
            "  Depois exporte a chave:\n"
            '    PowerShell:  $env:OPENWEATHER_API_KEY = "sua_chave"\n'
            "    cmd:         set OPENWEATHER_API_KEY=sua_chave\n"
            "    bash:        export OPENWEATHER_API_KEY=sua_chave",
            file=sys.stderr,
        )
        return 2

    try:
        previsao = consulta_previsao(args.cidade, api_key)
    except RuntimeError as e:
        print(f"ERRO: {e}", file=sys.stderr)
        return 1

    resumo = analisa_chuva(previsao, args.horas)
    imprime_relatorio(resumo)
    # exit code: 0 se PROSSEGUIR, 10 se SUSPENDER (util pra scripts/automacao)
    return 10 if resumo["vai_chover"] else 0


if __name__ == "__main__":
    sys.exit(main())
