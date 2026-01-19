using Azure;
using Azure.AI.OpenAI;
using Azure.Identity;
using ExpenseManagement.Models;
using System.Text.Json;

namespace ExpenseManagement.Services;

public interface IChatService
{
    Task<string> GetChatResponseAsync(string userMessage);
}

public class ChatService : IChatService
{
    private readonly IConfiguration _configuration;
    private readonly ILogger<ChatService> _logger;
    private readonly IExpenseService _expenseService;
    private AzureOpenAIClient? _azureOpenAIClient;
    private string? _deploymentName;
    private bool _isGenAIConfigured = false;

    public ChatService(
        IConfiguration configuration,
        ILogger<ChatService> logger,
        IExpenseService expenseService)
    {
        _configuration = configuration;
        _logger = logger;
        _expenseService = expenseService;
        
        InitializeClient();
    }

    private void InitializeClient()
    {
        try
        {
            var endpoint = _configuration["OpenAI:Endpoint"];
            var deploymentName = _configuration["OpenAI:DeploymentName"];
            var managedIdentityClientId = _configuration["ManagedIdentityClientId"];

            if (string.IsNullOrEmpty(endpoint) || string.IsNullOrEmpty(deploymentName))
            {
                _logger.LogWarning("Azure OpenAI configuration is missing. Chat will use dummy responses.");
                _isGenAIConfigured = false;
                return;
            }

            _logger.LogInformation("Initializing Azure OpenAI client with endpoint: {Endpoint}", endpoint);

            // Use ManagedIdentityCredential with explicit client ID
            Azure.Core.TokenCredential credential;
            
            if (!string.IsNullOrEmpty(managedIdentityClientId))
            {
                _logger.LogInformation("Using ManagedIdentityCredential with client ID: {ClientId}", managedIdentityClientId);
                credential = new ManagedIdentityCredential(managedIdentityClientId);
            }
            else
            {
                _logger.LogInformation("Using DefaultAzureCredential");
                credential = new DefaultAzureCredential();
            }

            _azureOpenAIClient = new AzureOpenAIClient(new Uri(endpoint), credential);
            _deploymentName = deploymentName;
            _isGenAIConfigured = true;
            
            _logger.LogInformation("Azure OpenAI client initialized successfully");
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Failed to initialize Azure OpenAI client. Chat will use dummy responses.");
            _isGenAIConfigured = false;
        }
    }

    public async Task<string> GetChatResponseAsync(string userMessage)
    {
        if (!_isGenAIConfigured || _azureOpenAIClient == null || string.IsNullOrEmpty(_deploymentName))
        {
            return GetDummyResponse(userMessage);
        }

        try
        {
            // Build the conversation
            var chatMessages = new List<ChatRequestMessage>
            {
                new ChatRequestSystemMessage(GetSystemPrompt()),
                new ChatRequestUserMessage(userMessage)
            };

            // Create chat completions options
            var chatCompletionsOptions = new ChatCompletionsOptions(_deploymentName, chatMessages);

            // Define function tools
            chatCompletionsOptions.Functions.Add(new FunctionDefinition
            {
                Name = "get_all_expenses",
                Description = "Retrieves all expenses from the database",
                Parameters = BinaryData.FromObjectAsJson(new { type = "object", properties = new { }, required = new string[] { } })
            });

            chatCompletionsOptions.Functions.Add(new FunctionDefinition
            {
                Name = "get_pending_expenses",
                Description = "Retrieves all pending expenses that need manager approval",
                Parameters = BinaryData.FromObjectAsJson(new { type = "object", properties = new { }, required = new string[] { } })
            });

            chatCompletionsOptions.Functions.Add(new FunctionDefinition
            {
                Name = "get_expenses_by_status",
                Description = "Retrieves expenses filtered by status (Draft, Submitted, Approved, Rejected)",
                Parameters = BinaryData.FromObjectAsJson(new
                {
                    type = "object",
                    properties = new
                    {
                        status = new { type = "string", description = "Status name: Draft, Submitted, Approved, or Rejected" }
                    },
                    required = new[] { "status" }
                })
            });

            chatCompletionsOptions.Functions.Add(new FunctionDefinition
            {
                Name = "get_all_categories",
                Description = "Retrieves all expense categories",
                Parameters = BinaryData.FromObjectAsJson(new { type = "object", properties = new { }, required = new string[] { } })
            });

            chatCompletionsOptions.Functions.Add(new FunctionDefinition
            {
                Name = "get_all_users",
                Description = "Retrieves all users in the system",
                Parameters = BinaryData.FromObjectAsJson(new { type = "object", properties = new { }, required = new string[] { } })
            });

            // Function calling loop
            bool requiresAction = true;
            ChatCompletions? completion = null;
            int maxIterations = 5;
            int iteration = 0;

            while (requiresAction && iteration < maxIterations)
            {
                iteration++;
                
                var response = await _azureOpenAIClient.GetChatCompletionsAsync(chatCompletionsOptions);
                completion = response.Value;

                // Check if function calling is needed
                var firstChoice = completion.Choices[0];
                if (firstChoice.FinishReason == CompletionsFinishReason.FunctionCall)
                {
                    // Add assistant's message with function call
                    chatCompletionsOptions.Messages.Add(new ChatRequestAssistantMessage(firstChoice.Message.Content)
                    {
                        FunctionCall = firstChoice.Message.FunctionCall
                    });

                    // Execute the function
                    var functionCall = firstChoice.Message.FunctionCall;
                    _logger.LogInformation("Executing function: {FunctionName} with args: {Args}", 
                        functionCall.Name, functionCall.Arguments);

                    string functionResult = await ExecuteFunctionAsync(functionCall.Name, functionCall.Arguments);
                    
                    // Add function result to conversation
                    chatCompletionsOptions.Messages.Add(new ChatRequestFunctionMessage(functionCall.Name, functionResult));
                }
                else
                {
                    requiresAction = false;
                }
            }

            return completion?.Choices[0]?.Message?.Content ?? "I apologize, but I couldn't generate a response.";
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error getting chat response from Azure OpenAI");
            return $"Error: {ex.Message}. Please check the logs for more details.";
        }
    }

