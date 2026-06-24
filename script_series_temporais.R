############ REPOSITÓRIO: analise-series-temporais-sarima ############
# Pipeline de Modelagem Preditiva e Forecasting (Escola Box-Jenkins)
# Autor: Mateus Vieira Costa

# ---- 1. Carregar Bibliotecas Necessárias ----
library(readxl)
library(ggplot2)
library(dplyr)
library(pracma)
library(forecast)
library(aTSA)
library(astsa)

# Configurar diretório de saída para os gráficos
if(!dir.exists("Plots")) dir.create("Plots")

# ---- 2. Carga e Engenharia de Atributos (Data Prep) ----
path_dados <- "data/ConsumoEnergiaEAgua.xlsx"

if (!file.exists(path_dados)) {
  stop("Erro: O arquivo de dados não foi encontrado em 'data/ConsumoEnergiaEAgua.xlsx'. Por favor, posicione-o na pasta correta.")
}

dados <- read_excel(path_dados, 
                    col_types = c("date", "date", "numeric", "numeric",
                                  "numeric", "numeric", "numeric", "numeric", 
                                  "numeric", "numeric", "numeric"))

# Limpeza e transformação de dados (Taxa de consumo diário)
Xt <- na.omit(dados$Energia)
Dt <- na.omit(dados$Dias)
Yt <- Xt / Dt
t  <- na.omit(dados$mes)

# Remoção de inconsistências/valores vazios no final da série
t <- t[-c((length(t)-2):length(t))]
condados <- data.frame(t = t, Xt = Xt[1:length(t)], Dt = Dt[1:length(t)], Yt = Yt[1:length(t)])

# ---- 3. Análise Exploratória e Estacionaridade (FAC/FACP) ----

# Gráfico de Evolução Temporal da Série Original
p_evoluçao <- ggplot(data = condados, aes(x = t, y = Yt)) + 
  geom_line(color = "darkblue", size = 0.7) + 
  labs(y = "Consumo Médio de Energia (kWh/dia)", x = "Mês/Ano",
       title = "Evolução Temporal do Consumo Médio de Energia") + 
  theme_minimal()
print(p_evoluçao)
ggsave("Plots/grafico2.png", plot = p_evoluçao, width = 8, height = 5)

# Diagnóstico de Não-Estacionaridade (FAC e FACP originais)
png("Plots/grafico3_fac_original.png", width = 800, height = 400)
par(mfrow = c(1, 2))
acf(condados$Yt, lag.max = 36, main = "FAC - Série Original")
pacf(condados$Yt, lag.max = 36, main = "FACP - Série Original")
dev.off()

# Teste Formal de Raiz Unitária (Dickey-Fuller Aumentado)
serie_ts <- ts(condados$Yt, frequency = 12)
print("--- Teste ADF para Série Original ---")
adf.test(serie_ts)

# Modelagem Harmônica de Baseline (Avaliação de Sazonalidade Determinística)
n <- length(condados$Yt)
harmonica <- data.frame(
  time = 1:n,
  cos1 = cos(2 * pi * (1:n) / 12),
  sin1 = sin(2 * pi * (1:n) / 12),
  cos2 = cos(4 * pi * (1:n) / 12),
  sin2 = sin(4 * pi * (1:n) / 12)
)
modeloharm <- lm(serie_ts ~ cos1 + sin1 + cos2 + sin2, data = harmonica)
print(summary(modeloharm))

# ---- 4. Transformação por Diferenciação Regular (d=1) ----
condados$zt <- c(NA, diff(condados$Yt))

# Gráfico da Série Diferenciada
p_diferenciada <- ggplot(data = condados, aes(x = t, y = zt)) + 
  geom_line(color = "darkred", size = 0.5) + 
  labs(y = "Variação do Consumo Médio", x = "Mês/Ano",
       title = "Variação do Consumo Médio de Energia (Série Diferenciada d=1)") + 
  theme_minimal()
print(p_diferenciada)
ggsave("Plots/grafico6.png", plot = p_diferenciada, width = 8, height = 5)

# Diagnóstico de Estacionaridade pós-diferenciação
png("Plots/grafico7_fac_diferenciada.png", width = 800, height = 400)
par(mfrow = c(1, 2))
acf(na.omit(condados$zt), lag.max = 36, main = "FAC - Diferenciada (d=1)")
pacf(na.omit(condados$zt), lag.max = 36, main = "FACP - Diferenciada (d=1)")
dev.off()

seriezt <- ts(na.omit(condados$zt), frequency = 12)
print("--- Teste ADF para Série Diferenciada ---")
adf.test(seriezt)

# ---- 5. Divisão Treino/Validação & Grid Search por Mínimo BIC ----
n_treinamento  <- ceiling(3 * n / 4)
Yt_treinamento <- condados$Yt[1:n_treinamento]

print("Iniciando Grid Search Automatizado para Ordem SARIMA (Amostragem por BIC)...")
BIC_matrix <- NULL
grid_regular <- 0:4
grid_sazonal <- 0:2

