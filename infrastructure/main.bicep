// Main Bicep template for Expense Management System
// Deploys: Managed Identity, App Service, Azure SQL Database
// Optionally: Azure OpenAI and AI Search (when deployGenAI=true)

@description('Location for all resources (default: UK South)')
param location string = 'uksouth'

@description('Admin Object ID for SQL Server Entra ID authentication')
param adminObjectId string

@description('Admin Login (UPN) for SQL Server Entra ID authentication')
param adminLogin string

@description('Whether to deploy GenAI resources (Azure OpenAI, AI Search)')
param deployGenAI bool = false

// Generate unique suffix for resource names
var uniqueSuffix = uniqueString(resourceGroup().id)

// Resource names (all lowercase)
var managedIdentityName = 'mid-expensemgmt-${uniqueSuffix}'
var appServicePlanName = 'asp-expensemgmt-${uniqueSuffix}'
var appServiceName = 'app-expensemgmt-${uniqueSuffix}'
var sqlServerName = 'sql-expensemgmt-${uniqueSuffix}'
var sqlDatabaseName = 'ExpenseDB'

// Deploy Managed Identity
module managedIdentity 'managed-identity.bicep' = {
  name: 'managedIdentity-deployment'
  params: {
    location: location
    managedIdentityName: managedIdentityName
  }
}

// Deploy App Service
module appService 'app-service.bicep' = {
  name: 'appService-deployment'
  params: {
    location: location
    appServicePlanName: appServicePlanName
    appServiceName: appServiceName
    managedIdentityId: managedIdentity.outputs.managedIdentityId
  }
}

// Deploy Azure SQL Database
module azureSQL 'azure-sql.bicep' = {
  name: 'azureSQL-deployment'
  params: {
    location: location
    sqlServerName: sqlServerName
    sqlDatabaseName: sqlDatabaseName
    adminObjectId: adminObjectId
    adminLogin: adminLogin
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
    managedIdentityName: managedIdentityName
  }
}

// Deploy GenAI resources (conditional)
module genai 'genai.bicep' = if (deployGenAI) {
  name: 'genai-deployment'
  params: {
    location: location
    uniqueSuffix: uniqueSuffix
    managedIdentityPrincipalId: managedIdentity.outputs.managedIdentityPrincipalId
  }
}

// Outputs
output managedIdentityClientId string = managedIdentity.outputs.managedIdentityClientId
output managedIdentityPrincipalId string = managedIdentity.outputs.managedIdentityPrincipalId
output appServiceName string = appService.outputs.appServiceName
output appServiceUrl string = appService.outputs.appServiceUrl
output sqlServerFqdn string = azureSQL.outputs.sqlServerFqdn
output sqlDatabaseName string = azureSQL.outputs.sqlDatabaseName

// Conditional outputs for GenAI (with null-safe operators)
output openAIEndpoint string = deployGenAI ? genai.outputs.openAIEndpoint : ''
output openAIModelName string = deployGenAI ? genai.outputs.openAIModelName : ''
output searchEndpoint string = deployGenAI ? genai.outputs.searchEndpoint : ''
output openAIName string = deployGenAI ? genai.outputs.openAIName : ''
