# ebpf-sketches-reproduction

## 复现 trace

在运行时，需要把下列命令中 `<>` 包裹的部分替换成实际信息。

```bash
# 安装依赖
sudo make install PCI_DEV_ID=<网卡 PCI 设备 ID，如 0000:00:19.0>
# 运行（开始复现）
sudo make run MAC_SRC=<源 MAC> MAC_DST=<目标 MAC> NUMA_ID=<numa id，如 0> PCI_DEV_ID=<网卡 PCI 设备 ID，如 0000:00:19.0>
```
