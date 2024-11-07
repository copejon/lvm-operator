#!/bin/bash

set -eux

DUMP_KUSTOMIZE=false
while getopts "t:n:i:d" OPT; do
    case "${OPT}" in
        t)
            TAG="${OPTARG}"
            ;;
        n)
            NS="${OPTARG}"
            ;;
        i)
            IMAGE_REPO="${OPTARG}"
            ;;
        d)
            DUMP_KUSTOMIZE=true
            ;;
        ?|*)
            exit 1
            ;;
    esac
done

F_KUST="$(mktemp -d)/kustomization.yaml"

cat <<EOF > "${F_KUST}"
---
# Generated kustomization file data:
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
namespace: "$NS"

resources:
- https://gitlab.com/kubesan/kubesan/deploy/openshift?ref=v0.7.0

patches:
- patch: |-
    kind: List
    apiVersion: v1
    items:
    - kind: SecurityContextConstraints
      apiVersion: security.openshift.io/v1
      metadata:
        name: kubesan
      users:
      - system:serviceaccount:${NS}:csi-controller-plugin
      - system:serviceaccount:${NS}:csi-node-plugin
      - system:serviceaccount:${NS}:cluster-controller-manager
      - system:serviceaccount:${NS}:node-controller-manager

patchesStrategicMerge:
- |-
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: csi-controller-plugin
    namespace: kubesan-system
  \$patch: delete
- |-
  apiVersion: apps/v1
  kind: Deployment
  metadata:
    name: csi-controller-plugin
    namespace: kubesan-system
  \$patch: delete
- |-
  apiVersion: storage.k8s.io/v1
  kind: CSIDriver
  metadata:
    name: kubesan.gitlab.io
  \$patch: delete
- |-
  apiVersion: v1
  kind: ServiceAccount
  metadata:
    name: csi-node-plugin
    namespace: kubesan-system
  \$patch: delete
- |-
  apiVersion: apps/v1
  kind: DaemonSet
  metadata:
    name: csi-node-plugin
    namespace: kubesan-system
  \$patch: delete

EOF

# Override Kubesan image
if [ -n "${IMAGE_REPO}" ]; then
    cat <<EOF >> "${F_KUST}"

images:
- name: quay.io/kubesan/kubesan
  newName: ${IMAGE_REPO}
  newTag: ${TAG}
EOF
fi

if $DUMP_KUSTOMIZE; then
    oc apply \
        --dry-run=client \
        -k  "$(dirname "${F_KUST}")" \
        -o yaml
else
        oc apply -k "$(dirname "${F_KUST}")"
fi

>&2 echo
>&2 echo "-- Generated kustomization file at ${F_KUST}"
