<p align="center">
  <img src="assets/covenant-logo.png" alt="Covenant Logo" width="500">
</p>
<p align="center">
  <strong>CachyOS Performance Toolkit</strong><br>
  <em>Otimização de sistema para máxima performance em Linux</em>
</p>
<p align="center">
  <a href="#"><img src="https://img.shields.io/badge/CachyOS-Compatible-06b6d4?style=flat-square&logo=archlinux&logoColor=white" alt="CachyOS"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="MIT"></a>
  <a href="#kernel-custom-covenant-buildsh"><img src="https://img.shields.io/badge/Kernel-Covenant-7c3aed?style=flat-square" alt="Kernel"></a>
  <a href="#hardware-alvo"><img src="https://img.shields.io/badge/NUMA-Dual_Socket-d4a017?style=flat-square" alt="NUMA"></a>
</p>

---

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
| `covenant-install.sh` | Instala com 1 comando os pacotes `.pkg.tar.zst` compilados e o tema do GRUB. |
| `covenant-build.sh` | Compila o kernel custom `linux-covenant` (Clang+ThinLTO) via env vars do PKGBUILD. |
| `covenant-backup.sh` | Detecta o kernel em uso e salva vmlinuz/initramfs/pacotes/configs + snapshot. |

### Uso

```bash
# 1. Otimizações de sistema (base — boota mesmo sem o kernel custom)
sudo bash covenant-setup.sh

# 2. Instalar o kernel custom compilado (.pkg.tar.zst) + tema de boot
sudo bash covenant-install.sh

# 3. (Opcional) Recompilar o kernel no futuro
bash covenant-build.sh

# 4. Após reiniciar no kernel novo, faça o backup
sudo bash covenant-backup.sh
```

Reinstalar o kernel custom sem recompilar:

```bash
sudo pacman -U ~/Kernel/backup/compiled/linux-covenant-*.pkg.tar.zst
```

### Steam launch options

```
numactl --cpunodebind=0 --membind=0 gamemoderun %command%
```

Fixa CPU e RAM no node 0, onde estão os dois NVMe — minimiza acesso cross-socket.

---

## 🎨 Temas visuais

O Covenant inclui temas visuais para GRUB (seleção de boot) e Plymouth (splash de boot).

### Tema GRUB

<p align="center">
  <img src="themes/grub/covenant/background.png" alt="Covenant GRUB Theme" width="700">
</p>

Tema escuro premium com estética cyberpunk — gradiente navy/púrpura, linhas de circuito sutis, acentos cyan e menu estilizado.

```bash
# Instalar tema GRUB
sudo bash themes/grub/install-grub-theme.sh
```

**Requisitos:** `imagemagick` (para gerar assets do menu).

### Tema Plymouth (Boot Splash)

Splash de boot com logo Covenant, spinner animado em cyan e barra de progresso.

```bash
# Instalar tema Plymouth
sudo bash themes/plymouth/install-plymouth-theme.sh
```

> **Nota:** Requer `plymouth` e o hook `plymouth` no `mkinitcpio.conf`.

---

## Otimizações

### Kernel custom (`covenant-build.sh`)

Nada é editado no `.config` manualmente. Tudo vem das variáveis que o PKGBUILD do CachyOS já expõe, o que mantém a árvore consistente com o upstream e preserva os `select`/dependências do Kconfig:

- **`-march=native`** — o build roda na própria Covenant, então `native` resolve para Broadwell-EP com o tuning exato da CPU (melhor que `MBROADWELL` fixo).
- **Clang + ThinLTO** (`_use_llvm_lto=thin`) — ganho tipicamente de poucos pontos percentuais em cargas reais.
- **BORE + EEVDF + sched_ext** (`_cpusched=cachyos`) — mantém `SCHED_CLASS_EXT` **e o BTF** ligados. Isso é o que permite o `scx_rusty` anexar; desabilitar `DEBUG_INFO_BTF` derruba o sched_ext silenciosamente.
- **`HZ=1000`, `PREEMPT=full`, `nohz_full`** (`_tickrate=full`) — baixa latência.
- **THP `always`** (`_hugepage=always`).
- **Governor default = performance** (`_per_gov=yes`).
- **BBRv3** (`_tcp_bbr3=yes`) — fornece o módulo `bbr` usado no sysctl.
- **`_build_debug=no`** — sem info de debug pesada (o CACHY config já desliga KFENCE/etc., mas preserva o BTF necessário ao scx).
- **`_localmodcfg`** (opt-in) — compila só os módulos que a máquina carrega. Rode `LOCALMODCFG=yes bash covenant-build.sh` depois de popular o `modprobed-db`.

