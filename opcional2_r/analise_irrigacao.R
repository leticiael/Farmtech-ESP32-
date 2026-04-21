# =========================================================================
# FarmTech Solutions - Opcional 2
# Analise estatistica dos dados do viveiro de Araucaria angustifolia
#
# Tecnicas aplicadas (cobertura ampla do programa da disciplina de R da FIAP):
#   1. Estatistica descritiva        - summary, media, mediana, desvio-padrao
#   2. Coeficiente de variacao (CV)  - medida relativa de dispersao
#   3. Correlacao de Pearson         - forca e direcao entre as variaveis
#   4. Regressao linear simples      - umidade ~ pH (tecnica exigida FIAP)
#   5. Regressao logistica           - irrigou ~ todas as variaveis (decisao
#                                      de irrigacao como variavel binaria)
#
# Base simulada: 25 linhas em dados_sensores.csv com as colunas
#   umidade (%), ph (0-14), n, p, k (0/1 presente-ausente), irrigou (0/1)
#
# A regra de irrigacao implementada no ESP32 (sketh.ino) eh:
#   irrigou = (umidade < 60) AND (5 <= ph <= 7) AND (p == 1) AND (n OR k)
#
# Como rodar:
#   1. Instalar R (https://cran.r-project.org/) - R >= 4.0
#   2. No terminal, dentro desta pasta:
#        Rscript analise_irrigacao.R
#      Ou abrir no RStudio e rodar linha a linha.
#
# Dependencias: somente base R (sem pacotes externos).
# =========================================================================

# Para rodar independente da pasta em que foi chamado:
if (!interactive()) {
  args <- commandArgs(trailingOnly = FALSE)
  file_arg <- sub("^--file=", "", args[grep("^--file=", args)])
  if (length(file_arg) > 0 && nzchar(file_arg)) {
    setwd(dirname(normalizePath(file_arg)))
  }
}

cat(rep("=", 72), "\n", sep = "")
cat(" FarmTech - Analise estatistica (Opcional 2)\n")
cat(" Cultura: Araucaria angustifolia (pinheiro-do-parana)\n")
cat(rep("=", 72), "\n\n", sep = "")

# -------------------------------------------------------------------------
# 1. Leitura dos dados
# -------------------------------------------------------------------------
dados <- read.csv("dados_sensores.csv", stringsAsFactors = FALSE)

cat("[1] DADOS CARREGADOS\n")
cat("  linhas x colunas: ", nrow(dados), " x ", ncol(dados), "\n", sep = "")
cat("  colunas: ", paste(names(dados), collapse = ", "), "\n\n", sep = "")
print(head(dados, 6))
cat("\n")

# -------------------------------------------------------------------------
# 2. Estatistica descritiva
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[2] ESTATISTICA DESCRITIVA\n")
cat(rep("-", 72), "\n", sep = "")
print(summary(dados))
cat("\n")

# -------------------------------------------------------------------------
# 3. Coeficiente de variacao (CV = desvio-padrao / media * 100)
#    - CV < 15%  = baixa dispersao
#    - CV 15-30% = media dispersao
#    - CV > 30%  = alta dispersao
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[3] COEFICIENTE DE VARIACAO (CV)\n")
cat(rep("-", 72), "\n", sep = "")

cv <- function(x) {
  m <- mean(x, na.rm = TRUE)
  if (m == 0) return(NA_real_)
  sd(x, na.rm = TRUE) / m * 100
}

tab_cv <- data.frame(
  variavel = names(dados),
  media    = sapply(dados, function(x) round(mean(x, na.rm = TRUE), 3)),
  sd       = sapply(dados, function(x) round(sd(x, na.rm = TRUE), 3)),
  cv_pct   = sapply(dados, function(x) round(cv(x), 2)),
  row.names = NULL
)
print(tab_cv)

