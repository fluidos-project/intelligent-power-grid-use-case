#!/bin/bash

K3S_VERSION="v1.24.17+k3s1"
LIQO_VERSION="v0.10.3"
FLUIDOS_VERSION="0.1.1"
HELM_REPO_LONGHORN="https://charts.longhorn.io"
HELM_REPO_FLUIDOS="https://fluidos-project.github.io/node/"

# k3s Installation
sudo rm -f /run/cni/dhcp.sock
echo "Installing k3s on consumer..."
sudo curl -sfL https://get.k3s.io | K3S_NODE_NAME=cloud INSTALL_K3S_VERSION=$K3S_VERSION K3S_TOKEN=politorse sh -s - server --cluster-init --kube-apiserver-arg="default-not-ready-toleration-seconds=20" --kube-apiserver-arg="default-unreachable-toleration-seconds=20" --write-kubeconfig-mode 644 --cluster-cidr="10.48.0.0/16" --service-cidr="10.50.0.0/16"
if [ $? -ne 0 ]; then
    echo "Error during k3s installation. Exiting."
    exit 1
fi
echo "Waiting for k3s to start..."
while ! systemctl is-active --quiet k3s; do
    sleep 2
done

echo "k3s active, proceeding with the next command."
echo "Waiting for the node to be ready"
while [[ $(kubectl get nodes --no-headers 2>/dev/null | awk '{print $2}') != "Ready" ]]; do
    sleep 2
done
# Node label
kubectl label nodes cloud node-role.fluidos.eu/resources=true node-role.fluidos.eu/worker=true
if [ $? -ne 0 ]; then
    echo "Node labeling error. Exiting."
    exit 1
fi
# Modify ConfigMap CoreDNS to use internal DNS 
# kubectl -n kube-system patch configmap coredns \
#   --type merge \
#   -p '{"data":{"Corefile":".:53 {\n    errors\n    health\n    ready\n    kubernetes cluster.local in-addr.arpa ip6.arpa {\n       pods insecure\n       fallthrough in-addr.arpa ip6.arpa\n    }\n    forward . 172.25.120.7\n    cache 30\n    loop\n    reload\n    loadbalance\n}"}}'

# Restarting CoreDNS to apply the change.
# kubectl -n kube-system rollout restart deployment coredns


# Longhorn installaion
cp /etc/rancher/k3s/k3s.yaml /root/.kube/config
if [ $? -ne 0 ]; then
    echo "Error copying K3s configuration file. Exiting."
    exit 1
fi

kubectl create namespace longhorn-system
if [ $? -ne 0 ]; then
    echo "Error creating the longhorn-system namespace. Exiting."
    exit 1
fi

helm repo add longhorn $HELM_REPO_LONGHORN
if [ $? -ne 0 ]; then
    echo "Error adding the Longhorn repository. Exiting."
    exit 1
fi

helm repo update
if [ $? -ne 0 ]; then
    echo "Error updating the Helm repository. Exiting."
    exit 1
fi

helm install longhorn longhorn/longhorn \
--namespace longhorn-system \
--set defaultSettings.nodeDownPodDeletionPolicy="delete-both-statefulset-and-deployment-pod" \
--set defaultDataLocality="best-effort" \
--version 1.3.2
if [ $? -ne 0 ]; then
    echo "Errore intalling Longhorn. Exiting."
    exit 1
fi

kubectl apply -f liqo/deploy/storageclass.yaml
if [ $? -ne 0 ]; then
    echo "Error applying Liqo storage class. Exiting."
    exit 1
fi

# FLUIDOS Installation
helm repo add fluidos $HELM_REPO_FLUIDOS
if [ $? -ne 0 ]; then
    echo "Error adding FLUIDOS repo. Exiting."
    exit 1
fi

helm repo update
if [ $? -ne 0 ]; then
    echo "Error updating FLUIDOS repo. Exiting."
    exit 1
fi

liqoctl install k3s --cluster-name cloud --version $LIQO_VERSION --pod-cidr="10.48.0.0/16" --service-cidr="10.50.0.0/16" --set storage.realStorageClassName=longhorn
if [ $? -ne 0 ]; then
    echo "Error installing Liqo. Exiting."
    exit 1
fi

kubectl apply -f liqo/deploy/multus.yaml -n kube-system
if [ $? -ne 0 ]; then
    echo "Error applying Multus. Exiting."
    exit 1
fi

echo "Waiting fot the CRD NetworkAttachmentDefinition to be available..."
while ! kubectl get crd network-attachment-definitions.k8s.cni.cncf.io &>/dev/null; do
    sleep 2
done
echo "CRD available!"

helm upgrade --install node fluidos/node \
    -n fluidos --version "0.1.1" \
    --create-namespace -f node/quickstart/utils/consumer-values.yaml \
    --set networkManager.configMaps.nodeIdentity.ip="172.25.xx.xx" \
    --set rearController.service.gateway.nodePort.port="30000" \
    --set networkManager.config.enableLocalDiscovery=true \
    --set networkManager.config.address.thirdOctet="1" \
    --set networkManager.config.netInterface="eno1" \
    --wait \
    --debug \
    --v=2
if [ $? -ne 0 ]; then
    echo "Error upgrading FLUIDOS node. Exiting."
    exit 1
fi
kubectl get flavor -n fluidos --no-headers --kubeconfig /etc/rancher/k3s/k3s.yaml | cut -f1 -d\  | xargs -I% kubectl patch flavor/%  --patch-file ./flavors-cao-mi.yaml --type merge -n fluidos --kubeconfig /etc/rancher/k3s/k3s.yaml
# registries.yaml configuration
echo "Configuration of registry mirror..."
sudo tee /etc/rancher/k3s/registries.yaml > /dev/null <<EOL
mirrors:
  "gitlab.rse-web.it:5005":
    endpoint:
      - "http://gitlab.rse-web.it:5005"
configs:
  "gitlab.rse-web.it:5005":
    tls:
      insecure_skip_verify: true
EOL

if [ $? -ne 0 ]; then
    echo "Error configuring registry mirror. Exiting."
    exit 1
fi
echo "K3s restart"
sudo systemctl restart k3s

if [ $? -ne 0 ]; then
    echo "Error restarting K3s. Exiting."
    exit 1
fi


echo "Waiting  K3s sia nuovamente attivo..."
while ! systemctl is-active --quiet k3s; do
    sleep 2
done
echo "K3s active!"

echo "Installation complete!"
