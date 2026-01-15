DDPLL RISC-V Vector (RVV) Implementation
Este repositório contém uma implementação de alto desempenho de um Decision-Directed Phase-Locked Loop (DDPLL) para recuperação de fase em sistemas de comunicação (QPSK), escrita inteiramente em Assembly RISC-V utilizando a extensão vetorial RVV 1.0.

O projeto demonstra o uso de processamento paralelo (SIMD) para algoritmos de DSP, integrando código C (Testbench) com rotinas otimizadas em Assembly.

📋 Funcionalidades
Arquitetura: RISC-V 64-bit (RV64GCV).

Modulação: QPSK (Quadrature Phase Shift Keying).

Algoritmo: DDPLL (Decision-Directed PLL) com suporte a símbolos piloto.

Otimizações:

Uso intensivo de instruções vetoriais (vle32, vfmul, vfadd, etc.).

Aproximação de funções trigonométricas (Seno/Cosseno) via Série de Taylor para evitar chamadas de biblioteca lenta.

Alocação dinâmica de memória na Stack para o filtro de loop.

Conformidade estrita com a ABI do RISC-V (preservação de registradores callee-saved).

📂 Estrutura do Projeto
ddpll_rvv.s: O core do algoritmo em Assembly RISC-V. Contém a lógica de rotação, decisão, cálculo de erro e filtro de loop.

main.c: O testbench em C. Gera sinais de teste com erro de fase sintético, chama a função assembly e valida os resultados.

🛠️ Pré-requisitos
Para compilar e executar este projeto, você precisará de:

Toolchain GCC RISC-V com suporte a vetores (ex: riscv64-unknown-elf-gcc).

Emulador QEMU (User Mode) para executar binários RISC-V em x86/x64 (ex: qemu-riscv64).

🚀 Compilação e Execução
Utilize os comandos abaixo para compilar o código. Certifique-se de habilitar a extensão vetorial (v) na flag de arquitetura.