#!/bin/bash
set -e

# Expense Management System - Main Deployment Script
# Deploys infrastructure and application without GenAI services

echo "=================================================="
echo "Expense Management System - Deployment Script"
echo "=================================================="
echo ""

# Check if Azure CLI is installed
if ! command -v az &> /dev/null; then
    echo "❌ Azure CLI is not installed. Please install it first."
    exit 1
fi

# Check if user is logged in
if ! az account show &> /dev/null; then
    echo "❌ Not logged into Azure. Please run 'az login' first."
    exit 1
fi

# Get current user information for SQL Server admin
CURRENT_USER_OBJECT_ID=$(az ad signed-in-user show --query id -o tsv)
CURRENT_USER_UPN=$(az ad signed-in-user show --query userPrincipalName -o tsv)

echo "✓ Logged in as: $CURRENT_USER_UPN"
echo "✓ Object ID: $CURRENT_USER_OBJECT_ID"
echo ""

# Set deployment variables
RESOURCE_GROUP="rg-expensemgmt-demo"
LOCATION="uksouth"
DEPLOYMENT_NAME="expense-deployment-$(date +%s)"

echo "Configuration:"
echo "  Resource Group: $RESOURCE_GROUP"
echo "  Location: $LOCATION"
echo ""

# Create resource group
echo "📦 Creating resource group..."
az group create \
    --name $RESOURCE_GROUP \
    --location $LOCATION \
    --output none

echo "✓ Resource group created"
echo ""

# Deploy Bicep infrastructure (without GenAI)
echo "🚀 Deploying infrastructure (App Service, SQL Database, Managed Identity)..."
DEPLOYMENT_OUTPUT=$(az deployment group create \
    --resource-group $RESOURCE_GROUP \
    --template-file infrastructure/main.bicep \
    --parameters adminObjectId=$CURRENT_USER_OBJECT_ID \
    --parameters adminLogin=$CURRENT_USER_UPN \
    --parameters deployGenAI=false \
    --query "properties.outputs" \
    --output json)

echo "✓ Infrastructure deployed"
echo ""

# Extract outputs
SQL_SERVER_FQDN=$(echo $DEPLOYMENT_OUTPUT | jq -r '.sqlServerFqdn.value')
SQL_DATABASE_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.sqlDatabaseName.value')
APP_SERVICE_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.appServiceName.value')
APP_SERVICE_URL=$(echo $DEPLOYMENT_OUTPUT | jq -r '.appServiceUrl.value')
MANAGED_IDENTITY_CLIENT_ID=$(echo $DEPLOYMENT_OUTPUT | jq -r '.managedIdentityClientId.value')

echo "Deployment outputs:"
echo "  SQL Server: $SQL_SERVER_FQDN"
echo "  Database: $SQL_DATABASE_NAME"
echo "  App Service: $APP_SERVICE_NAME"
echo "  App URL: $APP_SERVICE_URL"
echo "  Managed Identity Client ID: $MANAGED_IDENTITY_CLIENT_ID"
echo ""

# Wait for SQL Server to be fully ready
echo "⏳ Waiting 30 seconds for SQL Server to be fully ready..."
sleep 30

