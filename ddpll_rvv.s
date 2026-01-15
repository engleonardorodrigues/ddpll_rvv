/*
 ============================================================================
 MAPA DE REGISTRADORES (RISC-V Vector + ABI)
 ============================================================================
 Escalares:
   a0, a1, a2   : Args da função (Ponteiros Ei_real, Ei_imag, nSymbols)
   a3           : nModes (Tamanho do vetor)
   a4           : Ponteiro Theta (Array de saída)
   a5           : Registrador temporário (Substituto seguro do 'tp')
   fa0          : Kv (Ganho Proporcional)
   s0           : Frame Pointer (Base da Stack)
   s1, s2       : Ponteiros symbTx_real, symbTx_imag (Símbolos Piloto)
   s3           : Ponteiro pilot_mask (Máscara de Pilotos)
   s4           : Stride (Tamanho de um vetor em bytes: nModes * 4)
   s5, s6, s7   : Ponteiros para o buffer do Filtro de Loop (u[0], u[1], u[2])
   t0 - t6      : Temporários para cálculo de endereços e controle de loop
 
 Vetoriais (V0-V31):
   v1, v2       : Entrada Real (Ei_r) e Imaginária (Ei_i)
   v3           : Fase Estimada Atual (Theta)
   v10, v11     : Cosseno e Seno (Aproximação de Taylor)
   v12, v13     : Sinal Rotacionado (Re', Im')
   v14, v15     : Símbolo Decidido (Slicer QPSK ou Piloto)
   v8           : Erro de Fase (Detector)
   v9           : Saída do Filtro
 ============================================================================
*/

.globl ddpll_rvv
.type ddpll_rvv, @function

# === SEÇÃO DE CONSTANTES (Read-Only Data) ===
.section .rodata
.align 3                        # Alinha memória em 8 bytes (2^3)
const_qpsk_pos: .float 0.70710678 # +1/sqrt(2)
const_qpsk_neg: .float -0.70710678 # -1/sqrt(2)
const_zero:     .float 0.0
const_one:      .float 1.0
const_two:      .float 2.0

.text
# Assinatura: void ddpll_rvv(Ei_r, Ei_i, nSym, nMod, theta, ..., Kv...)
# Kv (Ganho) chega no registrador de ponto flutuante fa0

ddpll_rvv:
    # ---------------------------------------------------------
    # 1. SETUP DO STACK FRAME (Prólogo)
    # ---------------------------------------------------------
    addi sp, sp, -128           # Abre espaço de 128 bytes na pilha
    
    # Salva registradores que a função vai usar e precisa restaurar depois (Callee-saved)
    sd ra, 120(sp)              # Return Address (endereço de retorno)
    sd s0, 112(sp)              # Frame Pointer anterior
    sd s1, 104(sp)              # Saved Register 1
    sd s2, 96(sp)               # ...
    sd s3, 88(sp)
    sd s4, 80(sp)
    sd s5, 72(sp)
    sd s6, 64(sp)
    sd s7, 56(sp)

    # ---------------------------------------------------------
    # 2. FRAME POINTER SETUP
    # ---------------------------------------------------------
    addi s0, sp, 128            # s0 aponta para o topo original da pilha. 
                                # Útil para acessar argumentos passados via stack.

    # ---------------------------------------------------------
    # 3. CARREGAR ARGUMENTOS DA STACK
    # ---------------------------------------------------------
    # No RISC-V, apenas os primeiros 8 argumentos inteiros vão em a0-a7. 
    # O restante (symbTx, pilot_mask) está na memória, acima do s0.
    ld s1, 0(s0)                # Carrega ponteiro symbTx_real
    ld s2, 8(s0)                # Carrega ponteiro symbTx_imag
    ld s3, 16(s0)               # Carrega ponteiro pilot_mask

    # ---------------------------------------------------------
    # 4. CARREGAR CONSTANTES PARA REGISTRADORES
    # ---------------------------------------------------------
    fmv.s ft0, fa0              # Move o ganho Kv (fa0) para ft0 para uso posterior
    
    # Carrega as constantes QPSK e auxiliares em registradores float temporários (ft*)
    la t0, const_qpsk_pos       # Endereço de 0.707...
    flw ft6, 0(t0)              # Carrega valor em ft6
    la t0, const_qpsk_neg       # Endereço de -0.707...
    flw ft7, 0(t0)              # Carrega valor em ft7
    la t0, const_zero
    flw ft5, 0(t0)              # 0.0 em ft5
    la t0, const_one
    flw ft8, 0(t0)              # 1.0 em ft8
    la t0, const_two
    flw ft9, 0(t0)              # 2.0 em ft9

    # ---------------------------------------------------------
    # 5. ALOCAÇÃO DINÂMICA DO BUFFER DO FILTRO (Array 'u')
    # ---------------------------------------------------------
    # Precisamos de 3 buffers (u[0], u[1], u[2]) do tamanho de nModes.
    sext.w a3, a3               # Garante que nModes (a3) seja tratado como 64-bits com sinal
    slli s4, a3, 2              # s4 = nModes * 4 bytes (Stride/Tamanho de um vetor)
    li t1, 3                    # Precisamos de 3 vetores de histórico
    mul t0, s4, t1              # t0 = Tamanho total em bytes (3 * Stride)
    addi t0, t0, 15             # Adiciona margem para alinhamento
    andi t0, t0, -16            # Arredonda para baixo para múltiplo de 16 (Alinhamento)
    
    sub sp, sp, t0              # Aloca memória na pilha movendo o SP para baixo
    mv s5, sp                   # s5 aponta para o início do buffer u[0]

    # ---------------------------------------------------------
    # 6. INICIALIZAÇÃO DO BUFFER (ZERAR MEMÓRIA)
    # ---------------------------------------------------------
    mv t2, t0                   # t2 = contador de bytes total
    mv t6, s5                   # t6 = ponteiro temporário para percorrer o buffer