cat("\nInterpretacao:\n")
for (i in seq_len(nrow(tab_cv))) {
  v <- tab_cv$variavel[i]
  c <- tab_cv$cv_pct[i]
  if (is.na(c)) {
    nivel <- "indefinido (media zero)"
  } else if (c < 15) {
    nivel <- "BAIXA dispersao - dados homogeneos"
  } else if (c < 30) {
    nivel <- "MEDIA dispersao"
  } else {
    nivel <- "ALTA dispersao - dados heterogeneos"
  }
  cat("  - ", v, ": CV = ", c, "% -> ", nivel, "\n", sep = "")
}
cat("\n")

# -------------------------------------------------------------------------
# 4. Matriz de correlacao de Pearson
#    |r| proximo de 1 = forte associacao linear
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[4] MATRIZ DE CORRELACAO (Pearson)\n")
cat(rep("-", 72), "\n", sep = "")
mat_cor <- round(cor(dados), 3)
print(mat_cor)

cat("\nCorrelacoes com a variavel 'irrigou':\n")
cors_irr <- sort(mat_cor["irrigou", names(dados) != "irrigou"], decreasing = TRUE)
for (v in names(cors_irr)) {
  r <- cors_irr[[v]]
  forca <- if (abs(r) < 0.2) "muito fraca"
           else if (abs(r) < 0.4) "fraca"
           else if (abs(r) < 0.6) "moderada"
           else if (abs(r) < 0.8) "forte"
           else "muito forte"
  direcao <- if (r < 0) "negativa" else "positiva"
  cat("  - ", v, ": r = ", r, " (", forca, " ", direcao, ")\n", sep = "")
}
cat("\n")

# -------------------------------------------------------------------------
# 5. Regressao linear simples: umidade ~ ph
#    Exemplo pedagogico da tecnica (a disciplina de R da FIAP cobra).
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[5] REGRESSAO LINEAR SIMPLES: umidade ~ ph\n")
cat(rep("-", 72), "\n", sep = "")
modelo_lin <- lm(umidade ~ ph, data = dados)
print(summary(modelo_lin))

b0 <- coef(modelo_lin)[1]
b1 <- coef(modelo_lin)[2]
r2 <- summary(modelo_lin)$r.squared
cat(sprintf("\nEquacao: umidade = %.3f + %.3f * ph\n", b0, b1))
cat(sprintf("R-quadrado: %.4f (%.1f%% da variancia de umidade explicada pelo pH)\n",
            r2, r2 * 100))
if (r2 < 0.1) {
  cat("Interpretacao: umidade e pH sao praticamente independentes neste dataset,\n")
  cat("  o que faz sentido fisico - sao grandezas medidas por sensores distintos.\n")
}
cat("\n")

# -------------------------------------------------------------------------
# 6. Regressao logistica: irrigou ~ todas as variaveis
#    Modelo de decisao binaria (liga/desliga bomba).
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[6] REGRESSAO LOGISTICA: irrigou ~ umidade + ph + n + p + k\n")
cat(rep("-", 72), "\n", sep = "")

# suprime warnings de separacao perfeita (esperados - a regra eh deterministica)
modelo_log <- suppressWarnings(
  glm(irrigou ~ umidade + ph + n + p + k,
      data   = dados,
      family = binomial(link = "logit"))
)
print(summary(modelo_log))

# Qualidade: matriz de confusao com corte 0.5
prob   <- suppressWarnings(predict(modelo_log, type = "response"))
pred   <- as.integer(prob >= 0.5)
confm  <- table(observado = dados$irrigou, previsto = pred)

cat("\nMatriz de confusao (corte 0.5):\n")
print(confm)

acerto <- sum(diag(confm)) / sum(confm)
cat(sprintf("\nAcuracia: %.1f%% (%d de %d linhas)\n",
            acerto * 100, sum(diag(confm)), sum(confm)))

