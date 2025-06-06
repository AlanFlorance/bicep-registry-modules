targetScope = 'subscription'

metadata name = 'Using large parameter set'
metadata description = 'This instance deploys the module with most of its features enabled.'

// ========== //
// Parameters //
// ========== //

@description('Optional. The name of the resource group to deploy for testing purposes.')
@maxLength(90)
param resourceGroupName string = 'dep-${namePrefix}-insights.scheduledqueryrules-${serviceShort}-rg'

@description('Optional. A short identifier for the kind of deployment. Should be kept short to not run into resource-name length-constraints.')
param serviceShort string = 'isqrmax'

@description('Optional. A token to inject into the name of each resource.')
param namePrefix string = '#_namePrefix_#'

// enforcing location due to action groups not being available in most regions
#disable-next-line no-hardcoded-location
var enforcedLocation = 'germanywestcentral'

// ============ //
// Dependencies //
// ============ //

// General resources
// =================
resource resourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: resourceGroupName
  location: enforcedLocation
}

module nestedDependencies 'dependencies.bicep' = {
  scope: resourceGroup
  name: '${uniqueString(deployment().name, enforcedLocation)}-nestedDependencies'
  params: {
    managedIdentityName: 'dep-${namePrefix}-msi-${serviceShort}'
    logAnalyticsWorkspaceName: 'dep-${namePrefix}-law-${serviceShort}1'
    actionGroupName: 'dep-${namePrefix}-ag-${serviceShort}'
    location: enforcedLocation
  }
}

// ============== //
// Test Execution //
// ============== //

@batchSize(1)
module testDeployment '../../../main.bicep' = [
  for iteration in ['init', 'idem']: {
    scope: resourceGroup
    name: '${uniqueString(deployment().name, enforcedLocation)}-test-${serviceShort}-${iteration}'
    params: {
      name: '${namePrefix}${serviceShort}001'
      location: enforcedLocation
      alertDescription: 'My sample Alert'
      autoMitigate: false
      actions: {
        actionGroupResourceIds: [
          nestedDependencies.outputs.actionGroupResourceId
        ]
        customProperties: {
          'Additional Details': 'Evaluation windowStartTime: \${data.alertContext.condition.windowStartTime}. windowEndTime: \${data.alertContext.condition.windowEndTime}'
          'Alert \${data.essentials.monitorCondition} reason': '\${data.alertContext.condition.allOf[0].metricName} \${data.alertContext.condition.allOf[0].operator} \${data.alertContext.condition.allOf[0].threshold} \${data.essentials.monitorCondition}. The value is \${data.alertContext.condition.allOf[0].metricValue}'
        }
      }
      managedIdentities: {
        systemAssigned: false // Only either system-assigned or user-assigned can be configured
        userAssignedResourceIds: [
          nestedDependencies.outputs.managedIdentityResourceId
        ]
      }
      criterias: {
        allOf: [
          {
            dimensions: [
              {
                name: 'Computer'
                operator: 'Include'
                values: [
                  '*'
                ]
              }
              {
                name: 'InstanceName'
                operator: 'Include'
                values: [
                  '*'
                ]
              }
            ]
            metricMeasureColumn: 'AggregatedValue'
            operator: 'GreaterThan'
            query: 'Perf | where ObjectName == "LogicalDisk" | where CounterName == "% Free Space" | where InstanceName <> "HarddiskVolume1" and InstanceName <> "_Total" | summarize AggregatedValue = min(CounterValue) by Computer, InstanceName, bin(TimeGenerated,5m)'
            threshold: 0
            timeAggregation: 'Average'
          }
        ]
      }
      evaluationFrequency: 'PT5M'
      queryTimeRange: 'PT5M'
      lock: {
        kind: 'CanNotDelete'
        name: 'myCustomLockName'
      }
      roleAssignments: [
        {
          name: 'fa8868c7-33d3-4cd5-86a5-cbf76261035b'
          roleDefinitionIdOrName: 'Owner'
          principalId: nestedDependencies.outputs.managedIdentityPrincipalId
          principalType: 'ServicePrincipal'
        }
        {
          name: guid('Custom seed ${namePrefix}${serviceShort}')
          roleDefinitionIdOrName: 'b24988ac-6180-42a0-ab88-20f7382dd24c'
          principalId: nestedDependencies.outputs.managedIdentityPrincipalId
          principalType: 'ServicePrincipal'
        }
        {
          roleDefinitionIdOrName: subscriptionResourceId(
            'Microsoft.Authorization/roleDefinitions',
            'acdd72a7-3385-48ef-bd42-f606fba81ae7'
          )
          principalId: nestedDependencies.outputs.managedIdentityPrincipalId
          principalType: 'ServicePrincipal'
        }
      ]
      alertDisplayName: '${uniqueString(deployment().name, enforcedLocation)}-displayNameTest-${serviceShort}-${iteration}'
      ruleResolveConfiguration: {
        autoResolved: true
        timeToResolve: 'PT5M'
      }
      scopes: [
        nestedDependencies.outputs.logAnalyticsWorkspaceResourceId
      ]
      suppressForMinutes: 'PT5M'
      windowSize: 'PT5M'
      tags: {
        'hidden-title': 'This is visible in the resource name'
        Environment: 'Non-Prod'
        Role: 'DeploymentValidation'
      }
    }
  }
]
