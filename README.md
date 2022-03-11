# Application Gateway Ingress Controller with AKS 
This repository contains reference architecture implementation of using Azure Application Gateway as Ingress Controller with AKS Clusters. **Multiple AKS clusters** is one of the multitenant options of hosting and managing workloads of different customers/teams in AKS. The other cost-effective option is to have the workloads deployed to their dedicated namespace within the same cluster. Azure Application Gateway Ingress Controller (AGIC) has ways to load balance traffic to multiple sites for both of the multitenant scenarios stated above. The scenarios and the corresponding configuration of AGIC is shown in the table below. 

## Multitenant Options & AGIC implementation 
|MultiTenant Option  |AGIC Deployment  | Namespace watch | ProhibitedTargets |
|--------------------|-----------------|-----------------|-------------------|
|Same Cluster        |1 Ingress-Controller-Pod per site deployed to a dedicated namespace | List of namespaces that the each of the controllers must watch (mandatory) |NA|
| Multiple Clusters  |1 Ingress-Controller-Pod per cluster | List of namespaces that the controller must watch. If not specified, all namespaces would be watched|List of "AzureIngressProhibitedTarget" resources that the each controller should not update |

## Architecture Diagram
![Aks-Scenarios - MultiTenant-AGIC](https://user-images.githubusercontent.com/13979783/157807791-12061010-5a07-4a40-8633-a406a8f89b8f.png)

## Deployment instructions
1. Update of the necessary parameters in the parameters file and the script files
   - Parameters except for the certificate data and password are to be updated in the deployHubNetwork.Parameters.json
   - Update the SubscriptionId, TenantId and the resourceGroup names in all the deployment scripts (.sh files). Exercise caution not to checkin the files with these sensitive values
   - All the necessary fields (subscriptionId, resourceGroupName, applicationGatewayName, identityResourceId, identityClientId, rbacenabled & shared) need to be updated before the azure-appgw-ingress package can be installed
     - The HelmConfig.yaml once downloaded can be reused for subsequenet repeated executions. However if you delete the entire resource group as a part of the cleanup, the user-assigned identity recreated will have client and resourceIds. These have to be updated in the heml config file, failing to do so, the ingress controller pods would not get to the running state
     - The sed commands to update the rbac.enabled & appgw.shared fields do not work. These fields have to manually updated to true in the helm config file
   - The Listener certificate data and the key data (in base64 encoded string form) need to be updated in the secret manifests. The YQ commands do not work and needs fixing. for now, update these values manually
2. Order of execution of the scripts
   - deployAzureResource.sh
   - deployBUA001-ClusterResources.sh
   - deployBUA002-ClusterResources.sh 
3. Note: In an enterprise setup the hub and spoke components would be deployed to separate subscriptions or separate resource groups within the same subscription. This setup is for quick deployment and test purposes.
4. additional comments on the steps that update the helmconfig.yaml file
   - Manual update of shared and RBACEnabled fields in the helm config
5. mention the need to add the subdomain names and the corresponding ipv4 public IP addresses in the hosts file for quick testing
6. **Note**: Deployment as per the architecture diagram would need separate resource groups for each of the spokes and the hub (this can be separate subscriptions in an enterprise setup). WE have deployed all the resources in the same RG for the sake of simplicity 