# Loop de varredura de hiperparâmetros
for (p.grid in grid_regular) {
  for (q.grid in grid_regular) {
    for (P.grid in grid_sazonal) {
      for (Q.grid in grid_sazonal) {
        tryCatch({
          # Estimação via função sarima do pacote astsa
          draft <- sarima(Yt_treinamento, p.grid, 1, q.grid, P = P.grid, D = 0, 
                          Q = Q.grid, S = 12, no.constant = TRUE, details = FALSE)
          
          # Captura do BIC do modelo ajustado
          bic_val <- unlist(draft[4])[3]
          BIC_matrix <- rbind(BIC_matrix, c(BIC = bic_val, p = p.grid, q = q.grid, P = P.grid, Q = Q.grid))
        }, error = function(e) {
          # Ignora combinações não convergentes ou explosivas
        })
      }
    }
  }
}

# Ordenação dos melhores modelos encontrados
BIC_matrix <- data.frame(BIC_matrix)
BIC_matrix <- BIC_matrix[order(BIC_matrix$BIC.ICs.BIC), ]
print("--- Top 5 Modelos Selecionados pelo Grid Search ---")
print(head(BIC_matrix, 5))

# ---- 6. Ajuste e Diagnóstico do Modelo Ótimo ----
# Captura os parâmetros da primeira linha (melhor BIC)
p_opt <- BIC_matrix[1, 2]
q_opt <- BIC_matrix[1, 3]
P_opt <- BIC_matrix[1, 4]
Q_opt <- BIC_matrix[1, 5]

print(paste("Ajustando Modelo Escolhido: SARIMA(", p_opt, ",1,", q_opt, ")x(", P_opt, ",0,", Q_opt, ")_12", sep=""))

# Salvando a tela de diagnóstico padrão do astsa
png("Plots/grafico11_diagnostico_residuos.png", width = 800, height = 600)
fit_model <- sarima(Yt_treinamento, p_opt, 1, q_opt, P = P_opt, D = 0, Q = Q_opt, S = 12, no.constant = TRUE)
dev.off()

# Teste Formal de Independência dos Resíduos (Ljung-Box acumulado)
LB_pvalues <- numeric(30)
for (lag in 1:30) {
  LB_pvalues[lag] <- Box.test(resid(fit_model$fit), lag = lag, type = 'Ljung-Box')$p.value
}
print("--- P-valores do Teste Ljung-Box (Lags 1 a 10) ---")
print(head(LB_pvalues, 10))

# Teste Formal de Normalidade (Shapiro-Wilk)
residuos_treino <- as.numeric(residuals(fit_model$fit))
print("--- Teste de Normalidade dos Resíduos (Shapiro-Wilk) ---")
print(shapiro.test(residuos_treino))

# ---- 7. Validação em Amostra de Teste (Cálculo do MAPE) ----
# Ajuste do modelo na base histórica completa para extrair os resíduos longitudinais
fit_completo <- sarima(condados$Yt, p_opt, 1, q_opt, P = P_opt, D = 0, Q = Q_opt, S = 12, no.constant = TRUE, details = FALSE)
residuos_completos <- as.numeric(residuals(fit_completo$fit))

# Valores preditos um passo à frente
condados$Yhat <- condados$Yt - residuos_completos
condados$Yhat[1:n_treinamento] <- NA  # Isolar apenas a fase de validação (dados não vistos)

# Plot de Validação: Real vs. Previsto um passo à frente
png("Plots/grafico12_predicao_validacao.png", width = 800, height = 500)
plot(condados$t, condados$Yt, type = "l", col = "black", lwd = 1.5,
     xlab = "Mês/Ano", ylab = "Consumo Médio", main = "Validação Cruzada: Modelo SARIMA vs. Realidade")
lines(condados$t, condados$Yhat, col = "red", lwd = 1.2)
legend("topleft", legend = c("Consumo Real", "Previsão (Amostra Teste)"), col = c("black", "red"), lty = 1, lwd = 2)
dev.off()

# Métrica de Erro de Negócio (MAPE)
mape_val <- mean(abs((na.omit(condados$Yhat) - na.omit(condados$Yt)) / na.omit(condados$Yt)), na.rm = TRUE) * 100
print(paste("Métrica de Performance Preditiva -> MAPE final:", round(mape_val, 2), "%"))

# ---- 8. Projeções Futuras (Forecasting Horizonte H=12) ----
png("Plots/grafico13_forecast.png", width = 800, height = 500)
previsao_futura <- sarima.for(as.ts(condados$Yt), n.ahead = 12, 
                              p_opt, 1, q_opt, P = P_opt, D = 0, Q = Q_opt, S = 12, 
                              no.constant = TRUE, plot.all = TRUE)
title(main = "Projeção de Consumo de Energia - Horizonte 12 Meses")
dev.off()

print("Pipeline de Séries Temporais executado com sucesso. Gráficos exportados para a pasta /Plots.")