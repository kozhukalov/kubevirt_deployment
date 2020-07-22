# Used versions
- Kubevirt 0.28.0 (with minor customizations) https://github.com/kozhukalov/kubevirt/tree/branch-0.28.0
- Multus CNI plugin 3.4.2 (see multus file in the current repo or https://github.com/intel/multus-cni/releases/tag/v3.4.2)
- Sriov CNI plugin v2.3 (see sriov file in the current repo or https://github.com/intel/sriov-cni/releases/tag/v2.3)

# Deploy kubevirt
Deploy namespace, CRD, RBAC and kubevirt operator. 
```
kubectl apply -f kubevirt-operator.yaml
```

Deploy kubevirt CR
```
kubectl apply -f kubevirt-cr.yaml
```

This will deploy custom kubevirt build (v.0.28.0) which 
- runs VM instances with privileged containers
- runs VM containers without default apparmor profile
- mounts the whole /sys and /dev inside VM containers (needed for SR-IOV)

## Build and push custom kubevirt images
The customization is available here https://github.com/kozhukalov/kubevirt/tree/branch-0.28.0
The docker image which is used for deployment is index.docker.io/kubevirt73/virt-operator:20200709

```
git clone https://github.com/kozhukalov/kubevirt -b branch-0.28.0
cd kubevirt
export DOCKER_PREFIX=index.docker.io/kubevirt73
export DOCKER_TAG=kubevirt73
make && make push
```

# Deploy SR-IOV device plugin
SR-IOV device plugin is used to dynamically allocate VFs using filtered VF pools.

First let's label nodes with SR-IOV network insterfaces
```
kubectl label nodes cmp01 sriov=true
```

Now let's deploy SR-IOV daemonset (in the deployment manifest you can configure the interface name, PCI address range, etc.)
```
kubectl apply -f sriovdp.yaml 
```

# Deploy CNI plugins
## Multus
Install Multus CRD
```
kubectl apply -f multus-crd.yaml
```

Multus plugin requires admin kubeconfig. To generate it use this
```
# requires kubectl installed
./gen_multus_kubeconfig.sh
```

Then copy generated kubeconfig file to compute node
```
scp multus.kubeconfig cmp01:/etc/kubernetes/multus.kubeconfig
```

Deploy Multus CNI meta plugin on compute node
```
cp multus /opt/cni/bin
cp 00-multus.conf /etc/cni/net.d
```

Multus is looking for delegate plugin configurations 
- first in the kube-system network-attachment-definition CR by name
- second in the /etc/cni/net.d files by names defined inside files (NOT filenames)

Multus config defines clusterNetwork equal to `calico-k8s-network`. This is the name of the calico network.
Calico cni config with the name must be placed here `/etc/cni/net.d`. It is important that calico must be configured so
that IP forwarding is enabled inside containers. It must contain this 

```json
    "container_settings": {
        "allow_ip_forwarding": true
    },
```

## SR-IOV
Deploy SR-IOV CNI plugin 
```
cp sriov /opt/cni/bin
```

Deploy SR-IOV network-attachment-definition  (default namespace)

```
kubectl apply -f sriov-cr.yaml
```

Configure this how necessary (vlan, ipam, master interface)

# Start VM pod
Deploy VM instance. Take a look at what is defined in the network and interfaces sections
```
kubectl apply -f vmi-sriov.yaml
```

To build custom image use Dockerfile in the repo. Modify if needed.
```
docker build -t kubevirt73/xenial:latest .
docker push kubevirt73/xenial:latest
```

It is also possible to use PVCs as VM images using containerized data importer.
