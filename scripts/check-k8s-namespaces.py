"""Fail if a rendered manifest has a namespaced object without a namespace.

    kustomize build deploy/k8s/overlays/prod | python3 scripts/check-k8s-namespaces.py

kubeconform accepts such objects, but kubectl then creates them in "default",
where the app's pods can't see them (it happened to li-config on the first
release). Used by `make k8s-check`.
"""

import sys

# Kinds that don't live in a namespace.
CLUSTER_SCOPED = {
    "Namespace",
    "ClusterRole",
    "ClusterRoleBinding",
    "CustomResourceDefinition",
    "PriorityClass",
    "StorageClass",
}

missing = []
for doc in sys.stdin.read().split("\n---\n"):
    kind = name = namespace = None
    in_metadata = False
    for line in doc.splitlines():
        if line.startswith("kind:"):
            kind = line.split()[1]
        elif line.startswith("metadata:"):
            in_metadata = True
        elif in_metadata and line and not line.startswith(" "):
            in_metadata = False
        elif in_metadata and line.startswith("  name:") and name is None:
            name = line.split()[1]
        elif in_metadata and line.startswith("  namespace:"):
            namespace = line.split()[1]
    if kind and kind not in CLUSTER_SCOPED and not namespace:
        missing.append(f"{kind}/{name}")

if missing:
    print("No namespace (would land in 'default'): " + ", ".join(missing))
    sys.exit(1)
print("All namespaced objects have a namespace.")
