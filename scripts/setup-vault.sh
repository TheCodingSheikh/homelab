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

# Create a secret in the crossplane namespace with Vault credentials
kubectl create secret generic vault-creds -n crossplane \
  --from-literal=credentials="{ \"token\": \"$root_token\" }" --dry-run=client -o yaml | kubectl apply -f -

# Create a secret in the vault namespace with the root token
kubectl create secret generic vault-token -n external-secrets \
  --from-literal=token=$root_token --dry-run=client -o yaml | kubectl apply -f -

# TODO: fix this
# Keep trying to write init_output to Vault until success
while true; do
  kubectl exec -n $namespace $pod_name -- vault kv put kv/security/vault data="$init_output" && break
  echo "Retrying to write Vault initialization data..."
  sleep 5
done

echo "Vault has been initialized and unsealed."
echo "Root Token: $root_token"
