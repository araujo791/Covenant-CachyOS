# Covenant-CachyOS

Kernel e otimizações de sistema para **desktop gaming/performance rodando em hardware de servidor dual-socket**, baseado no CachyOS.

O foco é reduzir tráfego cross-socket (NUMA), fixar recursos em performance e derivar um kernel do `linux-cachyos` compilado para esta máquina — sem editar `.config` à mão, usando as variáveis do PKGBUILD oficial.

## Hardware alvo

| Componente | Especificação |
|---|---|
| CPU | 2x Intel Xeon E5-2680 v4 — Broadwell-EP (28c/56t total) |
| Placa-mãe | MACHINIST E5-D8-MAX |
| RAM | 64GB DDR4 (2x 32GB) |
| GPU | AMD Radeon RX 560 (Polaris) |
| Storage | NVMe 953GB + NVMe 465GB + 4x HDD (12TB total) |
| NUMA | node 0: CPUs 0-13,28-41 · node 1: CPUs 14-27,42-55 |
| OS | CachyOS (Arch-based) |
| Kernel base | linux-cachyos 7.1.x (BORE + EEVDF + sched_ext) |

> **Nota de memória:** com 2 DIMMs em 2 sockets, cada CPU roda **1 canal** de um controlador **quad-channel**. Popular 4 (ou 8) DIMMs por socket é, de longe, o maior ganho de banda de memória disponível nesta máquina — mais do que qualquer ajuste de kernel.

---

## Scripts

| Script | O que faz |
|---|---|
| `covenant-setup.sh` | Aplica as otimizações de sistema (GRUB, sysctl, governor, zram, I/O, GPU, serviços). |
| `covenant-build.sh` | Compila o kernel custom `linux-covenant` (Clang+ThinLTO) via env vars do PKGBUILD. |
| `covenant-backup.sh` | Detecta o kernel em uso e salva vmlinuz/initramfs/pacotes/configs + snapshot. |

### Uso

```bash
# 1. Otimizacoes de sistema (base — boota mesmo sem o kernel custom)
sudo bash covenant-setup.sh

# 2. (Opcional) Kernel custom para esta maquina — ~10min em rebuild
bash covenant-build.sh

# 3. Apos reiniciar no kernel novo, faca o backup
sudo bash covenant-backup.sh
```

Reinstalar o kernel custom sem recompilar:

```bash
sudo pacman -U ~/Kernal/backup/compiled/linux-covenant-*.pkg.tar.zst
```

### Steam launch options

```
numactl --cpunodebind=0 --membind=0 gamemoderun %command%
```

Fixa CPU e RAM no node 0, onde estao os dois NVMe — minimiza acesso cross-socket.

---

## Otimizacoes

### Kernel custom (`covenant-build.sh`)

Nada e editado no `.config` manualmente. Tudo vem das variaveis que o PKGBUILD do CachyOS ja expoe, o que mantem a arvore consistente com o upstream e preserva os `select`/dependencias do Kconfig:

- **`-march=native`** — o build roda na propria Covenant, entao `native` resolve para Broadwell-EP com o tuning exato da CPU (melhor que `MBROADWELL` fixo).
- **Clang + ThinLTO** (`_use_llvm_lto=thin`) — ganho tipicamente de poucos pontos percentuais em cargas reais.
- **BORE + EEVDF + sched_ext** (`_cpusched=cachyos`) — mantem `SCHED_CLASS_EXT` **e o BTF** ligados. Isso e o que permite o `scx_rusty` anexar; desabilitar `DEBUG_INFO_BTF` derruba o sched_ext silenciosamente.
- **`HZ=1000`, `PREEMPT=full`, `nohz_full`** (`_tickrate=full`) — baixa latencia.
- **THP `always`** (`_hugepage=always`).
- **Governor default = performance** (`_per_gov=yes`).
- **BBRv3** (`_tcp_bbr3=yes`) — fornece o modulo `bbr` usado no sysctl.
- **`_build_debug=no`** — sem info de debug pesada (o CACHY config ja desliga KFENCE/etc., mas preserva o BTF necessario ao scx).
- **`_localmodcfg`** (opt-in) — compila so os modulos que a maquina carrega. Rode `LOCALMODCFG=yes bash covenant-build.sh` depois de popular o `modprobed-db`.

> **BORE x scx_rusty:** quando o `scx_rusty` esta ativo, ele **assume** o escalonamento das tarefas normais; o BORE+EEVDF e o *fallback* quando o sched_ext esta desligado. Os dois nao atuam ao mesmo tempo.

### NUMA (dual socket) — via cmdline

- `numa_balancing=1` — balanceamento automatico entre os sockets.
- `nohz_full=1-13,28-41` + `rcu_nocbs=1-13,28-41` — cores do node 0 livres de tick/RCU callbacks.
- `irqaffinity=0,14` — um core por socket dedicado a IRQs.
- `scx_rusty` via `scx_loader` — escalonador userspace NUMA-aware.

> `nohz_full` rende mais em cargas *isoladas* (uma thread por core). Para jogos, vale **medir frametimes com e sem** — em cargas muito interativas o overhead de entrar/sair do modo tickless pode anular o beneficio.

### Memoria

- **Zram** — swap comprimido em RAM (zstd, ~metade da RAM).
- `vm.swappiness = 100` + `vm.page-cluster = 0` — **correto para zram**: comprimir paginas frias e mais barato que descartar page cache; swappiness baixa so faz sentido para swap em disco.
- THP `always` cobre hugepages para jogos/Proton — sem reservar `nr_hugepages` explicitas (que sequestrariam RAM sem uso).

### CPU / Energia

- Governor **performance** (kernel default + `tmpfiles.d` + runtime). Sem `power-profiles-daemon` (redundante em desktop e conflita com governor fixo).
- `irqbalance` desativado.

### GPU (RX 560)

- `power_dpm_force_performance_level = high`, persistido via udev **escopado ao driver `amdgpu`** (nao casa a funcao de audio HDMI).

### I/O Scheduler

- NVMe -> `none` · HDD rotativo -> `bfq` · SSD SATA -> `none`. Persistido via udev.

### Rede

- `tcp_congestion_control = bbr` (BBRv3) · `default_qdisc = fq` · `tcp_fastopen = 3` · `tcp_mtu_probing = 1`.

### Sistema / Boot

- Servicos desnecessarios desativados: `bluetooth`, `avahi-daemon`, `ModemManager`.
- `mitigations=off` + `nowatchdog` *(maquina pessoal/local)*.
- Nome nos menus do GRUB via **`GRUB_DISTRIBUTOR="Covenant-CachyOS"`** — sobrevive a `grub-mkconfig` e a updates de kernel, dispensando `sed` em `grub.cfg` e hook do pacman.

---

## Verificacao rapida (pos-reboot)

```bash
uname -r                              # -> <versao>-covenant
cat /sys/kernel/sched_ext/state       # -> enabled (scx_rusty ativo)
systemctl is-active scx_loader
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor   # -> performance
zramctl
sysctl net.ipv4.tcp_congestion_control                      # -> bbr
```

---

## Observacoes

- `mitigations=off` e aceitavel **apenas** em maquina pessoal/local.
- O node NUMA 0 concentra CPU, RAM e os NVMe — minimo de trafego cross-socket.
- Rollback do GRUB: o setup preserva `/etc/default/grub.covenant-orig` na primeira execucao.
