# Cap the ONNX Runtime thread pool when several processes each load a model

**Date**: 2026-11-26 · **Confidence**: High · **Scope**: any onnxruntime-node CPU session spawned per session

`onnxruntime-node` sizes its intra-op thread pool to every core by default. Measured on a 24-core box with Laya 421M fp32: default threads took 3.0 s and 66 CPU-seconds per call; `sessionOptions: { intraOpNumThreads: 6 }` took 2.8 s and 17 CPU-seconds, the same latency for a quarter of the CPU. laya-guard runs one sidecar per OpenCode session (five were resident), and the default pushed the load average to 47. Use `Math.min(6, availableParallelism())` (`plugins/laya-guard/sidecar.mjs`).
