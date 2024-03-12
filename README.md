# Intelligent Power Grid

This document provides a brief introduction to the implementation of the Intelligent Power Grid use case testbed. Our goal is to install the demo within two Kubernetes clusters, each of which is running a single Kubernetes node on a virtual machine with 8GB of RAM, 4 vCPU and a fresh volume of Ubuntu 20.04 LTS.

## Requirements
As software requirements, after updating and upgrading all the packages, we have to install Helm, Kubectl and Liqoctl. These steps must be performed on both virtual machines.
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
```
curl -sfL https://get.k3s.io | INSTALL_K3S_VERSION=v1.23.14+k3s1 sh -s - server --cluster-init --kube-apiserver-arg="default-not-ready-toleration-seconds=20" --kube-apiserver-arg="default-unreachable-toleration-seconds=20" --write-kubeconfig-mode 644
```
### Liqoctl
From the [Liqoctl documentation](https://docs.liqo.io/en/v0.9.4/installation/liqoctl.html) on Liqo's website, we run:
```
curl --fail -LS "https://github.com/liqotech/liqo/releases/download/v0.9.4/liqoctl-linux-amd64.tar.gz" | tar -xz
install -o root -g root -m 0755 liqoctl /usr/local/bin/liqoctl
rm liqoctl
```

## Install and configure Liqo
From the [Liqo documentation](https://docs.liqo.io/en/v0.9.4/installation/install.html), set the local variable KUBECONFIG and install Liqo on both virtual machines:
```
export KUBECONFIG="/etc/rancher/k3s/k3s.yaml"
liqoctl install k3s --version v0.9.4 --set storage.realStorageClassName=longhorn
liqoctl status
```
N.B.
- Be carefull with the version: liqoctl and Liqo versions must match. With the previous commands we install version v0.9.4 of Liqo and liqoctl v0.9.4. You can check the installed versions with the command `liqoctl version`.
- Furthermore, the option `--set storage.realStorageClassName=longhorn` is needed when one later deploys the mysql pod of the demo. If not set, when using the liqo storageclass, the offloaded (real) PVC uses the default storageclass `local-path` in the remote cluster, hence not bounding any (real) PV (there is the same problem if the pod is not offloaded; the real PVC uses the default storageclass of the local cluster). For further details, see [ref1](https://github.com/liqotech/liqo/issues/1870) and [ref2](https://github.com/liqotech/liqo/blob/master/deployments/liqo/values.yaml).

You can show the pods belonging to the liqo namespace with the command
```
kubectl get pods -n liqo
```
### Enable peering and offload a namespace
On the **remote** cluster, generate the peering command:
```
liqoctl generate peer-command
```
and then run the output on the **local** cluster.
You can check the peering status with one of the following
```
kubectl get foreignclusters
liqoctl status peer <cluster-name>
```
as well as from the node list, where a new virtual node should have appeared.
Now, to leverage remote resources, from the local cluster create and offload a dedicated namespace
```
kubectl create namespace liqo-demo
liqoctl offload namespace liqo-demo --namespace-mapping-strategy EnforceSameName
```
Liqo will add a suffix to the namespace name on the remote cluster to make it unique, to avoid it just add the option above.
Finally, from the local cluster, deploy an application in the dedicated namespace
```
kubectl apply -f <filename.yaml> -n liqo-demo
```

## Install the testbed
In order to guarantee volumes replications and persisentcy, we install Longhorn on both virtual machines:
```
apt install open-iscsi nfs-common
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
kubectl create namespace longhorn-system
helm repo add longhorn https://charts.longhorn.io
helm repo update
helm install longhorn longhorn/longhorn \
--namespace longhorn-system \
--set defaultSettings.nodeDownPodDeletionPolicy="delete-both-statefulset-and-deployment-pod" \
--set defaultDataLocality="best-effort" \
--version 1.3.2
```
Then, we apply the storageclass
```
kubectl apply -f storageclass-lh.yaml
```