# Configure SQL Server firewall
echo "🔥 Configuring SQL Server firewall..."
MY_IP=$(curl -s https://api.ipify.org)
SQL_SERVER_NAME=$(echo $SQL_SERVER_FQDN | cut -d'.' -f1)

# Allow Azure services access
az sql server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    --name "AllowAllAzureIPs" \
    --start-ip-address 0.0.0.0 \
    --end-ip-address 0.0.0.0 \
    --output none

# Add deployment IP
az sql server firewall-rule create \
    --resource-group $RESOURCE_GROUP \
    --server $SQL_SERVER_NAME \
    --name "AllowDeploymentIP" \
    --start-ip-address $MY_IP \
    --end-ip-address $MY_IP \
    --output none

echo "✓ Firewall configured"
echo ""

echo "⏳ Waiting 15 seconds for firewall rules to propagate..."
sleep 15

# Install Python dependencies
echo "📦 Installing Python dependencies..."
pip3 install --quiet pyodbc azure-identity

# Update Python scripts with actual server names
echo "📝 Updating Python scripts with deployment values..."
sed -i.bak "s/PLACEHOLDER_SQL_SERVER/$SQL_SERVER_FQDN/g" run-sql.py && rm -f run-sql.py.bak
sed -i.bak "s/PLACEHOLDER_SQL_SERVER/$SQL_SERVER_FQDN/g" run-sql-dbrole.py && rm -f run-sql-dbrole.py.bak
sed -i.bak "s/PLACEHOLDER_SQL_SERVER/$SQL_SERVER_FQDN/g" run-sql-stored-procs.py && rm -f run-sql-stored-procs.py.bak

# Get managed identity name for script.sql
MANAGED_IDENTITY_NAME=$(echo $DEPLOYMENT_OUTPUT | jq -r '.managedIdentityPrincipalId.value')
# Actually we need the name, let me extract it differently
MANAGED_IDENTITY_NAME="mid-expensemgmt-$(echo $RESOURCE_GROUP | md5sum | cut -c1-13)"
# Better: get from Azure
MANAGED_IDENTITY_NAME=$(az identity list --resource-group $RESOURCE_GROUP --query "[0].name" -o tsv)

sed -i.bak "s/MANAGED-IDENTITY-NAME/$MANAGED_IDENTITY_NAME/g" script.sql && rm -f script.sql.bak

echo "✓ Python scripts updated"
echo ""

# Deploy database schema
echo "💾 Deploying database schema..."
python3 run-sql.py
echo "✓ Database schema deployed"
echo ""

# Configure database roles for managed identity
echo "🔐 Configuring database roles for managed identity..."
python3 run-sql-dbrole.py
echo "✓ Database roles configured"
echo ""

# Deploy stored procedures
echo "📊 Deploying stored procedures..."
python3 run-sql-stored-procs.py
echo "✓ Stored procedures deployed"
echo ""

# Build and publish the application
echo "🔨 Building application..."
cd src/ExpenseManagement
dotnet publish -c Release -o ../../publish
cd ../..
echo "✓ Application built"
echo ""

# Create deployment package
echo "📦 Creating deployment package..."
cd publish
zip -r ../app.zip . > /dev/null
cd ..
echo "✓ Deployment package created"
echo ""

# Configure App Service settings
echo "⚙️ Configuring App Service settings..."

# Build connection string
CONNECTION_STRING="Server=tcp:${SQL_SERVER_FQDN},1433;Database=${SQL_DATABASE_NAME};Authentication=Active Directory Managed Identity;User Id=${MANAGED_IDENTITY_CLIENT_ID};Encrypt=True;TrustServerCertificate=False;Connection Timeout=30;"

az webapp config appsettings set \
    --name $APP_SERVICE_NAME \
    --resource-group $RESOURCE_GROUP \
    --settings \
        "ConnectionStrings__DefaultConnection=$CONNECTION_STRING" \
        "ManagedIdentityClientId=$MANAGED_IDENTITY_CLIENT_ID" \
        "AZURE_CLIENT_ID=$MANAGED_IDENTITY_CLIENT_ID" \
    --output none

echo "✓ App Service settings configured"
echo ""

# Deploy application to App Service
echo "🚀 Deploying application to App Service..."
az webapp deploy \
    --resource-group $RESOURCE_GROUP \
    --name $APP_SERVICE_NAME \
    --src-path app.zip \
    --type zip \
    --output none

echo "✓ Application deployed"
echo ""

# Wait for app to start
echo "⏳ Waiting for application to start..."
sleep 20

echo ""
echo "=================================================="
echo "✅ Deployment completed successfully!"
echo "=================================================="
echo ""
echo "📱 Application URL: ${APP_SERVICE_URL}/Index"
echo "📄 API Documentation: ${APP_SERVICE_URL}/swagger"
echo "💬 Chat UI: ${APP_SERVICE_URL}/Chat"
echo ""
echo "⚠️  Note: The chat UI will show dummy responses until you deploy GenAI services."
echo "   To enable full AI chat functionality, run: ./deploy-with-chat.sh"
echo ""
echo "📝 To run locally:"
echo "   1. Update appsettings.json connection string to use:"
echo "      Authentication=Active Directory Default"
echo "   2. Run: az login"
echo "   3. Run: dotnet run --project src/ExpenseManagement"
echo ""
