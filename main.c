#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <math.h>
#include <complex.h>

// Definição de PI caso não exista
#ifndef M_PI
#define M_PI 3.14159265358979323846
#endif

// --- DECLARAÇÃO DA FUNÇÃO ASSEMBLY ---
extern void ddpll_rvv(
    float *Ei_real,
    float *Ei_imag,
    int nSymbols,
    int nModes,
    float *theta,
    float *constSymb_real,  // Ignorado
    float *constSymb_imag,  // Ignorado
    int constSize,          // Ignorado
    float *symbTx_real,     // Stack
    float *symbTx_imag,     // Stack
    float *pilot_mask,      // Stack
    float Kv,               // fa0
    float tau1,             // fa1
    float tau2              // fa2
);

// --- ESTRUTURAS ---
typedef struct {
    float *real;
    float *imag;
    int nSamples;
    int nModes;
} ComplexSignal;

ComplexSignal* allocate_signal(int nSamples, int nModes) {
    ComplexSignal *sig = (ComplexSignal*)malloc(sizeof(ComplexSignal));
    sig->nSamples = nSamples;
    sig->nModes = nModes;
    sig->real = (float*)calloc(nSamples * nModes, sizeof(float));
    sig->imag = (float*)calloc(nSamples * nModes, sizeof(float));
    return sig;
}

// --- FUNÇÃO PRINCIPAL ---
int main() {
    printf("=== DDPLL RVV Test Bench ===\n");

    // Configuração
    int nSymbols = 1024;
    int nModes = 4;
    float Kv = 0.2f;  // Ganho do loop
    
    // 1. Gera Sinais (QPSK Aleatório)
    ComplexSignal *SymbTx = allocate_signal(nSymbols, nModes);
    ComplexSignal *Ei = allocate_signal(nSymbols, nModes);
    
    // Máscara de Pilotos (Piloto a cada 16 símbolos)
    float *pilot_mask = (float*)calloc(nSymbols, sizeof(float));
    
    srand(42);
    
    for (int k = 0; k < nSymbols; k++) {
        // Define se é piloto
        int is_pilot = (k % 16 == 0);
        pilot_mask[k] = is_pilot ? 1.0f : 0.0f;

        // Ruído de Fase Variante (Senoide lenta)
        // Isso é o que o DDPLL deve tentar rastrear/corrigir
        float true_phase_error = 0.5f * sinf(0.02f * k); 

        for (int m = 0; m < nModes; m++) {
            int idx = k * nModes + m;
            
            // Símbolo QPSK Ideal (+-0.707)
            float tx_re = (rand() % 2) ? 0.7071f : -0.7071f;
            float tx_im = (rand() % 2) ? 0.7071f : -0.7071f;
            
            SymbTx->real[idx] = tx_re;
            SymbTx->imag[idx] = tx_im;
            
            // Aplica rotação de fase ao sinal recebido (Ei)
            // Ei = Tx * exp(j * erro)
            float cos_err = cosf(true_phase_error);
            float sin_err = sinf(true_phase_error);
            
            Ei->real[idx] = tx_re * cos_err - tx_im * sin_err;
            Ei->imag[idx] = tx_re * sin_err + tx_im * cos_err;
        }
    }

    // 2. Prepara Saída
    float *theta = (float*)calloc(nSymbols * nModes, sizeof(float));
    
    // 3. Chama Assembly
    printf("[INFO] Executando DDPLL Assembly...\n");
    printf("       Kv=%.2f, nSym=%d, nMod=%d\n", Kv, nSymbols, nModes);
    
    // Passamos placeholders para args não usados no assembly atual
    ddpll_rvv(
        Ei->real, Ei->imag, nSymbols, nModes, theta,
        NULL, NULL, 0, // Constellation args ignorados
        SymbTx->real, SymbTx->imag, pilot_mask,
        Kv, 0.0f, 0.0f
    );

    // 4. Verifica Resultados
    printf("\n=== Resultados (Modo 0) ===\n");
    printf("   k | Fase Real | Fase Estimada (Theta) | Erro Residual\n");
    printf("-----+-----------+-----------------------+--------------\n");
    
    for (int k = 0; k <= 100; k++) { // Mostra primeiros 20
        float true_phase = 0.5f * sinf(0.02f * k);
        float est_phase = theta[k * nModes];
        printf("%4d | %9.4f | %21.4f | %9.4f\n", 
               k, true_phase, est_phase, true_phase - est_phase);
    }

    // Cleanup
    free(SymbTx->real); free(SymbTx->imag); free(SymbTx);
    free(Ei->real); free(Ei->imag); free(Ei);
    free(pilot_mask);
    free(theta);
    
    return 0;
}