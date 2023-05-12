targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name which is used to generate a short unique hash for each resource')
param name string

@minLength(1)
@description('Primary location for all resources')
param location string

param webAppExists bool = false

var resourceToken = toLower(uniqueString(subscription().id, name, location))
var tags = { 'azd-env-name': name }

resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: '${name}-rg'
  location: location
  tags: tags
}

var prefix = '${name}-${resourceToken}'

// Container apps host (including container registry)
module containerApps 'core/host/container-apps.bicep' = {
  name: 'container-apps'
  scope: resourceGroup
  params: {
    name: 'app'
    location: location
    tags: tags
    containerAppsEnvironmentName: '${prefix}-containerapps-env'
    containerRegistryName: '${replace(prefix, '-', '')}registry'
    logAnalyticsWorkspaceName: logAnalyticsWorkspace.outputs.name
  }
}

module cdn 'core/networking/cdn.bicep' = {
  name: 'cdn'
  scope: resourceGroup
  params: {
    location: location
    tags: tags
    cdnEndpointName: '${prefix}-cdn-endpoint'
    cdnProfileName: '${prefix}-cdn-profile'
    originUrl: last(split(web.outputs.appUri, '//'))
    deliveryPolicyRules: [
      {
        name: 'Global'
        order: 0
        actions: [
          {
            name: 'CacheExpiration'
            parameters: {
                cacheBehavior: 'SetIfMissing'
                cacheType: 'All'
                cacheDuration: '00:05:00'
                typeName: 'DeliveryRuleCacheExpirationActionParameters'
            }
          }
        ]
      }
      {
        name: 'images'
        order: 1
        conditions: [
          {
            name: 'UrlPath'
            parameters: {
                operator: 'BeginsWith'
                negateCondition: false
                matchValues: [
                  'static/images/'
                ]
                transforms: ['Lowercase']
                typeName: 'DeliveryRuleUrlPathMatchConditionParameters'
            }
          }
        ]
        actions: [
          {
            name: 'CacheExpiration'
            parameters: {
                cacheBehavior: 'Override'
                cacheType: 'All'
                cacheDuration: '7.00:00:00'
                typeName: 'DeliveryRuleCacheExpirationActionParameters'
            }
          }
        ]
      }
    ]
  }
}

// Web frontend
module web 'web.bicep' = {
  name: 'web'
  scope: resourceGroup
  params: {
    name: replace('${take(prefix,19)}-ca', '--', '-')
    location: location
    tags: tags
    identityName: '${prefix}-id-web'
    containerAppsEnvironmentName: containerApps.outputs.environmentName
    containerRegistryName: containerApps.outputs.registryName
    exists: webAppExists
  }
}


module logAnalyticsWorkspace 'core/monitor/loganalytics.bicep' = {
  name: 'loganalytics'
  scope: resourceGroup
  params: {
    name: '${prefix}-loganalytics'
    location: location
    tags: tags
  }
}


output AZURE_LOCATION string = location
output AZURE_CONTAINER_ENVIRONMENT_NAME string = containerApps.outputs.environmentName
output AZURE_CONTAINER_REGISTRY_NAME string = containerApps.outputs.registryName
output AZURE_CONTAINER_REGISTRY_ENDPOINT string = containerApps.outputs.registryLoginServer
output SERVICE_WEB_IDENTITY_PRINCIPAL_ID string = web.outputs.SERVICE_WEB_IDENTITY_PRINCIPAL_ID
output SERVICE_WEB_NAME string = web.outputs.SERVICE_WEB_NAME
output SERVICE_WEB_ENDPOINTS array = [cdn.outputs.uri]
output SERVICE_WEB_IMAGE_NAME string = web.outputs.SERVICE_WEB_IMAGE_NAME
