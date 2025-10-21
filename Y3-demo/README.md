# Intelligent Power Grid Y3 Demo

### Objectives

The Year 3 Intelligent Power Grid Use Case Demonstration leverages the intent-based orchestration across the FLUIDOS computing continuum.
This demonstration focuses on the FLUIDOS Model-based and Intent-driven Meta-Orchestrator (MIMO) component, which enables dynamic and context-aware workload management based on high-level user intents.

The demonstration highlights how orchestration intents (e.g. latency constraints) can be automatically translated into concrete deployment actions, optimizing workload placement across distributed nodes. In the Intelligent Power Grid context, this capability ensures that Phasor Data Concentrator (PDC) workloads are deployed considering ICT network quality, achieving low latency in PMU data collection and resilient control-loop operations.

---

### Components

The testbed includes:

* Physical PMUs of the RSE DER-TF Facility connected via optical fibers to the RSE IoT & Big Data Laboratory.
* Three Linux-based servers hosted in RSE IoT & BigData Lab running as FLUIDOS nodes (each hosting k3s, Longhorn) and forming a FLUIDOS computing continuum (one consumer and two providers).
* Phasor Data Concentrator (PDC) applications (lower-level and higher-leve)
* Percona XtraDB Cluster application and Longhorn for distributed configuration storage
* FLUIDOS MIMO (Model-based and Intent-driven Meta-Orchestrator) and Prometheus and PushGateway Docker containers on the consumer FLUIDOS node
* Ping-Push PDC sidecar container

---

### Requirements

* python >= 3.11
* Docker

---

### Setup

On each machine run the scripts consumer.sh, provider.sh, and provider2.sh respectively.
The scripts will install K3s, Liqo, FLUIDOS, Multus, and Longhorn, and add Location, Latency and Carbon Emission data on the three FLUIDOS nodes flavors. The scripts also add some configuration changes to K3s to reach the internal GitLab registry. 

Install the Prometheus and Push Gateway Docker containers on the consumer node:

```
docker create network monitoring
docker run -d -p 9091:9091 --network monitoring --name pushgateway prom/pushgateway
docker run -it -v $PWD/config:/etc/prometheus -p 9090:9090 --network monitoring --rm prom/prometheus:main
```

Run FLUIDOS MIMO in the consumer node:
clone the repository available at: https://github.com/fluidos-project/fluidos-modelbased-metaorchestrator

The operator assumes the following to be available within the system:
* Kubernetes version >= 28.1.0
* REAR (node) functionality version >= 0.0.4
* Liqo version >= 0.10.2

Moreover, the interaction with the operator assumes:
* fluidos-kubectl-plugin version >= 0.0.3

To run the operator in development mode, the following is required:
* python >= 3.11

Manually modify the file fluidos_model_orchestrator/configuration.py and substitute the "arm64" architecture specification with "amd64". 
Run: 
```
kubectl apply -f fluidos-modelbased-metaorchestrator/deployment/fluidos-meta-orchestrator/crds/fluidos-deployment-crd.yaml -n fluidos
```
```
pip install -e .
```
Create mbmo-config-map.yaml
```
apiVersion: v1
kind: ConfigMap
metadata:
  name: fluidos-mbmo-configmap
data:
  ELECTRICITY_MAP_API_KEY: xxxxxxxxx
  MSPL_ENDPOINT: "http://fluidos-mspl.sl.cloud9.ibm.com:8002/meservice"
```
```
kubectl apply -f fluidos-modelbased-metaorchestrator/mbmo-config-map.yaml -n fluidos
```
In /fluidos-modelbased-metaorchestrator/utils/prometheus/config/prometheus.yml add address of the pushgateway.

```
global:
  scrape_interval:     15s # By default, scrape targets every 15 seconds.
  external_labels:
    monitor: 'external_label'

scrape_configs:
  - job_name: 'testing'
    scrape_interval: 2s
    static_configs:
      - targets: ['pushgateway:9091']
```
Then run the MIMO orchestrator:

```
sudo python3 -m kopf run --verbose -m fluidos_model_orchestrator -A
```

### Intent Definition and Sequence

1. The orchestration intent is defined in the lower-level PDC YAML file:

   ```yaml
   fluidos-intent-latency: 100
   ```

   This specifies that the workload must run only on provider nodes capable of meeting a 100 ms latency threshold.

2. When the lower-level PDC is launched, MIMO evaluates the available providers:

   * Provider 1 (rm.fluidos.eu):** latency 80 ms
   * Provider 2 (vr.fluidos.eu):** latency 90 ms
     Both satisfy the declared intent, and MIMO selects one provider for PDC deployment.

3. The sidecar container continuously measures round-trip time (RTT) using ICMP probes.

   * Latency samples are aggregated (last 10 measurements) to assess compliance with the declared intent.
   * If latency remains within threshold, no action is taken.

4. When artificial latency fluctuations are introduced, the sidecar detects the increase and updates MIMO.

   * The flavor definition of Provider 1 is updated with the new latency value.
   * Since it no longer meets the latency constraint, MIMO automatically reschedules the PDC workload to Provider 2.


This sequence demonstrates the self-adaptive and intent-driven orchestration capability of MIMO.

---

## License and Acknowledgments
This project is licensed under the Apache License - version 2.0, see the [LICENSE](LICENSE) file for details.

This project includes some previous work done by [Claudio Usai](https://github.com/claudious96), [Claudio Lorina](https://github.com/claudiolor) and [Riccardo Medina](https://github.com/rmedina97) as part of their master thesis at Politecnico di Torino.
