MAC_SRC ?= 00:00:00:00:00:00
MAC_DST ?= 00:00:00:00:00:00
NUMA_ID ?= 0
PCI_DEV_ID ?= 0000:00:00.0
DPDK_DRIVER ?= vfio-pci

SKIP_GLOBAL_DEPS ?=
SKIP_INSTALL_DPDK ?=
SKIP_INSTALL_DPDK_BURST_REPLAY ?=

SHELL := /bin/bash
GLOBAL_DEPS = build-essential libnuma-dev tshark meson ninja-build tcpreplay autoconf

msg = @echo -e "\e[1;34m$(1)\e[0m";

ifeq ($(V),1)
	Q =
else
	Q = @
	MAKEFLAGS += --no-print-directory
endif

.PHONY: default
default: help
	$(Q)exit 1

.PHONY: help
help:
	$(Q)echo -e "usage: make install|run"

.PHONY: install
install: install-global-deps install-dpdk install-dpdk-burst-replay

.PHONY: install-global-deps
ifeq ($(SKIP_INSTALL_GLOBAL_DEPS),)
install-global-deps:
	$(call msg,Installing global dependencies)
	$(Q)sudo apt-get update
	$(Q)sudo DEBIAN_FRONTEND=noninteractive apt-get install -yq $(GLOBAL_DEPS)
else
install-global-deps:
	$(call msg,Skipped installation of global dependencies)
endif

.PHONY: install-dpdk
ifeq ($(SKIP_INSTALL_DPDK),)
install-dpdk: install-global-deps
	$(call msg,Building and installing DPDK)
	$(Q)cd deps/dpdk-stable && meson build
	$(Q)ninja -C deps/dpdk-stable/build
	$(Q)sudo ninja -C deps/dpdk-stable/build install
	$(Q)sudo ldconfig
	$(call msg,Configuring DPDK)
	$(Q)sudo dpdk-devbind.py --bind="$(DPDK_DRIVER)" "$(PCI_DEV_ID)"
	$(Q)sudo dpdk-hugepages.py --setup 1G
else
install-dpdk:
	$(call msg,Skipped installation and configuration of DPDK)
endif

.PHONY: install-dpdk-burst-replay
ifeq ($(SKIP_INSTALL_DPDK_BURST_REPLAY),)
install-dpdk-burst-replay: install-global-deps
	$(call msg,Building and installing dpdk-burst-replay)
	$(Q)cd deps/dpdk-burst-replay && git reset --hard
	$(Q)cd deps/dpdk-burst-replay && git apply ../ebpf-sketches/pkt-generator/dpdk-burst-replay.patch
	$(Q)cd deps/dpdk-burst-replay && autoreconf -i
	$(Q)cd deps/dpdk-burst-replay && ./configure
	$(Q)make -C deps/dpdk-burst-replay
	$(Q)sudo make -C deps/dpdk-burst-replay install || true  # This failure does not matter
else
install-dpdk-burst-replay:
	$(call msg,Skipped installation of dpdk-burst-replay)
endif

.PHONY: run
run: output_complete.pcap
	$(call msg,Starting replay)
	$(Q)sudo dpdk-replay --nbruns 100000000000 --numacore "$(NUMA_ID)" output_complete.pcap "$(PCI_DEV_ID)"

output_complete.pcap: output.pcap
	$(call msg,Downloading dependencies for classbench-generators)
	$(Q)if [[ ! -d .venv ]]; then python3 -m venv --system-site-packages .venv; fi
	$(Q)source .venv/bin/activate && pip install -r deps/classbench-generators/requirements.txt
	$(Q)source .venv/bin/activate && pip install numpy
	$(Q)cd /usr/lib/x86_64-linux-gnu && (if [[ ! -f liblibc.a ]]; then sudo ln -s libc.a liblibc.a; fi)  # https://stackoverflow.com/a/65513989/10108192
	$(call msg,Converting from output.pcap to output_complete.pcap)
	$(Q)source .venv/bin/activate && python3 deps/classbench-generators/pcap/convert-trace-with-right-size-single-core.py -i output.pcap -o output_complete.pcap -s "$(MAC_SRC)" -d "$(MAC_DST)" -p

output.pcap: deps/univ1_trace/univ1_pt1
	$(call msg,Adding Ethernet layer to traces)
	$(Q)tcprewrite --dlt=enet --enet-dmac="$(MAC_DST)" --enet-smac="$(MAC_SRC)" --infile=deps/univ1_trace/univ1_pt1 --outfile=output.pcap

deps/univ1_trace/univ1_pt1: deps/univ1_trace.tgz
	$(call msg,Extracting traces)
	$(Q)rm -rf deps/univ1_trace
	$(Q)mkdir deps/univ1_trace && cd deps/univ1_trace && tar xzf ../univ1_trace.tgz

deps/univ1_trace.tgz:
	$(call msg,Downloading traces)
	$(Q)wget -O deps/univ1_trace.tgz http://pages.cs.wisc.edu/~tbenson/IMC_DATA/univ1_trace.tgz