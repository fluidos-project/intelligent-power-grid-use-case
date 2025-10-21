# Intelligent Power Grid Y3 Demo

## Objectives

The Year 3 Intelligent Power Grid Use Case Demonstration leverages the intent-based orchestration across the FLUIDOS computing continuum.
This demonstration focuses on the FLUIDOS Model-based and Intent-driven Meta-Orchestrator (MIMO) component, which enables dynamic workload management based on high-level user intents.

The demonstration highlights how orchestration intents (e.g. latency intents) can be automatically translated into concrete deployment actions, optimizing workload placement across distributed FLUIDOS nodes. In the Intelligent Power Grid context, this capability ensures that Phasor Data Concentrator (PDC) workloads are deployed considering ICT network quality, achieving low latency in PMU data collection and resilient control-loop operations.

The testbed includes:

* Physical PMUs from the RSE DER-TF Facility are connected via optical fibers to the RSE IoT & Big Data Laboratory.

* Three Linux-based servers hosted in the RSE IoT & Big Data Lab operate as FLUIDOS nodes, forming a computing continuum.

* A Percona XtraDB Cluster is used for distributed configuration storage.

* FLUIDOS MIMO (Model-based and Intent-driven Meta-Orchestrator), along with Prometheus and Pushgateway for monitoring and metrics collection.

* Phasor Data Concentrator (PDC) applications and a Ping Sidecar service.



## Setup

### Requirements

* Python >= 3.11
* Docker >= 20

### FLUIDOS Node

On each server run the setup scripts [consumer.sh](./setup/consumer.sh), [provider.sh](./setup/provider.sh), and [provider.sh](./setup/provider2.sh) respectively to install one FLUIDOS consumer and two FLUIDOS providers.
The scripts will install K3s, Liqo, FLUIDOS, Multus, and Longhorn, and add Location, Latency and Carbon Emission data on the three FLUIDOS nodes flavors. The scripts also add some configuration changes to K3s to reach the internal GitLab registry. 

Manually generate peerings using the command:

```
liqo generate peer-command
```