cat("\nInterpretacao dos coeficientes (odds ratio = exp(beta)):\n")
odds <- round(exp(coef(modelo_log)), 3)
for (v in names(odds)) {
  cat("  - ", v, ": OR = ", odds[[v]], "\n", sep = "")
}
cat("  OR > 1 aumenta chance de irrigar; OR < 1 diminui.\n")
cat("  Aviso: com n=25 e regra deterministica, os erros-padrao sao grandes\n")
cat("  (problema de 'separacao perfeita') - esperado neste cenario didatico.\n\n")

# -------------------------------------------------------------------------
# 7. Graficos - salva como PNG na pasta atual
# -------------------------------------------------------------------------
cat(rep("-", 72), "\n", sep = "")
cat("[7] GRAFICOS\n")
cat(rep("-", 72), "\n", sep = "")

# 7a. Boxplot: umidade por decisao de irrigar
# Paleta e tema visual consistentes
cor_irrig    <- "#2E8B57"
cor_nao      <- "#C0392B"
cor_seco     <- "#1F77B4"
cor_enchar   <- "#8E44AD"
cor_ph       <- "#E67E22"
cor_neutro   <- "#34495E"
fundo        <- "#FAFAFA"
grade        <- "#E5E5E5"

setup_tema <- function() {
  par(bg = fundo, family = "sans",
      mar = c(5, 5, 4.5, 2),
      mgp = c(2.8, 0.7, 0),
      tcl = -0.3, las = 1, cex.axis = 0.95, cex.lab = 1.05,
      cex.main = 1.25, font.main = 2, col.main = cor_neutro,
      col.axis = cor_neutro, col.lab = cor_neutro,
      fg = cor_neutro)
}
grade_h <- function() {
  usr <- par("usr")
  yt  <- pretty(c(usr[3], usr[4]))
  abline(h = yt, col = grade, lwd = 0.8)
}

# 7a. Boxplot: umidade por decisao de irrigar
png("grafico_boxplot_umidade.png", width = 1100, height = 750, res = 140)
setup_tema()
boxplot(umidade ~ irrigou, data = dados,
        names    = c("Nao irrigou", "Irrigou"),
        col      = c(adjustcolor(cor_nao, 0.75),
                     adjustcolor(cor_irrig, 0.75)),
        border   = c(cor_nao, cor_irrig),
        boxwex   = 0.55, lwd = 1.6,
        outpch   = 21, outbg = "white", outcol = cor_neutro,
        main     = "Umidade do solo por decisao de irrigacao",
        ylab     = "Umidade (%)", xlab = "Decisao da bomba")
grade_h()
boxplot(umidade ~ irrigou, data = dados,
        col = c(adjustcolor(cor_nao, 0.75), adjustcolor(cor_irrig, 0.75)),
        border = c(cor_nao, cor_irrig), boxwex = 0.55, lwd = 1.6,
        outpch = 21, outbg = "white", outcol = cor_neutro,
        add = TRUE, axes = FALSE)
set.seed(1)
xj <- jitter(as.numeric(factor(dados$irrigou)), amount = 0.08)
points(xj, dados$umidade, pch = 21,
       bg = adjustcolor(ifelse(dados$irrigou == 1, cor_irrig, cor_nao), 0.7),
       col = "white", cex = 1.2)
abline(h = 60, lty = 2, col = cor_seco,   lwd = 1.6)
abline(h = 75, lty = 2, col = cor_enchar, lwd = 1.6)
legend("topright", inset = 0.02, bty = "n", cex = 0.85,
       legend = c("Limiar seco (60%)", "Limiar encharcado (75%)"),
       col = c(cor_seco, cor_enchar), lty = 2, lwd = 1.6,
       bg = "white", box.col = grade)
invisible(dev.off())

# 7b. Barras: coeficiente de variacao por variavel
png("grafico_cv.png", width = 1100, height = 750, res = 140)
setup_tema()
ord     <- order(tab_cv$cv_pct)
vals    <- tab_cv$cv_pct[ord]
labs    <- tab_cv$variavel[ord]
cores_b <- ifelse(vals < 15, "#27AE60",
           ifelse(vals < 30, "#F1C40F", "#E74C3C"))