> **BORE x scx_rusty:** quando o `scx_rusty` está ativo, ele **assume** o escalonamento das tarefas normais; o BORE+EEVDF é o *fallback* quando o sched_ext está desligado. Os dois não atuam ao mesmo tempo.

### NUMA (dual socket) — via cmdline

- `numa_balancing=1` — balanceamento automático entre os sockets.
- `nohz_full=1-13,28-41` + `rcu_nocbs=1-13,28-41` — cores do node 0 livres de tick/RCU callbacks.
- `irqaffinity=0,14` — um core por socket dedicado a IRQs.
- `scx_rusty` via `scx_loader` — escalonador userspace NUMA-aware.

> `nohz_full` rende mais em cargas *isoladas* (uma thread por core). Para jogos, vale **medir frametimes com e sem** — em cargas muito interativas o overhead de entrar/sair do modo tickless pode anular o benefício.

### Memória

- **Zram** — swap comprimido em RAM (zstd, ~metade da RAM).
- `vm.swappiness = 100` + `vm.page-cluster = 0` — **correto para zram**: comprimir páginas frias é mais barato que descartar page cache; swappiness baixa só faz sentido para swap em disco.
- THP `always` cobre hugepages para jogos/Proton — sem reservar `nr_hugepages` explícitas (que sequestrariam RAM sem uso).

### CPU / Energia

- Governor **performance** (kernel default + `tmpfiles.d` + runtime). Sem `power-profiles-daemon` (redundante em desktop e conflita com governor fixo).
- `irqbalance` desativado.

### GPU (AMD)

- `power_dpm_force_performance_level = high`, persistido via udev **escopado ao driver `amdgpu`** (não casa a função de áudio HDMI).

### I/O Scheduler

- NVMe → `none` · HDD rotativo → `bfq` · SSD SATA → `none`. Persistido via udev.

### Rede

- `tcp_congestion_control = bbr` (BBRv3) · `default_qdisc = fq` · `tcp_fastopen = 3` · `tcp_mtu_probing = 1`.

### Sistema / Boot

- Serviços desnecessários desativados: `bluetooth`, `avahi-daemon`, `ModemManager`.
- `mitigations=off` + `nowatchdog` *(máquina pessoal/local)*.
- Nome nos menus do GRUB via **`GRUB_DISTRIBUTOR="Covenant-CachyOS"`** — sobrevive a `grub-mkconfig` e a updates de kernel, dispensando `sed` em `grub.cfg` e hook do pacman.

---

## Estrutura do repositório

```
Covenant-CachyOS/
├── assets/
│   └── covenant-logo.png          Logo oficial
├── themes/
│   ├── grub/
│   │   ├── covenant/              Arquivos do tema GRUB
│   │   │   ├── theme.txt          Layout e estilo do menu
│   │   │   ├── background.png     Background cyberpunk 1920x1080
│   │   │   ├── generate-assets.sh Gerador de select/scrollbar/progress
│   │   │   └── icons/             Ícones das entradas de boot
│   │   └── install-grub-theme.sh  Instalador automático
│   └── plymouth/
│       └── install-plymouth-theme.sh  Instalador do splash de boot
├── covenant-setup.sh              Otimizações de sistema (11 passos)
├── covenant-build.sh              Compilador do kernel custom
├── covenant-backup.sh             Backup pós-reboot
├── LICENSE                        MIT
└── README.md                      Esta documentação
```

---

## Verificação rápida (pós-reboot)

```bash
uname -r                              # -> <versão>-covenant
cat /sys/kernel/sched_ext/state       # -> enabled (scx_rusty ativo)
systemctl is-active scx_loader
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor   # -> performance
zramctl
sysctl net.ipv4.tcp_congestion_control                      # -> bbr
```

---

## Observações

- `mitigations=off` é aceitável **apenas** em máquina pessoal/local.
- O node NUMA 0 concentra CPU, RAM e os NVMe — mínimo de tráfego cross-socket.
- Rollback do GRUB: o setup preserva `/etc/default/grub.covenant-orig` na primeira execução.

---

<p align="center">
  <sub>Feito com ⚡ por <a href="https://github.com/araujo791">Anderson Araujo</a></sub>
</p>