init_loop:
    # Configura vetor para processar o máximo de bytes possível (e8 = byte, m8 = 8 registradores)
    vsetvli t4, t2, e8, m8, ta, ma 
    vmv.v.i v0, 0               # Preenche vetor v0 com zeros
    vse8.v v0, (t6)             # Salva zeros na memória
    sub t2, t2, t4              # Decrementa bytes restantes
    add t6, t6, t4              # Avança ponteiro
    bnez t2, init_loop          # Se não acabou, repete

    # Define endereços dos buffers u[1] e u[2] baseados no stride (s4)
    add s6, s5, s4              # s6 = endereço de u[1]
    add s7, s6, s4              # s7 = endereço de u[2]

    # ---------------------------------------------------------
    # === LOOP PRINCIPAL DO PLL (Símbolo por Símbolo) ===
    # ---------------------------------------------------------
    li t0, 0                    # t0 é o contador 'k' (índice do símbolo)
    
main_loop:
    # Verificação de Limite: k < nSymbols - 1
    # Processamos até n-1 porque calculamos Theta[k+1]
    addi t1, a2, -1
    bge t0, t1, cleanup_and_exit # Se k >= nSymbols-1, termina

    # Cálculo dos Offsets de Memória para o índice k
    mul t1, t0, a3              # t1 = k * nModes (índice linear float)
    slli t1, t1, 2              # t1 = Offset em bytes (float * 4)
    
    # Ponteiros Absolutos para os dados do símbolo atual
    add t2, a0, t1              # t2 = &Ei_real[k]
    add t3, a1, t1              # t3 = &Ei_imag[k]
    add t4, a4, t1              # t4 = &Theta[k]
    add t5, s1, t1              # t5 = &Tx_real[k] (Piloto)
    add t6, s2, t1              # t6 = &Tx_imag[k] (Piloto)

    # ---------------------------------------------------------
    # A. Shift Register do Filtro: u[1] = u[2] (Delay)
    # ---------------------------------------------------------
    # Configura vetor para tamanho nModes (a3), elementos float (e32), agrupamento m1
    vsetvli a5, a3, e32, m1, ta, ma
    vle32.v v2, (s7)            # Carrega u[2]
    vse32.v v2, (s6)            # Salva em u[1]
    
    # ---------------------------------------------------------
    # B. Carregar Dados de Entrada e Theta Atual
    # ---------------------------------------------------------
    vle32.v v1, (t2)            # v1 = Ei_real (Entrada)
    vle32.v v2, (t3)            # v2 = Ei_imag (Entrada)
    vle32.v v3, (t4)            # v3 = Theta[k] (Fase estimada)

    # ---------------------------------------------------------
    # C. Trigonometria (Série de Taylor para Pequenos Ângulos)
    # ---------------------------------------------------------
    # cos(x) ~= 1 - x^2/2
    # sin(x) ~= x
    
    vfmul.vv v10, v3, v3        # v10 = theta^2
    vfdiv.vf v10, v10, ft9      # v10 = theta^2 / 2
    vfrsub.vf v10, v10, ft8     # v10 = 1.0 - (theta^2 / 2)  --> COSSENO
    vmv.v.v v11, v3             # v11 = theta                --> SENO

    # ---------------------------------------------------------
    # D. Rotação (Correção de Fase)
    # ---------------------------------------------------------
    # Z_rot = Z_in * exp(-j*theta)
    # Re' = Re*Cos + Im*Sin
    # Im' = Im*Cos - Re*Sin
    
    vfmul.vv v12, v1, v10       # v12 = Re * Cos
    vfmacc.vv v12, v2, v11      # v12 += Im * Sin  (Resultado: Re')
    
    vfmul.vv v13, v2, v10       # v13 = Im * Cos
    vfnmsac.vv v13, v1, v11     # v13 -= Re * Sin  (Resultado: Im') (Instrução Negate-Multiply-Subtract)

    # ---------------------------------------------------------
    # E. Decisão (Slicer ou Piloto)
    # ---------------------------------------------------------
    # Verifica se o símbolo atual k é um Piloto
    slli a5, t0, 2              # Offset do vetor de máscara (k * 4 bytes)
    add a5, s3, a5              # Endereço de pilot_mask[k]
    flw ft1, 0(a5)              # Carrega máscara
    fcvt.w.s a5, ft1            # Converte float para int
    bnez a5, mode_pilot         # Se máscara != 0, pula para carregar Piloto conhecido

