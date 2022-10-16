param location string
param prefix string
param vnetSettings object = {
  addressPrefixes: [
    '10.0.0.0/19'
  ]
  subnets: [
    { 
      name: 'subnet1'
      addressPrefix: '10.0.0.0/21'
    }
    { 
      name: 'acaAppSubnet'
      addressPrefix: '10.0.8.0/21'
    }
    { 
      name: 'acaControlPlaneSubnet'
      addressPrefix: '10.0.16.0/21'
    }
  ]
}

resource networkSecurityGroup 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: '${prefix}-default-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'allowhttpsinbound'
        properties:{
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          description: 'Allow https traffic into API'
          sourceAddressPrefix: '*'
          sourcePortRange: '*'
          destinationPortRange: '443'
          destinationAddressPrefix: '*'
          priority: 200
        }
      }
    ]
  }
}


resource virtualNetwork 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: '${prefix}-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: vnetSettings.addressPrefixes
    }
    subnets: [  for subnet in vnetSettings.subnets: {
      name: subnet.name
      properties: {
        addressPrefix: subnet.addressPrefix
        networkSecurityGroup: {
          id: networkSecurityGroup.id
        }
        privateEndpointNetworkPolicies: 'disabled'
      }
    }]
  }
}

resource cosmosDbAccount 'Microsoft.DocumentDB/databaseAccounts@2021-03-15' = {
  name: '${prefix}-cosmos-account'
  location: location
  kind: 'GlobalDocumentDB'
  properties: {
    consistencyPolicy: {
      defaultConsistencyLevel: 'Session'
    }
    locations: [
      {
        locationName: location
        failoverPriority: 0
      }
    ]
    databaseAccountOfferType: 'Standard'
    enableAutomaticFailover: false
    capabilities: [
      {
        name: 'EnableServerless'
      }
    ]
    publicNetworkAccess: 'Disabled'
  }
}

resource sqlDb 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases@2021-06-15' = {
  name: '${prefix}-sqldb'
  parent: cosmosDbAccount
  properties: {
    resource: {
      id: '${prefix}-sqldb'
    }
  }
}

resource sqlContainerName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-06-15' = {
  parent: sqlDb 
  name: '${prefix}-orders'
  properties: {
    resource: {
      id: '${prefix}-orders'
      partitionKey: {
        paths: [
          '/id'
        ]
      }
    }

  }
}

resource stateContainerName 'Microsoft.DocumentDB/databaseAccounts/sqlDatabases/containers@2021-06-15' = {
  parent: sqlDb 
  name: '${prefix}-state'
  properties: {
    resource: {
      id: '${prefix}-state'
      partitionKey: {
        paths: [
          '/partitionKey'
        ]
      }
    }
    
  }
}

module cosmosPrivateLink 'br:bicepreg.azurecr.io/bicep/modules/privateendpoint:v1' ={
  name: 'cosmosPrivateLink'
  params:{
    location:location
    name: '${prefix}-cosmos'
    virtualNetworkId: virtualNetwork.id
    subnetName: virtualNetwork.properties.subnets[0].name
    zoneName: 'privatelink.documents.azure.com'
    subResourceTypes:[
       'SQL'
    ]
    resourceId: cosmosDbAccount.id
  }
}

resource keyVault 'Microsoft.KeyVault/vaults@2021-10-01' = {
  name: '${prefix}-kv'
  location: location
  properties: {
    enabledForDeployment: true
    enabledForTemplateDeployment: true
    enabledForDiskEncryption: true
    enableRbacAuthorization: true
    tenantId: tenant().tenantId
    sku: {
      name: 'standard'
      family: 'A'
    }
  }
}

module keyVaultPrivateLink 'br:bicepreg.azurecr.io/bicep/modules/privateendpoint:v1' ={
  name: 'keyVaultPrivateLink'
  params:{
    location:location
    name: '${prefix}-keyvault'
    virtualNetworkId: virtualNetwork.id
    subnetName: virtualNetwork.properties.subnets[0].name
    zoneName: 'privatelink.vaultcore.azure.net'
    subResourceTypes:[
       'vault'
    ]
    resourceId: keyVault.id
  }
}

output vNetId string = virtualNetwork.id
output vNetName string = virtualNetwork.name
output SecretKeyVaultName string = keyVault.name
output CosmosAccountName string = cosmosDbAccount.name
output ComosDbName string = sqlDb.name
output CosmosStateContainerName string = stateContainerName.name
output CosmosSqlContainerName string = sqlContainerName.name
