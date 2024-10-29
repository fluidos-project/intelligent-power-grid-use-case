# Intelligent Power Grid

This document provides a brief introduction to the implementation of the Intelligent Power Grid use case testbed. Our goal is to install the demo within two FLUIDOS nodes **v0.1.0-rc.1**, each of which is running a single Kubernetes node on a virtual machine with 16GB of RAM, 8 vCPU and a fresh volume of Ubuntu 20.04 LTS. This guide is inspired by the [documentation](https://github.com/fluidos-project/node/blob/v0.1.0-rc.1/docs/installation/installation.md#manual-installation) provided in the [Node](https://github.com/fluidos-project/node/) repository.

## Requirements
As software requirements, after updating and upgrading all the packages, we have to install Helm, Kubectl, Liqoctl and Longhorn. The first three are FLUIDOS requirements from the testbed while Longhorn is required by our application for internal-cluster data replication. Docker and KinD are not needed in this setup.
The following steps must be performed on both virtual machines.
### Helm
From the [Helm documentation](http://helm.sh/docs/intro/install/#from-apt-debianubuntu):
```
apt-get install apt-transport-https
curl https://baltocdn.com/helm/signing.asc | gpg --dearmor | sudo tee /usr/share/keyrings/helm.gpg > /dev/null
echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/helm.gpg] https://baltocdn.com/helm/stable/debian/ all main" | sudo tee /etc/apt/sources.list.d/helm-stable-debian.list
apt-get update
apt-get install helm
```
### Kubectl
We install K3s distribution of Kubernetes, which features a very limited resource consumption, performance close to vanilla Kubernetes and a very simple setup procedure. This will allow the testbed to be replicated also onto edge devices like, Raspberry Pis.
On the **consumer** cluster, we install K3s with the options
```
curl -sfL https://get.k3s.io | K3S_NODE_NAME=fluidos-consumer INSTALL_K3S_VERSION=v1.24.17+k3s1 sh -s - server --cluster-init --kube-apiserver-arg="default-not-ready-toleration-seconds=20" --kube-apiserver-arg="default-unreachable-toleration-seconds=20" --write-kubeconfig-mode 644 --cluster-cidr="10.48.0.0/16" --service-cidr="10.50.0.0/16"
```
while on the **provider** cluster we run
```
curl -sfL https://get.k3s.io | K3S_NODE_NAME=fluidos-provider INSTALL_K3S_VERSION=v1.24.17+k3s1 sh -s - server --cluster-init --kube-apiserver-arg="default-not-ready-toleration-seconds=20" --kube-apiserver-arg="default-unreachable-toleration-seconds=20" --write-kubeconfig-mode 644 --cluster-cidr="10.58.0.0/16" --service-cidr="10.60.0.0/16"
```
### Liqoctl
From the [Liqoctl documentation](https://docs.liqo.io/en/v0.10.3/installation/liqoctl.html) on Liqo's website, we run:
```
curl --fail -LS "https://github.com/liqotech/liqo/releases/download/v0.10.3/liqoctl-linux-amd64.tar.gz" | tar -xz
install -o root -g root -m 0755 liqoctl /usr/local/bin/liqoctl
rm liqoctl
```
### Longhorn
From the [Longhorn documentation](https://longhorn.io/docs/1.6.2/deploy/install/install-with-helm/), install Longhorn dependencies
```
apt install open-iscsi nfs-common
```
Expose the rancher/k3s configs in a place where Longhorn can read them
```
mkdir /root/.kube
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
```
Anf finally install Longhorn (this may take a few minutes)
```
kubectl create namespace longhorn-system
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
--namespace longhorn-system \
--set defaultSettings.nodeDownPodDeletionPolicy="delete-both-statefulset-and-deployment-pod" \
--set defaultDataLocality="best-effort" \
--version 1.3.2
```
Then, apply the [storageclass](./deploy/storageclass-lh.yaml)
```
kubectl apply -f deploy/storageclass-lh.yaml
```

## FLUIDOS Setup
First, clone the FLUIDOS Node repository, carefully selecting the right version
```
wget https://github.com/fluidos-project/node/archive/refs/tags/v0.1.0-rc.1.zip
unzip v0.1.0-rc.1.zip
rm v0.1.0-rc.1.zip
mv node-0.1.0-rc.1 node
```
The file [setup.sh](https://github.com/fluidos-project/node/blob/v0.1.0-rc.1/tools/scripts/setup.sh), stored in `node/tools/scripts/setup.sh`, contains the instructions to install two worker nodes and one control plane with KinD. From it we extract the commands to setup a testbed with two K3s clusters, each one with a single node.
Name and labels must bepecified, thus on the consumer we run
```
kubectl label nodes fluidos-consumer node-role.fluidos.eu/resources=true node-role.fluidos.eu/worker=true 
```
while on the provider cluster
```
kubectl label nodes fluidos-provider node-role.fluidos.eu/resources=true node-role.fluidos.eu/worker=true 
```
To check that the label is set correctly
```
kubectl describe node fluidos-provider
```
Then, on both machines we run
```
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
helm repo add fluidos https://fluidos-project.github.io/node/
helm repo update
```
Finally, on the **consumer** cluster
```
liqoctl install k3s --cluster-name fluidos-consumer \
  --version v0.10.3 \
  --set storage.realStorageClassName=longhorn \
  --pod-cidr="10.48.0.0/16" \
  --service-cidr="10.50.0.0/16"
  
helm install node fluidos/node -n fluidos \
  --create-namespace -f node/quickstart/utils/consumer-values.yaml \
  --set networkManager.configMaps.nodeIdentity.ip="192.168.30.83:30000" \
  --set networkManager.configMaps.providers.local="192.168.30.154:30001" \
  --version 0.1.0-rc.1 \
  --wait
```
while on the **provider** cluster
```
liqoctl install k3s --cluster-name fluidos-provider \
  --version v0.10.3 \
  --set storage.realStorageClassName=longhorn \
  --pod-cidr="10.58.0.0/16" \
  --service-cidr="10.60.0.0/16"
  
helm install node fluidos/node -n fluidos \
  --create-namespace -f node/quickstart/utils/provider-values.yaml \
  --set networkManager.configMaps.nodeIdentity.ip="192.168.30.154:30001" \
  --set networkManager.configMaps.providers.local="192.168.30.83:30000" \
  --version 0.1.0-rc.1 \
  --wait
```
To check the installation status
```
kubectl get pods -A
liqoctl status
kubectl get flavours.nodecore.fluidos.eu -n fluidos
```
Now, to leverage remote resources, on the **consumer** cluster run
```
kubectl apply -f node/deployments/node/samples/solver.yaml
kubectl get solver -n fluidos
```
One can modify the parameters in the solver to reserve more resources, in our case we set 4Gi of RAM and 4000m of CPU. This command also establishes the peering! To check it run one of the following
```
liqoctl status peer
kubectl get solver -n fluidos
```

## Percona Operator for MySQL
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

## OpenPDC
Finally, we can apply the OpenPDC application with the command
```
kubectl apply -f deploy/openpdc-lower-level.yaml -n lower
```
To connect the [OpenPDC Manager](https://github.com/GridProtectionAlliance/openPDC/releases/tag/v2.4) GUI with the orchestrated backend, obtain the NodePort of the database with the command
```
kubectl describe svc cluster1-haproxy-replicas -n lower
```
and use it to connect with the cluster enabling port-forwarding with a command like
```
ssh -L 3306:localhost:NodePort -L 8500:localhost:30085 -L 6165:localhost:30065 user@kubernetes-node
```

## License and Acknowledgments
This project is licensed under the Apache License - version 2.0, see the [LICENSE](LICENSE) file for details.

This project includes some previous work done by [Claudio Usai](https://github.com/claudious96), [Claudio Lorina](https://github.com/claudiolor) and [Riccardo Medina](https://github.com/rmedina97) as part of their master thesis at Politecnico di Torino.