mode_decision:
    # Lógica do Slicer QPSK (Decide baseado no quadrante)
    # Se Re' > 0, decide +0.707, senão -0.707
    vmv.v.i v0, 0               # Limpa máscara vetorial v0
    vmfgt.vf v0, v12, ft5       # Compara Re' (v12) > 0.0 (ft5). Resultado em v0.
    vfmv.v.f v14, ft7           # Inicializa v14 com -0.707
    vfmerge.vfm v14, v14, ft6, v0 # Se v0 for true, põe +0.707. (v14 = DecRe)
    
    # Se Im' > 0, decide +0.707, senão -0.707
    vmfgt.vf v0, v13, ft5       # Compara Im' (v13) > 0.0
    vfmv.v.f v15, ft7           # Inicializa v15 com -0.707
    vfmerge.vfm v15, v15, ft6, v0 # Se v0 for true, põe +0.707. (v15 = DecIm)
    j calc_error                # Pula a parte do piloto

mode_pilot:
    # Carrega os símbolos piloto conhecidos diretamente da memória
    vle32.v v14, (t5)           # v14 = Tx_real (Piloto)
    vle32.v v15, (t6)           # v15 = Tx_imag (Piloto)

calc_error:
    # ---------------------------------------------------------
    # F. Detector de Erro de Fase (Produto Cruzado)
    # ---------------------------------------------------------
    # Erro ~= Im' * DecRe - Re' * DecIm  (Aproximação de sen(phi_err))
    vfmul.vv v8, v13, v14       # v8 = Im' * DecRe
    vfnmsac.vv v8, v12, v15     # v8 -= Re' * DecIm
    
    vse32.v v8, (s7)            # Salva o erro calculado em u[2] (Histórico mais recente)

    # ---------------------------------------------------------
    # G. Filtro de Loop (PI Controller Simplificado)
    # ---------------------------------------------------------
    # Filtro: Out = u[1] + (u[2] / 2)
    # u[1] é o erro anterior (integrador), u[2] é o erro atual
    vfdiv.vf v9, v8, ft9        # v9 = u[2] / 2.0
    vle32.v v20, (s6)           # Carrega u[1]
    vfadd.vv v9, v20, v9        # v9 = u[1] + u[2]/2
    
    vse32.v v9, (s5)            # Salva resultado em u[0] (embora não usado diretamente no next step, bom pra debug)

    # ---------------------------------------------------------
    # H. Atualização do NCO (Oscilador Controlado Numericamente)
    # ---------------------------------------------------------
    # Theta_next = Theta_atual + (Filtro_Out * Kv)
    vfmul.vf v20, v9, ft0       # v20 = Filtro_Out * Kv
    vfadd.vv v21, v3, v20       # v21 = Theta_atual + Correção (FEEDBACK NEGATIVO)
    
    # ---------------------------------------------------------
    # I. Store Theta[k+1]
    # ---------------------------------------------------------
    add a5, t4, s4              # Calcula endereço Theta[k] + Stride = Theta[k+1]
                                # s4 contém o tamanho de um vetor inteiro (offset para o próximo k)
    vse32.v v21, (a5)           # Salva Theta[k+1] na memória

    # Incrementa k e repete
    addi t0, t0, 1
    j main_loop

cleanup_and_exit:
    # ---------------------------------------------------------
    # EPÍLOGO DA FUNÇÃO
    # ---------------------------------------------------------
    mv sp, s0                   # Restaura SP para o ponto logo abaixo dos registros salvos
                                # (Descarta o buffer dinâmico 'u')
    addi sp, sp, -128           # Volta para a base do frame salvo
    
    # Restaura todos os registradores salvos
    ld ra, 120(sp)
    ld s0, 112(sp)
    ld s1, 104(sp)
    ld s2, 96(sp)
    ld s3, 88(sp)
    ld s4, 80(sp)
    ld s5, 72(sp)
    ld s6, 64(sp)
    ld s7, 56(sp)
    
    addi sp, sp, 128            # Desaloca o frame da stack
    ret                         # Retorna para quem chamou (main em C)