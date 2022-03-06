#!/bin/bash

#install JQ to be able to edit the ARM params values from script
apt install jq

# Declare the variables
RG_LOCATION='eastus2'
RG_NAME='rg-aksagic-dev0001'
SUBSCRIPTION_ID=""
TENANT_ID=""
DOMAIN_NAME="contoso.com"
SUBDOMAIN_BUA1="BUA001"
SUBDOMAIN_BUA2="BUA002"
TLS_CERTPASSWORD="appgwtlssecret#12"
HUB_DEPLOYMENT_NAME="deployHubNetwork"
SPOKEA_DEPLOYMENT_NAME="spoke1_deployment"
SPOKEB_DEPLOYMENT_NAME="spoke2_deployment"

# Login to the account and set the target subscription
az login
az account set -s "${SUBSCRIPTION_ID}"

# install the needed features
az provider register --namespace Microsoft.OperationsManagement
az provider register --namespace Microsoft.OperationalInsights
az feature register --name EnablePodIdentityPreview --namespace Microsoft.ContainerService


# Create the resource group. In an enterprise setup, the resources would be split differently. The resources in the hub & the spokes need to be provisioned in their own resource groups
az group create -n $RG_NAME -l $RG_LOCATION

# Generate the Self-Signed TLS certificates that will be used by the Application Gateway to perform TLS termination
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out appgwlistenerbu1.crt -keyout appgwlistenerbu1.key -subj "/CN=${SUBDOMAIN_BUA1}.${DOMAIN_NAME}/O=Contoso BusinessUnit A001" -addext "subjectAltName = DNS:${SUBDOMAIN_BUA1}.${DOMAIN_NAME}" -addext "keyUsage = digitalSignature" -addext "extendedKeyUsage = serverAuth"
openssl pkcs12 -export -out appgwlistenerbu1.pfx -in appgwlistenerbu1.crt -inkey appgwlistenerbu1.key -passout pass:${TLS_CERTPASSWORD}
export APP_GATEWAY_LISTENER_A01_CERTIFICATE_DATA=$(cat appgwlistenerbu1.pfx | base64 | tr -d '\n')

# Repeat the steps for the other subdomain i.e app-gw listener. The TLS cert can also be configured at the gateway level with a wild-card certificate e.g. *.contoso.com
openssl req -x509 -nodes -days 365 -newkey rsa:2048 -out appgwlistenerbu2.crt -keyout appgwlistenerbu2.key -subj "/CN=${SUBDOMAIN_BUA2}.${DOMAIN_NAME}/O=Contoso BusinessUnit A002" -addext "subjectAltName = DNS:${SUBDOMAIN_BUA2}.${DOMAIN_NAME}" -addext "keyUsage = digitalSignature" -addext "extendedKeyUsage = serverAuth"
openssl pkcs12 -export -out appgwlistenerbu2.pfx -in appgwlistenerbu2.crt -inkey appgwlistenerbu2.key -passout pass:${TLS_CERTPASSWORD}
export APP_GATEWAY_LISTENER_A02_CERTIFICATE_DATA=$(cat appgwlistenerbu2.pfx | base64 | tr -d '\n')

# Update the TLS certificate values before running the deployment
cd AzureDeploymentManifests
echo $(cat deployHubNetwork.Parameters.json | jq --arg app_gw_cert "$APP_GATEWAY_LISTENER_A01_CERTIFICATE_DATA" '.parameters.BUA01SiteCertData.value|=$app_gw_cert') > deployHubNetwork.Parameters.json
echo $(cat deployHubNetwork.Parameters.json | jq --arg app_gw_cert_pwd "$TLS_CERTPASSWORD" '.parameters.BUA01SiteCertPassword.value|=$app_gw_cert_pwd') > deployHubNetwork.Parameters.json
echo $(cat deployHubNetwork.Parameters.json | jq --arg app_gw_cert "$APP_GATEWAY_LISTENER_A02_CERTIFICATE_DATA" '.parameters.BUA02SiteCertData.value|=$app_gw_cert') > deployHubNetwork.Parameters.json
echo $(cat deployHubNetwork.Parameters.json | jq --arg app_gw_cert_pwd "$TLS_CERTPASSWORD" '.parameters.BUA02SiteCertPassword.value|=$app_gw_cert_pwd') > deployHubNetwork.Parameters.json

# Navigate back to root dir to execute the deployment of azure resources
cd ..

# This deployment shd create the hub virtual network and the application gateway 
az deployment group create -g $RG_NAME -n $HUB_DEPLOYMENT_NAME -f AzureDeploymentManifests/deployHubNetwork.json -p AzureDeploymentManifests/deployHubNetwork.parameters.json
# Deploy the Spoke-A components, Spoke Vnet, peering with the hub, an AKS cluster and the associated services
az deployment group create -g $RG_NAME -n $SPOKEA_DEPLOYMENT_NAME -f AzureDeploymentManifests/deploySpokeNetwork-BUA1.json
# query the required outputs from each of the deployments
# az deployment group create -g $RG_NAME -n $SPOKEB_DEPLOYMENT_NAME_DEPLOYMENT_NAME -f AzureDeploymentManifests/deploySpokeNetwork-BUA2.json

# query the required outputs from each of the deployments
az group deployment show -g $RG_NAME -n $HUB_DEPLOYMENT_NAME --query "properties.outputs" -o json > hubdeployment-outputs.json
az group deployment show -g $RG_NAME -n $SPOKEA_DEPLOYMENT_NAME --query "properties.outputs" -o json > spoke1deployment-outputs.json
# az group deployment show -g $RG_NAME -n $SPOKEB_DEPLOYMENT_NAME --query "properties.outputs" -o json > spoke2deployment-outputs.json

