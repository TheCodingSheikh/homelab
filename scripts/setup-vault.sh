#!/bin/bash

# Namespace and Pod Name
namespace="vault"
pod_name="vault-0"

# Initialize Vault and capture the output
init_output=$(kubectl exec -n $namespace $pod_name -- vault operator init -key-shares=5 -key-threshold=3 -format=json)

# Extract the unseal key and root token
unseal_key_0=$(echo $init_output | jq -r '.unseal_keys_b64[0]')
unseal_key_1=$(echo $init_output | jq -r '.unseal_keys_b64[1]')
unseal_key_2=$(echo $init_output | jq -r '.unseal_keys_b64[2]')
root_token=$(echo $init_output | jq -r '.root_token')

# Unseal Vault
kubectl exec -n $namespace $pod_name -- vault operator unseal $unseal_key_0
kubectl exec -n $namespace $pod_name -- vault operator unseal $unseal_key_1
kubectl exec -n $namespace $pod_name -- vault operator unseal $unseal_key_2

# Authenticate with Vault using root token
kubectl exec -n $namespace $pod_name -- vault login $root_token

# # Create a secret in the crossplane namespace with Vault credentials
# kubectl create secret generic vault-creds -n crossplane \
#   --from-literal=credentials="{ \"token\": \"$root_token\" }" --dry-run=client -o yaml | kubectl apply -f -

# Create a secret in the vault namespace with the root token
kubectl create secret generic vault-token -n vault \
  --from-literal=token=$root_token \
  --from-literal=json="{ \"token\": \"$root_token\" }" \
  --dry-run=client -o yaml | kubectl apply -f -

# Create Kubernetes secret containing all fields
secret_manifest=$(cat <<EOF
apiVersion: v1
kind: Secret
metadata:
  name: vault-init-data
  namespace: vault
type: Opaque
stringData:
  unseal_keys_b64: |
    $(echo "$init_output" | jq -c '.unseal_keys_b64')
  unseal_keys_hex: |
    $(echo "$init_output" | jq -c '.unseal_keys_hex')
  unseal_shares: "$(echo "$init_output" | jq -r '.unseal_shares')"
  unseal_threshold: "$(echo "$init_output" | jq -r '.unseal_threshold')"
  root_token: "$(echo "$init_output" | jq -r '.root_token')"
EOF
)

echo "$secret_manifest" | kubectl apply -f -

while true; do
  kubectl exec -n $namespace $pod_name -- vault kv put secret/security/vault unseal_keys_b64=$(echo "$init_output" | jq -c '.unseal_keys_b64') && break
  kubectl exec -n $namespace $pod_name -- vault kv put secret/security/vault unseal_keys_hex=$(echo "$init_output" | jq -c '.unseal_keys_hex') && break
  kubectl exec -n $namespace $pod_name -- vault kv put secret/security/vault unseal_shares="$(echo "$init_output" | jq -r '.unseal_shares')" && break
  kubectl exec -n $namespace $pod_name -- vault kv put secret/security/vault unseal_threshold="$(echo "$init_output" | jq -r '.unseal_threshold')" && break
  kubectl exec -n $namespace $pod_name -- vault kv put secret/security/vault root_token="$(echo "$init_output" | jq -r '.root_token')" && break
  echo "Retrying to write Vault initialization data..."
  sleep 5
done

echo "Vault has been initialized and unsealed."
echo "Root Token: $root_token"
