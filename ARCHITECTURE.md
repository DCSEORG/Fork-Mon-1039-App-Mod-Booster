# Expense Management System - Architecture Documentation

## System Architecture Diagram

```
┌──────────────────────────────────────────────────────────────────────────────┐
│                          AZURE RESOURCE GROUP                                 │
│                          (rg-expensemgmt-demo)                               │
│                                                                               │
│                                                                               │
│   ┌────────────────────────────────────────────────────────────────────┐    │
│   │                    USER-ASSIGNED MANAGED IDENTITY                   │    │
│   │                    (mid-expensemgmt-xxxxxxx)                       │    │
│   │                                                                     │    │
│   │  Client ID: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx                  │    │
│   │  Used by: App Service, connects to SQL, OpenAI, Search            │    │
│   └────────────────────┬────────────────────────────────────┬──────────┘    │
│                        │                                    │                │
│                        │                                    │                │
│   ┌────────────────────▼─────────────┐   ┌────────────────▼──────────┐     │
│   │     APP SERVICE (LINUX)          │   │   AZURE SQL DATABASE       │     │
│   │  app-expensemgmt-xxxxxxx         │   │  sql-expensemgmt-xxxxxxx   │     │
│   │                                  │   │                             │     │
│   │  ┌────────────────────────────┐ │   │  Database: ExpenseDB        │     │
│   │  │  ASP.NET Core 8 App        │ │   │  Tier: Basic (Dev/Test)     │     │
│   │  │                            │ │   │                             │     │
│   │  │  Components:               │ │   │  Authentication:            │     │
│   │  │  - Razor Pages (UI)        │◄┼───┤  - Entra ID Only            │     │
│   │  │  - REST API Controllers    │ │   │  - Managed Identity         │     │
│   │  │  - Swagger/OpenAPI         │ │   │  - No SQL Auth              │     │
│   │  │  - Chat Service            │ │   │                             │     │
│   │  │  - Expense Service         │ │   │  Tables:                    │     │
│   │  │                            │ │   │  - Roles                    │     │
│   │  └────────────────────────────┘ │   │  - Users                    │     │
│   │                                  │   │  - ExpenseCategories        │     │
│   │  SKU: S1 Standard                │   │  - ExpenseStatus            │     │
│   │  Runtime: .NET 8 on Linux        │   │  - Expenses                 │     │
│   │  HTTPS: Required                 │   │                             │     │
│   │  TLS: 1.2 minimum                │   │  + 20+ Stored Procedures    │     │
│   └──────────────┬───────────────────┘   └─────────────────────────────┘     │
│                  │                                                            │
│                  │ (When deployGenAI=true)                                   │
│                  │                                                            │
│   ┌──────────────▼───────────────┐       ┌──────────────────────────┐       │
│   │   AZURE OPENAI SERVICE       │       │   AI SEARCH SERVICE      │       │
│   │  aoai-expensemgmt-xxxxxxx    │       │  srch-expensemgmt-xxx    │       │
│   │                              │       │                          │       │
│   │  Location: swedencentral     │       │  Location: uksouth       │       │
│   │  SKU: S0 Standard            │       │  SKU: Basic              │       │
│   │                              │       │                          │       │
│   │  Deployment:                 │       │  Index: expense-docs     │       │
│   │  - Model: gpt-4o             │       │  (For RAG pattern)       │       │
│   │  - Version: 2024-08-06       │       │                          │       │
│   │  - Capacity: 8 units         │       │  Replication: 1          │       │
│   │                              │       │  Partitions: 1           │       │
│   │  Auth: Managed Identity      │       │  Auth: Managed Identity  │       │
│   │  Role: Cognitive Services    │       │  Role: Search Index Data │       │
│   │        OpenAI User           │       │        Contributor       │       │
│   └──────────────────────────────┘       └──────────────────────────┘       │
│                                                                               │
└──────────────────────────────────────────────────────────────────────────────┘

                                    │
                                    │ HTTPS
                                    ▼
                    ┌───────────────────────────────┐
                    │         END USERS             │
                    │                               │
                    │  - Employees (Submit)         │
                    │  - Managers (Approve/Reject)  │
                    │  - Chat with AI Assistant     │
                    └───────────────────────────────┘
```

## Component Details

### 1. User-Assigned Managed Identity
**Purpose**: Passwordless authentication for all Azure service connections

**Configuration**:
- Created first during deployment
- Assigned to App Service
- Granted roles:
  - SQL Database: db_datareader, db_datawriter, EXECUTE
  - Azure OpenAI: Cognitive Services OpenAI User
  - AI Search: Search Index Data Contributor