ymax <- max(vals) * 1.18
bp <- barplot(vals, names.arg = labs,
              col = cores_b, border = NA, ylim = c(0, ymax),
              main = "Coeficiente de variacao (%) por variavel",
              ylab = "CV (%)", xlab = "Variavel")
grade_h()
barplot(vals, col = cores_b, border = NA, add = TRUE, axes = FALSE)
abline(h = c(15, 30), lty = 2, col = c("#27AE60", "#E74C3C"), lwd = 1.4)
text(bp, vals, labels = sprintf("%.1f%%", vals),
     pos = 3, offset = 0.4, cex = 0.85, col = cor_neutro, font = 2)
legend("topleft", inset = 0.02, bty = "n", cex = 0.8,
       legend = c("Baixa (<15%)", "Media (15-30%)", "Alta (>30%)"),
       fill = c("#27AE60", "#F1C40F", "#E74C3C"), border = NA)
invisible(dev.off())

# 7c. Scatter: umidade vs pH colorido por irrigacao
png("grafico_scatter_umid_ph.png", width = 1100, height = 750, res = 140)
setup_tema()
cores <- ifelse(dados$irrigou == 1, cor_irrig, cor_nao)
plot(dados$ph, dados$umidade, type = "n",
     xlim = c(2, 10), ylim = c(20, max(dados$umidade) + 8),
     main = "Umidade x pH por decisao de irrigacao",
     xlab = "pH do solo", ylab = "Umidade (%)")
grade_h()
abline(v = pretty(c(2, 10)), col = grade, lwd = 0.8)
rect(5, par("usr")[3], 7, par("usr")[4],
     col = adjustcolor(cor_ph, 0.10), border = NA)
abline(h = 60, lty = 2, col = cor_seco,   lwd = 1.6)
abline(h = 75, lty = 2, col = cor_enchar, lwd = 1.6)
abline(v = c(5, 7), lty = 2, col = cor_ph, lwd = 1.6)
points(jitter(dados$ph, 0.6), dados$umidade,
       pch = 21, bg = adjustcolor(cores, 0.8),
       col = "white", cex = 1.7, lwd = 1.2)
legend("topright", inset = 0.02, bty = "o", cex = 0.85,
       bg = "white", box.col = grade,
       legend = c("Irrigou", "Nao irrigou",
                  "Faixa pH ideal (5-7)",
                  "Umidade 60% (seco)",
                  "Umidade 75% (encharcado)"),
       col = c(cor_irrig, cor_nao, cor_ph, cor_seco, cor_enchar),
       pch = c(19, 19, NA, NA, NA),
       lty = c(NA, NA, 2, 2, 2), lwd = c(NA, NA, 1.6, 1.6, 1.6))
invisible(dev.off())

cat("  Graficos salvos:\n")
cat("    - grafico_boxplot_umidade.png\n")
cat("    - grafico_cv.png\n")
cat("    - grafico_scatter_umid_ph.png\n\n")

# -------------------------------------------------------------------------
# 8. Conclusao automatica
# -------------------------------------------------------------------------
cat(rep("=", 72), "\n", sep = "")
cat(" CONCLUSAO\n")
cat(rep("=", 72), "\n", sep = "")
cat(sprintf(
  " - Dos %d registros, %d (%.0f%%) resultaram em irrigacao.\n",
  nrow(dados), sum(dados$irrigou), mean(dados$irrigou) * 100))
cat(sprintf(
  " - Umidade media: %.1f%% (CV=%.1f%%).\n",
  mean(dados$umidade), cv(dados$umidade)))
cat(sprintf(
  " - pH medio: %.1f (faixa observada %d-%d).\n",
  mean(dados$ph), min(dados$ph), max(dados$ph)))
cat(sprintf(
  " - Modelo logistico classificou corretamente %.0f%% dos casos.\n",
  acerto * 100))
cat(" - A variavel 'p' (fosforo) eh critica - sem P, irrigacao sempre = 0.\n")
cat(rep("=", 72), "\n", sep = "")
