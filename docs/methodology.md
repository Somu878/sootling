# Methodology

Sootling estimates the carbon impact of local AI usage by adapting the public EcoLogits LLM inference methodology. EcoLogits itself is MPL-2.0 licensed, and its methodology pages are CC BY-SA 4.0. Sootling attributes the method to:

> Rincé, Samuel and Banse, Adrien. "EcoLogits: Evaluating the Environmental Impacts of Generative AI." Journal of Open Source Software, 2025.

References:

- EcoLogits docs: https://ecologits.ai/latest/methodology/llm_inference/
- EcoLogits repository: https://github.com/mlco2/ecologits
- PyPI release checked during scaffold: `ecologits 0.10.2`, released June 4, 2026

## Scope

M1 estimates text-to-text LLM inference from token counts in local CLI logs. It does not include:

- model training,
- networking,
- end-user device energy,
- voice or multimodal requests,
- exact provider datacenter location.

Browser chat support estimates token counts from visible message text in the browser extension using a simple `characters / 4` heuristic. The extension sends only token counts, source/model metadata, and timestamps to Sootling; prompt and response text are not sent to the app or stored in the database.

## Tokens to Energy

EcoLogits fits GPU energy per output token from ML.ENERGY H100 benchmark data:

```text
f_E(P_active, B) = alpha * exp(beta * B) * P_active + gamma
alpha = 1.17e-6
beta  = -1.12e-2
gamma = 4.05e-5
B     = 64
```

`P_active` is active parameter count in billions. Sootling applies this to output tokens and adds a small prefill term for input tokens. Cached input tokens are charged at a lower prefill factor because the logs distinguish them and cache reads should be cheaper than fresh prefill work.

## Server Energy

Sootling follows EcoLogits' H100 cloud-server assumptions:

- NVIDIA H100 80GB GPUs,
- 16-bit model weights,
- 1.2 memory overhead,
- 8 GPUs installed per server,
- 1.2 kW server draw excluding GPUs,
- batch size 64.

Required GPUs are estimated from model memory and rounded up to a power of two. The server component is allocated by the share of GPUs needed for the model and the batch size.

## Datacenter Overhead

Energy is multiplied by PUE. Registry entries include provider-style PUE ranges where known from EcoLogits docs:

- Anthropic: 1.09 to 1.14
- Google: 1.09
- OpenAI/Azure: 1.20
- fallback: 1.12 to 1.20

## Energy to CO2e

Usage emissions are:

```text
gCO2e = energy_kWh * grid_intensity_gCO2e_per_kWh
```

The default grid intensity is `480 gCO2e/kWh`, a world-average style default. Users can choose region presets or set a custom value.

## Embodied Hardware Share

Sootling includes an embodied-hardware allocation using EcoLogits' published constants:

- p5.48xlarge-like server without GPUs: 5700 kgCO2e,
- NVIDIA H100 80GB GPU: 273 kgCO2e,
- lifetime: 3 years,
- allocation by request latency and batch size.

## Ranges and Honesty

Every estimate is a range. Min/max come from:

- model active-parameter range,
- provider PUE range,
- embodied allocation over the resulting latency range.

Unknown model IDs are mapped to a conservative fallback entry. The UI labels these as estimates so users do not mistake them for exact measurements.
