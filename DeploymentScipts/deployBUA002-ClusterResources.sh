#!/bin/bash

# add the yq repository to the repo collection & install
sudo add-apt-repository ppa:rmescandon/yq
sudo apt-get install yq

RG_NAME='rg-aksagic-dev0001'
SUBSCRIPTION_ID=""
TENANT_ID=""

# Get the name of the cluster from the spoke deployment outputs
CLUSTER_NAME=$(jq -r ".aksClusterName.value" spoke2deployment-outputs.json)
# Set the context to the cluster in the first spoke
az aks get-credentials -n $CLUSTER_NAME -g $RG_NAME --admin

############## TEMP CODE BLOCK (To be removed)######################
# export IDENTITY_RESOURCE_GROUP="$(az aks show -g ${RG_NAME} -n ${CLUSTER_NAME} --query nodeResourceGroup -otsv)"

# get the client-Id of the managed identity assigned to the node pool
# AGENTPOOL_IDENTITY_CLIENTID=$(az aks show -g $RG_NAME -n $CLUSTER_NAME --query identityProfile.kubeletidentity.clientId -o tsv)

# perform the necessary role assignments to the managed identity of the nodepool (used by the kubelet)
# Important Note: The roles Managed Identity Operator and Virtual Machine Contributor must be assigned to the cluster managed identity or service principal, identified by the ID obtained above, 
# ""before deploying AAD Pod Identity"" so that it can assign and un-assign identities from the underlying VM/VMSS.
# az role assignment create --role "Managed Identity Operator" --assignee $AGENTPOOL_IDENTITY_CLIENTID --scope /subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${IDENTITY_RESOURCE_GROUP}
# az role assignment create --role "Managed Identity Operator" --assignee $AGENTPOOL_IDENTITY_CLIENTID --scope /subscriptions/${SUBSCRIPTION_ID}/resourcegroups/${RG_NAME}/providers/microsoft.managedidentity/userassignedidentities/appgwcontridentity-hubvnet-dev001
#/subscriptions/695471ea-1fc3-42ee-a854-eab6c3009516/resourcegroups/rg-aksagic-dev0001/providers/microsoft.managedidentity/userassignedidentities/appgwcontridentity-hubvnet-dev001

############## TEMP CODE BLOCK ######################

# Deploy the CRDs for AAD Pod Managed Identity. This is required for the AGIC pod to interact with the ARM
kubectl apply -f https://raw.githubusercontent.com/Azure/aad-pod-identity/v1.8.6/deploy/infra/deployment-rbac.yaml
# Deploy the required CRDs needed to process AzureIngressProhibitedTarget resource requests
kubectl apply -f https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/ae695ef9bd05c8b708cedf6ff545595d0b7022dc/crds/AzureIngressProhibitedTarget.yaml
# Note: CRDs include the AGIC related resource kinds. 

# Add the AGIC Helm repository
helm repo add application-gateway-kubernetes-ingress https://appgwingress.blob.core.windows.net/ingress-azure-helm-package/
helm repo update

# Read the values needed to update the Helm-Config
applicationGatewayName=$(jq -r ".applicationGatewayName.value" hubdeployment-outputs.json)
resourceGroupName=$(jq -r ".resourceGroupName.value" hubdeployment-outputs.json)
subscriptionId=$(jq -r ".subscriptionId.value" hubdeployment-outputs.json)
identityClientId=$(jq -r ".identityClientId.value" hubdeployment-outputs.json)
identityResourceId=$(jq -r ".identityResourceId.value" hubdeployment-outputs.json)
aksclusterrbacenabled=true
appgwshared=true

# download a helm config template
wget https://raw.githubusercontent.com/Azure/application-gateway-kubernetes-ingress/master/docs/examples/sample-helm-config.yaml -O helm-config.yaml

# Update the required values
sed -i "s|<subscriptionId>|${subscriptionId}|g" helm-config.yaml
sed -i "s|<resourceGroupName>|${resourceGroupName}|g" helm-config.yaml
sed -i "s|<applicationGatewayName>|${applicationGatewayName}|g" helm-config.yaml
sed -i "s|<identityResourceId>|${identityResourceId}|g" helm-config.yaml
sed -i "s|<identityClientId>|${identityClientId}|g" helm-config.yaml
sed -i "s|<enabled>|${aksclusterrbacenabled}|g" helm-config.yaml
sed -i "s|<shared>|${appgwshared}|g" helm-config.yaml

# Create the AzureIngressProhibitedTarget  resource
kubectl apply -f KubernetesManifests/cluster-BUA2-AgicProhibitedTarget.yaml

# Install the Helm package
helm install ingress-azure \
  -f helm-config.yaml \
  application-gateway-kubernetes-ingress/ingress-azure \
  --version 1.5.1

# The helm install creates an AzureIngressProhibitedTarget called "prohibit-all-targets"
# This prohibits the AGIC pod from modifying any of the available namespaces. The above specified default resource needs to be deleted after the creation of a specific target
# Delete the default AzureIngressProhibitedTarget- This is an important step
kubectl delete AzureIngressProhibitedTarget prohibit-all-targets

# Check the prohibited targets
kubectl get AzureIngressProhibitedTargets

# Create the secrets needed for TLS
# Note: This step assumes that the certificate (.crt) and the key (.key) files are present in the execution environment

# Create the base64 encoded string values of the CRT and the Key files
APP_GATEWAY_LISTENER_A02_CERTIFICATE_DATA=$(cat appgwlistenerbu2.crt | base64 | tr -d '\n')
APP_GATEWAY_LISTENER_A02_CERTIFICATE_KEYDATA=$(cat appgwlistenerbu2.key | base64 | tr -d '\n')

# Update the values in the secrets file
# yq -i '.data.tls.cert1.value |= "$APP_GATEWAY_LISTENER_A01_CERTIFICATE_DATA"' KubernetesManifests/cluster-BUA1-ingress-tlssecret.yaml
# yq w KubernetesManifests/cluster-BUA1-ingress-tlssecret.yaml "data.tls.cert.value" "${APP_GATEWAY_LISTENER_A01_CERTIFICATE_DATA}"
# yq w KubernetesManifests/cluster-BUA1-ingress-tlssecret.yaml "data.tls.cert.key" "${APP_GATEWAY_LISTENER_A01_CERTIFICATE_KEYDATA}"

# **Important: The commands attempted (above) dp not seem to work with yq 4.16.x. Manually updating the secret values for now

#Create the TLS secret resource
kubectl apply -f KubernetesManifests/cluster-BUA2-ingress-tlssecret.yaml

# Deploy the test workload
kubectl apply -f KubernetesManifests/cluster-workload-votingapp.yaml
# Deploy the ingress resource for the BUA001.contoso.com host
kubectl apply -f KubernetesManifests/cluster-BUA2-ingress.yaml

# Reference to the helm upgrade command
# helm upgrade \
#     --recreate-pods \
#     -f helm-config.yaml \
#     ingress-azure application-gateway-kubernetes-ingress/ingress-azure \
#     --version 1.5.1