### Percona Operator for MySQL
In order to guarantee cross-cluster volumes replication and data persisentcy, we follow [this guide](https://docs.percona.com/legacy-documentation/percona-operator-for-mysql-pxc/percona-kubernetes-operator-for-pxc-1.11.0.pdf) to install the Percona Operator for MySQL based on Percona XtraDB Cluster. First, clone the repository
```
git clone -b v1.11.0 https://github.com/percona/percona-xtradb-cluster-operator
cd percona-xtradb-cluster-operator/
```
Install the operator
```
kubectl apply -f deploy/crd.yaml
kubectl create namespace lower
kubectl apply -f deploy/rbac.yaml -n lower
kubectl apply -f deploy/operator.yaml -n lower
```
And then offload the namespace (since the operator must run on the consumer cluster, we apply it before offloading the namespace, otherwise we should modify the operator.yaml file to add a nodeSelector rule)
```
liqoctl offload namespace lower --namespace-mapping-strategy EnforceSameName
```
Now one should modify the `deploy/cr.yaml` setting the appropriate configurations. For convenience, we save a copy of the [already configured](./deploy/cr.yaml) file in this repository.
```
kubectl apply -f deploy/cr.yaml -n lower
```
Use the following command to retrieve the root password of the database (if using the default secret)
```
kubectl get secret cluster1-secrets -n lower --template='{{.data.root | base64decode}}{{"\n"}}'
```
Launch a mysql-client to verify that the previous configuration changes have been patched correctly, and in case set the corresponding variables
```
kubectl run mysql-client --image=mysql:latest -it --rm --restart=Never -- /bin/bash
mysql -h cluster1-haproxy.lower.svc.cluster.local -uroot -proot_password
SHOW VARIABLES LIKE 'auto_increment_increment';
SET GLOBAL auto_increment_increment=1;
```

### Model-based and Intent-driven Meta-Orchestrator

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
  UPDATE_FLAVORS: "False"
  UPDATE_FLAVORS_INTERVAL: "360"
  ELECTRICITY_MAP_API_KEY: "REbFju22LwHPVT3t1Y0IKh1I"
  architecture: "amd64"
  MSPL_ENDPOINT: "http://fluidos-mspl.sl.cloud9.ibm.com:8002/meservice"
  monitor_enabled: "True"
  monitor_interval: "2"
  prometeus_endpoint: "http://localhost:9090"
  MONITOR_CONTRACTS: "False"
  SKIP_PEERING: "True"
  HOST_MAPPING: "vr.fluidos.eu:2b2c5c29-cbcd-451d-a231-acc5806b302d;rm.fluidos.eu:d93276fe-14ad-4921-9fb1-a6305bfbaac5"

```
```
kubectl apply -f fluidos-modelbased-metaorchestrator/mbmo-config-map.yaml -n fluidos
```
Configure the /fluidos-modelbased-metaorchestrator/utils/prometheus/config/prometheus.yml file as follows:

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

### Ping sidecar container image

On each node use following commands to build the `ping-sidecar` image, save it as a `.tar` archive, and import it into the k3s container runtime:

```
sudo docker build -t myregistry/ping-sidecar:latest . && \
sudo docker save myregistry/ping-sidecar2 -o ./ping-sidecar.tar && \
sudo k3s ctr image import ping-sidecar.tar
```
Run on the consumer node:
```
kubectl apply -f deploy/flavor-reader-rbac.yaml 
```

### PDC
Finally, we can apply from the consumer the OpenPDC application with the command
```
kubectl apply -f deploy/openpdc-lower-level-y3.yaml -n lower
```
To connect the [OpenPDC Manager](https://github.com/GridProtectionAlliance/openPDC/releases/tag/v2.4) GUI with the orchestrated backend, obtain the NodePort of the database with the command
```
kubectl describe svc cluster1-haproxy-replicas -n lower
```
and use it to connect with the cluster enabling port-forwarding with a command like
```
ssh -L 3306:localhost:NodePort -L 8500:localhost:30085 -L 6165:localhost:30065 user@kubernetes-node
```
We can also apply the OpenPDC higher level application on the consumer node: 

```
kubectl apply -f deploy/openpdc-higher-level.yaml -n higher
```
Then we can use the GUI to configure the PMUs' connection and output streams forming a hierarchical architecture.

## Intent Definition and Scenario

The scenario is described as follows:

1. The orchestration intent is defined in the openpdc-lower-level-y3.yaml PDC YAML file:

   ```yaml
   fluidos-intent-latency: 100
   ```

   This specifies that the workload must run only on provider nodes capable of meeting a 100 ms latency threshold.

2. When the lower-level PDC is launched, MIMO evaluates the available providers:

   * Provider 1 (rm.fluidos.eu): latency 80 ms
   * Provider 2 (vr.fluidos.eu): latency 90 ms
     Both satisfy the declared intent, and MIMO selects one provider for PDC deployment.

3. The Ping sidecar container continuously measures round-trip time (RTT) using ICMP probes and sends data to MIMO's Prometheus.

   * Latency samples are aggregated (last 10 measurements) to assess compliance with the declared intent.
   * If latency remains within threshold, no action is taken.

4. When artificial latency fluctuations are introduced, the sidecar detects the increase and updates MIMO.

   * The flavor definition of Provider 1 is updated with the new latency value.
   * Since it no longer meets the latency constraint, MIMO automatically reschedules the PDC workload to Provider 2.


This sequence demonstrates the intent-driven orchestration capability of MIMO.

---

## License and Acknowledgments
This project is licensed under the Apache License - version 2.0, see the [LICENSE](LICENSE) file for details.

This project includes some previous work done by [Claudio Usai](https://github.com/claudious96), [Claudio Lorina](https://github.com/claudiolor) and [Riccardo Medina](https://github.com/rmedina97) as part of their master thesis at Politecnico di Torino.
