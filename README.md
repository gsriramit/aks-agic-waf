# Application Gateway Ingress Controller with AKS 
This repository contains reference architecture implementation of using Azure Application Gateway as Ingress Controller with AKS Clusters. **Multiple AKS clusters** is one of the multitenant options of hosting and managing workloads of different customers/teams in AKS. The other cost-effective option is to have the workloads deployed to their dedicated namespace within the same cluster. Azure Application Gateway Ingress Controller (AGIC) has ways to load balance traffic to multiple sites for both of the multitenant scenarios stated above. The scenarios and the corresponding configuration of AGIC is shown in the table below. 

## Multitenant Options & AGIC implementation 
|MultiTenant Option  |AGIC Deployment  | Namespace watch | ProhibitedTargets |
|--------------------|-----------------|-----------------|-------------------|
|Same Cluster        |1 Ingress-Controller-Pod per site deployed to a dedicated namespace | List of namespaces that the each of the controllers must watch (mandatory) |NA|
| Multiple Clusters  |1 Ingress-Controller-Pod per cluster | List of namespaces that the controller must watch. If not specified, all namespaces would be watched|List of "AzureIngressProhibitedTarget" resources that the each controller should not update |

## Architecture Diagram
![Aks-Scenarios - MultiTenant-AGIC](https://user-images.githubusercontent.com/13979783/157807791-12061010-5a07-4a40-8633-a406a8f89b8f.png)

## Comparison of the baseline and  current approaches
The [aks-baseline architecture](https://github.com/mspnp/aks-baseline) deploys the application gateway (without AGIC) in the spoke network and the same would be considered as a spoke component. If the architecture were to be extended to multiple spokes, then each of the spoke would be receiving its own app-gw.  
The architecure that we have adopted here is based a common hub and spoke network model used in many of the enterprise's cloud adoption journey. This would be the natural step when multiple teams move their web-based apps to the cloud (AKS cluster(s)) and can share the same application gateway. If teams need their own app-gw for scale-out and higher sku needs, then it would make sense to deploy a dedicated app-gw in the spoke network where the cluster is deployed  
![image](https://user-images.githubusercontent.com/13979783/157811607-a7583083-ddf0-4f8a-b199-19cd8e1e8d21.png)  
src: https://docs.microsoft.com/en-us/azure/cloud-adoption-framework/ready/azure-best-practices/hub-spoke-network-topology#overview


### Note (before deployment)
In an enterprise setup, the hub and spoke components would be deployed to separate subscriptions or separate resource groups within the same subscription. This setup is for quick deployment and test purposes and so the hub and spoke components are deployed to the same resource group.

## Deployment instructions
1. Update of the necessary parameters in the parameters file and the script files
   - Parameters except for the certificate data and password are to be updated in the deployHubNetwork.Parameters.json
     - the ARM template of gateway contains the standard sections of configuring TLS for the hosted sites. These are not actually needed and will be replaced at runtime by AGIC. The same would be applied from the values configured in the Hosts section of Ingress resources
   - Update the SubscriptionId, TenantId and the resourceGroup names in all the deployment scripts (.sh files). Exercise caution not to checkin the files with these sensitive values
   - All the necessary fields (subscriptionId, resourceGroupName, applicationGatewayName, identityResourceId, identityClientId, rbacenabled & shared) need to be updated before the azure-appgw-ingress package can be installed
     - The HelmConfig.yaml once downloaded can be reused for subsequenet repeated executions. However if you delete the entire resource group as a part of the cleanup, the user-assigned identity recreated will have client and resourceIds. These have to be updated in the heml config file, failing to do so, the ingress controller pods would not get to the running state
     - The sed commands to update the rbac.enabled & appgw.shared fields do not work. These fields have to manually updated to true in the helm config file
   - The Listener certificate data and the key data (in base64 encoded string form) need to be updated in the secret manifests. The YQ commands do not work and needs fixing. for now, update these values manually
2. Order of execution of the scripts
   - deployAzureResource.sh
   - deployBUA001-ClusterResources.sh
   - deployBUA002-ClusterResources.sh 
3. Deployment of the kubernetes manifests for each of the clusters needs to be performed from within separate WSL instances (or cloud shell instances). The kube configs of the clusters should be kept separate and it is not advisable to try updating both the clusters from within the same WSL instance
4. Add the subdomain names (bua001.contoso.com & bua002.consoto.com) and the ipv4 public IP address of the application gateway in the hosts file (c:\Windows\System32\Drivers\etc\hosts in windows and etc/hosts in linux) before testing from your local box

## Concepts Used
1. AAD Pod Identity - The AAD pod managed identity is used by the AGIC pods to make REST calls to the ARM to update the Application Gateway according to the config of the Ingress that it is associated with
   - **Note**: 
       - In this implementation, agic pods from both the cluster use the same user-assigned managed identity to request updates to the app-gw. As an user-assigned identity can be associated with multiple resources (agic pods in this case) and both the resources require the same RBAC permission to the same resources (resource-group and app-gw)
       - As mentioned in an earlier note, when the clusters are deployed to different resource groups in the same subscription, using separate MIs per cluster would be the appropriate practise. 
2. Application Gateway & AGIC
   - Hosting of Multiple Sites
   - TLS support for each of the sites (can be completely different domains or sub-domains of the same parent domain)

## Test Instructions
1. Check the state of all the pods (ingress controller, MIC, NMI and the workload). All the pods should be in the running state
   ``` 
   kubectl get pods --all-namespaces 
   ```
2. Check the config of the ingress resources
```
kubectl describe ingress aspnetapp-ingress
kubectl describe ingress votingapp-ingress
```
3. Get the publicIP of the application gateway from the portal and update the same in the hosts files 
![image](https://user-images.githubusercontent.com/13979783/157813624-45d1872b-5543-4116-b11e-cc62aa782ff8.png)
4. Browse to the sites (tolerate the TLS certificate warning and proceed as we have used self-signed certificates and the browser does not recognize the same)
   - https://bua001.contoso.com should take you to the aspnet app page 
   - https://bua002.contoso.com should take you to the voting app page

## WAF Configuration (WIP)
We use the WAF_v2 SKU of the application gateway for this implementation. This provides us the possibility of using WAF to analyze the inbound HTTPS requests using the inbuilt OWASP (3.x) and advanced rule sets.  
A recent update announced my Microsoft brought in the possibility of configuring WAF policies at 3 different levels of the deployment stamp, at the gateway, listener and the uri. When this feature is to be applied to the current deployment, the following mapping would appy  

| Policy Level | Component |
|--------------|-----------|
|App-gw        | app-gw    |
|listener      | applies to site configured and managed by a specific ingress resource |
|uri           | applies to the uri paths (if path-based routing is used) configured in the ingress resource that maps to a listener |

## Possible Enhancements
TBD

## Known Issues
1. The sed commands to update the values in the helm config file do not always work 
2. The YQ commands to update the values in the secrets yaml file does not work

## References
1. General reference of AGIC- https://www.youtube.com/watch?v=sotCKJhQtuk&ab_channel=AzurePowerLunch
2. Blog post on AGIC - https://azure.microsoft.com/en-us/blog/application-gateway-ingress-controller-for-azure-kubernetes-service/
3. AGIC getting started - https://azure.github.io/application-gateway-kubernetes-ingress/tutorials/tutorial.general/
4. Possible implementation options for Multi-Tenant Scenarios
https://docs.microsoft.com/en-us/azure/architecture/example-scenario/aks-agic/aks-agic
5. Documentation of hosting multiple sites in an application gateway
https://docs.microsoft.com/en-us/azure/application-gateway/multiple-site-overview
6. TLS termination at the Application Gateway (TLS certificates configured at the listener level, so we would have 2 TLS certificates, 1 for each subdomain- BUA001 and BUA002)
https://docs.microsoft.com/en-us/azure/application-gateway/tutorial-ssl-cli#create-the-application-gateway
7. Configuring AKS Clusters with managed identity - specific fields required in the ARM templates
https://borzenin.com/aks-with-managed-identity-and-managed-aad-integration/ 
8. Implementing TLS for the hosts interacting with the ingress controller
https://kubernetes.io/docs/concepts/services-networking/ingress/#tls

