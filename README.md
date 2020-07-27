# Used versions
```
- Kubevirt 0.28.0 (with minor customizations) https://github.com/kozhukalov/kubevirt/tree/branch-0.28.0
- Multus CNI plugin 3.4.2 (see multus file in the current repo or https://github.com/intel/multus-cni/releases/tag/v3.4.2)
- Sriov CNI plugin v2.3 (see sriov file in the current repo or https://github.com/intel/sriov-cni/releases/tag/v2.3)
```

# Update model to use k8s formula from github

```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/infra/salt_master_formulas.yml

parameters:
  salt:
    master:
      environment:
        prd:
          formula:
            kubernetes:
              source: git
              address: https://github.com/reddydodda/salt-formulas-kubernetes.git
              revision: master
              branch: master
```

# Deploy kubevirt

Update Cluster model to have kubevirt and multus pillar

```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/kubernetes/common.yml

parameters:
  kubernetes:
    pool:
      network:
        multus:
          enabled: true
          delegates:
            - type: bridge
              name: bridge01
            - type: bridge
              name: bridge02
            - type: sriov
              name: sriov-eth1
            - type: sriov
              name: sriov-eth2
```

```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/kubernetes/control.yml

parameters:
  kubernetes:
    common:
      addons:
        kubevirt:
          enabled: true
          image: index.docker.io/kubevirt73/virt-operator:20200709
        multus:
          enabled: true
```


```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/kubernetes/init.yml

    kubernetes_cniplugins_source: 'http://magma-mirantis-com.s3.amazonaws.com/containernetworking-plugins_v0.8.2-8-gad527c5.tar.gz'
    kubernetes_cniplugins_source_hash: md5=e8dbf4ab36379c1bb8878016dfa1fe30

```

```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/kubernetes/networking/physical.yml

  _param:
    kubernetes_sriov_pf_nic1: ens801f0
    kubernetes_sriov_pf_nic2: ens801f1
    kubernetes_sriov_numvfs: 10
  linux:
## SR-IOV
    system:
      kernel:
        sriov: True
        modules:
        - i40e
        - i40evf
        - vfio_pci
        module:
          vfio_iommu_type1:
            option:
              allow_unsafe_interrupts: 1
          i40e:
            option:
              max_vfs: ${_param:kubernetes_sriov_numvfs}
      rc:
        local: |
          #!/bin/sh -e
          # Enabling ${_param:kubernetes_sriov_pf_nic1} VFs on ${_param:kubernetes_sriov_pf_nic1} PF
          echo ${_param:kubernetes_sriov_numvfs} > /sys/class/net/${_param:kubernetes_sriov_pf_nic1}/device/sriov_numvfs; sleep 2; ip link set ${_param:kubernetes_sriov_pf_nic1} up
          echo ${_param:kubernetes_sriov_numvfs} > /sys/class/net/${_param:kubernetes_sriov_pf_nic2}/device/sriov_numvfs; sleep 2; ip link set ${_param:kubernetes_sriov_pf_nic2} up
          exit 0
```

Run Linux and kubernetes states to deploy sriov and kubevirt 


1. salt 'cmp*' saltutil.refresh_pillar

2. salt 'cmp*' state.sls linux.system,linux.network;reboot --async

3. salt-call state.sls salt.master -l debug 

4. salt 'cmp*' state.sls kubernetes -l debug 

5. salt 'cmp*' state.sls kubernetes -l debug


# Deploy SR-IOV device plugin
SR-IOV device plugin is used to dynamically allocate VFs using filtered VF pools.

First let's label nodes with SR-IOV network insterfaces
```
vim /srv/salt/reclass/classes/cluster/<cluster_name>/kubernetes/control.yml

parameters:
  kubernetes:
    master:
      label:
        ctl01:
          value: sriov
          key: true
          node: cmp01
          enabled: true

```

Now let's deploy SR-IOV daemonset (in the deployment manifest you can configure the interface name, PCI address range, etc.)

```
kubectl apply -f sriovdp.yaml
```

#Multus plugin requires admin kubeconfig. To generate it use this
```
# requires kubectl installed
./gen_multus_kubeconfig.sh
```

Then copy generated kubeconfig file to compute node
```
scp multus.kubeconfig cmp01:/etc/kubernetes/multus.kubeconfig

```

# Deploy VM Pod

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

To build custom image use Dockerfile in the repo. Modify if needed.
```
docker build -t kubevirt73/xenial:latest .
docker push kubevirt73/xenial:latest
```

It is also possible to use PVCs as VM images using containerized data importer.