**Environment Variables**:
- `AZURE_CLIENT_ID`: Set in App Service configuration
- `ManagedIdentityClientId`: Same value for explicit SDK usage

### 2. App Service (Linux)
**Purpose**: Host the ASP.NET Core 8 web application

**Configuration**:
- Plan: Standard S1 (avoid cold starts)
- OS: Linux
- Runtime: .NET 8
- Always On: Enabled
- HTTPS Only: True
- TLS Version: 1.2+

**Application Structure**:
```
Controllers/
  ├── ExpensesController.cs    # CRUD + workflow operations
  ├── CategoriesController.cs  # Category lookup
  ├── UsersController.cs       # User information
  └── ChatController.cs        # AI chat endpoint

Services/
  ├── ExpenseService.cs        # Database operations (stored procs)
  └── ChatService.cs           # Azure OpenAI integration + function calling

Pages/
  ├── Index.cshtml             # Main expense UI
  └── Chat.cshtml              # AI chat interface

Models/
  └── ExpenseModels.cs         # DTOs and domain models
```

**Endpoints**:
- `/Index` - Main application UI
- `/Chat` - AI chat interface
- `/swagger` - API documentation
- `/api/expenses/*` - REST API endpoints
- `/api/chat` - Chat API

### 3. Azure SQL Database
**Purpose**: Persistent data storage with Entra ID authentication

**Security**:
- Entra ID Only Authentication: `true` (policy requirement)
- No SQL authentication allowed
- Managed Identity access
- Firewall rules for Azure services + deployment IP

**Schema**:
```sql
Roles (RoleId, RoleName, Description)
  └─ Users (UserId, UserName, Email, RoleId, ManagerId)
       └─ Expenses (ExpenseId, UserId, CategoryId, StatusId, AmountMinor, ...)
            ├─ ExpenseCategories (CategoryId, CategoryName)
            └─ ExpenseStatus (StatusId, StatusName)
```

**Stored Procedures** (20+ procedures):
- All database operations go through stored procedures
- No inline SQL in application code
- Proper parameterization prevents SQL injection

### 4. Azure OpenAI Service
**Purpose**: Provide AI-powered chat functionality

**Configuration**:
- Location: Sweden Central (quota availability)
- Model: GPT-4o
- Deployment: gpt-4o (2024-08-06)
- Capacity: 8 units
- Authentication: Managed Identity only

**Features**:
- Function calling to execute database operations
- Natural language queries
- Contextual responses
- Proper error handling

### 5. AI Search Service
**Purpose**: RAG (Retrieval-Augmented Generation) for contextual chat

**Configuration**:
- Tier: Basic
- Index: expense-docs
- Documents: Expense-related documentation
- Authentication: Managed Identity

**Use Case**:
- Provide context to AI for better responses
- Store expense policies, guidelines, FAQs
- Semantic search for relevant information

## Data Flow

### 1. User Submits Expense
```
User → Index Page → POST /api/expenses
  → ExpenseService.CreateExpenseAsync()
    → sp_CreateExpense stored procedure
      → SQL Database (INSERT)
        → Return ExpenseId
          → 201 Created response
```

### 2. Manager Approves Expense
```
Manager → Index Page (Filter: Pending) → GET /api/expenses/pending
  → ExpenseService.GetPendingExpensesAsync()
    → sp_GetPendingExpenses stored procedure
      → SQL Database (SELECT with JOIN)
        → Return expense list
          
Manager clicks Approve → POST /api/expenses/{id}/approve
  → ExpenseService.ApproveExpenseAsync(id, reviewerId)
    → sp_ApproveExpense stored procedure
      → SQL Database (UPDATE status, set reviewer, timestamp)
        → 200 OK response
```

### 3. AI Chat Query
```
User → Chat Page → "Show all pending expenses"
  → POST /api/chat
    → ChatService.GetChatResponseAsync()
      → Azure OpenAI (with function definitions)
        → AI decides to call get_pending_expenses function
          → ChatService.ExecuteFunctionAsync()
            → ExpenseService.GetPendingExpensesAsync()
              → sp_GetPendingExpenses
                → SQL Database
                  → Return data to AI
                    → AI formats response with lists/tables
                      → Display to user
```

## Authentication Flow

### App Service → SQL Database
```
1. App Service has User-Assigned Managed Identity
2. Connection string uses: Authentication=Active Directory Managed Identity
3. User Id parameter specifies MI Client ID
4. Azure AD issues token for database.windows.net scope
5. SQL Server validates token with Entra ID
6. MI user in database has db_datareader, db_datawriter, EXECUTE roles
7. Connection established
```

