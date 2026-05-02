# Covenant-CachyOS

Kernel customizado e otimizado para desktop gaming/performance em hardware de servidor dual-socket, baseado no CachyOS.

## Hardware alvo

| Componente | Especificação |
|---|---|
| CPU | 2x Intel Xeon E5-2680 v4 (28c/56t total) |
| Placa-mãe | MACHINIST E5-D8-MAX |
| RAM | 64GB DDR4 (2x 32GB, dual channel por socket) |
| GPU | AMD Radeon RX 560 Series |
| Storage | NVMe 953GB + NVMe 465GB + 4x HDD (12TB total) |
| NUMA | 2 nodes — node 0: CPUs 0-13,28-41 / node 1: CPUs 14-27,42-55 |
| OS | CachyOS (Arch-based) |
| Kernel base | linux-cachyos 7.0.3 (BORE+EEVDF) |

---

## Otimizações aplicadas

### Kernel
- Compilado do zero com **Clang + ThinLTO** (~20% mais rápido que GCC em algumas cargas)
- `CONFIG_MBROADWELL` — instruções específicas para Broadwell-EP, sem código genérico
- **BORE + EEVDF scheduler** — melhor responsividade em desktop com muitos cores
- `HZ=1000` — timer de alta resolução para menor latência
- `PREEMPT=FULL` — preempção total, kernel mais responsivo
- **Debug desativado** — sem KFENCE, FTRACE, SLUB_DEBUG, KPROBES (reduz overhead)
- Watchdog desativado no kernel (`LOCKUP_DETECTOR`, `HARDLOCKUP_DETECTOR`)
- `CONFIG_RD_ZSTD` + `CONFIG_KERNEL_ZSTD` — compressão zstd (mais rápido que gzip)
- `CONFIG_LTO_CLANG_THIN` — link-time optimization
- `CONFIG_CC_OPTIMIZE_FOR_PERFORMANCE` — otimiza para velocidade, não tamanho
- `CONFIG_IRQ_FORCED_THREADING` — IRQ em threads dedicadas
- `CONFIG_RCU_NOCB_CPU` + `CONFIG_RCU_BOOST` — RCU otimizado para throughput
- `CONFIG_TCP_CONG_BBR` + `CONFIG_NET_SCH_FQ` — controle de rede BBR
- `CONFIG_FUTEX` + `CONFIG_FUTEX_PI` — suporte otimizado para Steam/Proton/Wine
- `CONFIG_ZSWAP` + `CONFIG_ZSMALLOC` — compressão de memória
- `CONFIG_DRM_AMDGPU` — suporte nativo RX 560
- `CONFIG_BLK_DEV_NVME` + `CONFIG_NVME_MULTIPATH` — NVMe otimizado

### NUMA (dual socket)
- `numa_balancing=1` — balanceamento automático entre os dois sockets
- `nohz_full=1-13,28-41` — cores do node 0 livres de interrupções de timer
- `rcu_nocbs=1-13,28-41` — RCU offloaded nos cores do node 0
- `irqaffinity=0,14` — um core por socket dedicado a IRQs
- **Steam launch options** com `numactl --cpunodebind=0 --membind=0` — força CPU, RAM e I/O no mesmo nó NUMA onde estão os NVMes

### SCX Scheduler
- `scx_rusty` via `scx_loader` — scheduler userspace **NUMA-aware**, distribui carga entre os dois sockets de forma inteligente

### CPU
- Governor **performance** em todos os 56 cores
- IRQ balance desativado (`irqbalance` desabilitado)
- Persistido via `tmpfiles.d` no boot

### Memória
- **Zram** — 32GB de swap comprimido em RAM com zstd (muito mais rápido que swap em disco)
- `vm.nr_hugepages = 1024` — hugepages para reduzir TLB miss
- `vm.swappiness = 10` — usa swap apenas quando necessário
- `vm.compaction_proactiveness = 20` — hugepages mais eficientes
- `CONFIG_TRANSPARENT_HUGEPAGE_ALWAYS` — hugepages transparentes sempre ativas

### GPU (AMD RX 560)
- `power_dpm_force_performance_level = high` — GPU fixada em performance máxima
- Persistido via udev rule no boot

### I/O Scheduler
- **NVMe** → `none` (gerenciamento interno da fila pelo próprio NVMe)
- **HDDs** → `bfq` (Budget Fair Queueing — melhor para discos rotativos)
- Persistido via udev rules

### Rede
- `net.ipv4.tcp_congestion_control = bbr` — BBR para melhor throughput
- `net.core.default_qdisc = fq` — Fair Queuing
- `net.ipv4.tcp_fastopen = 3` — conexões TCP mais rápidas
- `net.ipv4.tcp_mtu_probing = 1` — MTU dinâmico

### Processos
- **Ananicy-cpp** — prioridade automática de processos (jogos ganham CPU automaticamente)
- `kernel.sched_autogroup_enabled = 1` — agrupamento automático de tarefas

### Sistema
- Serviços desnecessários desativados: `bluetooth`, `avahi-daemon`, `ModemManager`
- `mitigations=off` — desativa proteções Spectre/Meltdown *(máquina pessoal/local)*
- `nowatchdog` — watchdog desativado via cmdline

### Boot
- Nome **Covenant-CachyOS** no GRUB
- Hook pacman para manter o nome após atualizações do kernel

---

## Scripts

| Script | Descrição |
|---|---|
| `covenant-cachyos.sh` | Instalação completa de todas as otimizações |
| `covenant-build.sh` | Compila o kernel do zero com Clang+ThinLTO |
| `covenant-backup.sh` | Backup completo pós-reboot (vmlinuz, initramfs, pkgs, configs) |

### Uso

```bash
# 1. Instala todas as otimizações
sudo bash covenant-cachyos.sh

# 2. Compila kernel customizado (opcional, ~10min com 56 threads)
bash covenant-build.sh

# 3. Após reiniciar, faz backup completo
sudo bash covenant-backup.sh
```

### Reinstalar kernel sem recompilar

```bash
sudo pacman -U ~/Kernal/backup/compiled/linux-covenant-*.pkg.tar.zst
```

### Steam launch options

```
numactl --cpunodebind=0 --membind=0 gamemoderun %command%
```

---

## Resultado

| Métrica | Antes | Depois |
|---|---|---|
| Kernel | linux-cachyos 7.0.2 (pré-compilado) | linux-covenant 7.0.3 (Clang+ThinLTO) |
| Scheduler | EEVDF | BORE+EEVDF + scx_rusty |
| Swap | disco | Zram 32GB zstd (RAM) |
| GPU | auto | performance fixo |
| I/O NVMe | mq-deadline | none |
| I/O HDD | mq-deadline | bfq |
| Tempo de build | — | ~10min (56 threads) |

---

## Observações

- `mitigations=off` é recomendado apenas para máquinas pessoais/locais
- O node NUMA 0 concentra CPU, RAM e storage (NVMe) — mínimo de tráfego cross-socket
- Testado no CachyOS com GNOME 50 + Wayland