    private async Task<string> ExecuteFunctionAsync(string functionName, string functionArgs)
    {
        try
        {
            var argsDict = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(functionArgs);

            switch (functionName)
            {
                case "get_all_expenses":
                    var allExpenses = await _expenseService.GetAllExpensesAsync();
                    return JsonSerializer.Serialize(allExpenses);

                case "get_pending_expenses":
                    var pendingExpenses = await _expenseService.GetPendingExpensesAsync();
                    return JsonSerializer.Serialize(pendingExpenses);

                case "get_expenses_by_status":
                    var status = argsDict!["status"].GetString() ?? "Submitted";
                    var expensesByStatus = await _expenseService.GetExpensesByStatusAsync(status);
                    return JsonSerializer.Serialize(expensesByStatus);

                case "get_all_categories":
                    var categories = await _expenseService.GetAllCategoriesAsync();
                    return JsonSerializer.Serialize(categories);

                case "get_all_users":
                    var users = await _expenseService.GetAllUsersAsync();
                    return JsonSerializer.Serialize(users);

                default:
                    return JsonSerializer.Serialize(new { Error = "Unknown function" });
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error executing function {FunctionName}", functionName);
            return JsonSerializer.Serialize(new { Error = ex.Message });
        }
    }

    private string GetSystemPrompt()
    {
        return @"You are an AI assistant for an Expense Management System. You help users manage their expenses, including:
- Viewing expenses (all, pending, by status)
- Getting categories and users
- Providing expense statistics

When listing expenses or data, always format the output in a clear, readable way using:
- Bold text with **text** for emphasis
- Numbered lists (1. item) for ordered information
- Bullet points (- item or * item) for unordered lists
- Line breaks for better readability

Important information about the system:
- Expense amounts are in GBP (British Pounds)
- Categories: 1=Travel, 2=Meals, 3=Supplies, 4=Accommodation, 5=Other
- Statuses: Draft, Submitted, Approved, Rejected
- Sample users: Alice (UserId: 1, Employee), Bob Manager (UserId: 2, Manager)

Be helpful, concise, and format your responses for easy reading in a chat interface.";
    }

    private string GetDummyResponse(string userMessage)
    {
        return @"**GenAI Services Not Configured**

The Azure OpenAI and AI Search services have not been deployed yet. To enable the full AI-powered chat experience:

1. Run the `deploy-with-chat.sh` script to deploy GenAI resources
2. This will provision:
   - Azure OpenAI (GPT-4o model)
   - AI Search for RAG capabilities
   - Proper managed identity configuration

Once deployed, I'll be able to help you with:
- **Natural language queries** about your expenses
- **Smart summaries** and insights
- **Interactive expense management** through conversation
- **Context-aware** responses using your expense data

For now, please use the main UI to manage your expenses, or deploy the GenAI services to unlock the full chat experience!";
    }
}