### App Service → Azure OpenAI
```
1. App Service uses ManagedIdentityCredential with Client ID
2. SDK requests token for cognitiveservices.azure.com scope
3. Azure AD issues token
4. OpenAI validates token and checks role assignment
5. MI has "Cognitive Services OpenAI User" role
6. Request processed
```

## Deployment Flow

### deploy.sh (Basic)
```
1. Create Resource Group
2. Deploy Bicep (deployGenAI=false)
   ├─ Managed Identity
   ├─ App Service + Plan
   └─ SQL Server + Database
3. Wait 30 seconds for SQL readiness
4. Configure SQL firewall (Azure services + deployment IP)
5. Wait 15 seconds for firewall propagation
6. Install Python dependencies (pyodbc, azure-identity)
7. Update Python scripts with deployment values
8. Deploy database schema (run-sql.py)
9. Configure MI database roles (run-sql-dbrole.py)
10. Deploy stored procedures (run-sql-stored-procs.py)
11. Build .NET application (dotnet publish)
12. Create app.zip at root (not in subdirectory)
13. Configure App Service settings (connection string, MI client ID)
14. Deploy app.zip to App Service (az webapp deploy)
15. Wait for application startup
16. Display URLs and instructions
```

### deploy-with-chat.sh (Full)
```
Same as deploy.sh but:
2. Deploy Bicep (deployGenAI=true)
   ├─ All basic resources
   ├─ Azure OpenAI (Sweden Central)
   └─ AI Search (UK South)
13. Configure App Service settings (includes OpenAI + Search endpoints)
```

## Security Considerations

### 1. No Secrets in Code
- Zero API keys, passwords, or connection strings in code
- All authentication via Managed Identity
- Configuration via App Service environment variables

### 2. Database Security
- Entra ID only authentication (policy compliance)
- Stored procedures only (no dynamic SQL)
- Parameterized queries prevent injection
- Least privilege access for MI

### 3. Network Security
- SQL firewall restricts to Azure services only
- HTTPS enforced on App Service
- TLS 1.2 minimum

### 4. Application Security
- XSS protection in chat UI (HTML escaping)
- Detailed error messages for troubleshooting (consider restricting in production)
- Input validation on all API endpoints

## Scalability Considerations

### Current Configuration (Dev/Test)
- App Service: S1 (1 instance)
- SQL Database: Basic tier (5 DTUs)
- Azure OpenAI: 8 capacity units
- AI Search: Basic tier

### Production Recommendations
- App Service: P1v2+ with auto-scaling
- SQL Database: Standard S3+ or Premium
- Azure OpenAI: Increase capacity as needed
- AI Search: Standard tier with replicas
- Add Application Insights for monitoring
- Add Azure Front Door for global distribution
- Implement caching (Redis)

## Monitoring & Diagnostics

### Application Insights (Recommended)
- Request telemetry
- Exception tracking
- Performance metrics
- Custom events

### SQL Database Metrics
- DTU percentage
- Connection failures
- Deadlocks
- Query performance

### App Service Diagnostics
- HTTP logs
- Application logs
- Failed request tracing
- Deployment logs

## Cost Optimization

### Development Environment
```
- App Service S1:       ~$73/month
- SQL Database Basic:   ~$5/month
- Managed Identity:     Free
- Azure OpenAI S0:      ~$0 + usage ($0.03/1K tokens)
- AI Search Basic:      ~$75/month
─────────────────────────────────────
Total:                  ~$153/month + usage
```

### Cost Reduction Strategies
1. Use B1 App Service tier for dev/test ($13/month)
2. Stop/start resources when not in use
3. Use consumption-based pricing where available
4. Implement auto-shutdown policies
5. Monitor usage with Cost Management

## Disaster Recovery

### Backup Strategy
- SQL Database: Automatic backups (7-day retention)
- App Service: Deployment slots for zero-downtime updates
- Infrastructure: Bicep templates in source control

### Recovery Procedures
1. Redeploy infrastructure from Bicep
2. Restore SQL database from backup
3. Redeploy application code
4. Update DNS if needed

## Future Enhancements

### Potential Improvements
1. **Authentication**: Add Entra ID login for users
2. **File Storage**: Azure Blob Storage for receipt uploads
3. **Notifications**: Logic Apps for approval emails
4. **Reporting**: Power BI integration
5. **Mobile**: Progressive Web App (PWA)
6. **Workflows**: Add multi-level approvals
7. **Integration**: Connect to accounting systems
8. **Analytics**: Usage analytics and insights
9. **Multi-region**: Geo-distributed deployment
10. **Compliance**: Add audit logging

---

**Document Version**: 1.0  
**Last Updated**: 2025  
**Maintained By**: Development Team
