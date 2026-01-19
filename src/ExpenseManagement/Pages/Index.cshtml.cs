using ExpenseManagement.Models;
using ExpenseManagement.Services;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ExpenseManagement.Pages;

public class IndexModel : PageModel
{
    private readonly IExpenseService _expenseService;
    private readonly ILogger<IndexModel> _logger;

    public IndexModel(IExpenseService expenseService, ILogger<IndexModel> logger)
    {
        _expenseService = expenseService;
        _logger = logger;
    }

    public List<Expense> Expenses { get; set; } = new();
    public List<ExpenseCategory> Categories { get; set; } = new();
    public List<User> Users { get; set; } = new();
    public string? ErrorMessage { get; set; }
    public string? ErrorDetails { get; set; }
    public string? ErrorLocation { get; set; }

    [BindProperty(SupportsGet = true)]
    public string? StatusFilter { get; set; }

    public async Task OnGetAsync()
    {
        try
        {
            // Load categories and users
            Categories = await _expenseService.GetAllCategoriesAsync();
            Users = await _expenseService.GetAllUsersAsync();

            // Load expenses based on filter
            if (!string.IsNullOrEmpty(StatusFilter))
            {
                Expenses = await _expenseService.GetExpensesByStatusAsync(StatusFilter);
            }
            else
            {
                Expenses = await _expenseService.GetAllExpensesAsync();
            }
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error loading expense data");
            
            // Provide detailed error information
            ErrorMessage = "Database Connection Error";
            ErrorDetails = GetDetailedErrorMessage(ex);
            ErrorLocation = $"File: Pages/Index.cshtml.cs, Method: OnGetAsync";

            // Load dummy data for display
            LoadDummyData();
        }
    }

    private string GetDetailedErrorMessage(Exception ex)
    {
        var message = ex.Message;

        // Check for common managed identity issues
        if (message.Contains("Login failed") || message.Contains("authentication"))
        {
            return $"Managed Identity Authentication Failed: {message}\n\n" +
                   "SOLUTION:\n" +
                   "1. Ensure the managed identity has been assigned to the App Service\n" +
                   "2. Run the database role assignment script: python3 run-sql-dbrole.py\n" +
                   "3. Verify the managed identity has db_datareader, db_datawriter, and EXECUTE permissions\n" +
                   "4. Check that AZURE_CLIENT_ID environment variable is set in App Service configuration\n" +
                   "5. Wait 5-10 minutes after role assignment for permissions to propagate\n\n" +
                   $"Technical details: {ex.GetType().Name} - {message}";
        }

        if (message.Contains("Could not find") || message.Contains("network-related"))
        {
            return $"Database Connection Failed: {message}\n\n" +
                   "SOLUTION:\n" +
                   "1. Verify the SQL Server firewall allows connections from this App Service\n" +
                   "2. Check that the connection string in App Service configuration is correct\n" +
                   "3. Ensure the Azure SQL database is running and accessible\n\n" +
                   $"Technical details: {ex.GetType().Name} - {message}";
        }

        return $"{ex.GetType().Name}: {message}\n\n" +
               "Please check the application logs for more detailed information. " +
               "Stack trace has been logged to the console.";
    }

    private void LoadDummyData()
    {
        Categories = new List<ExpenseCategory>
        {
            new() { CategoryId = 1, CategoryName = "Travel", IsActive = true },
            new() { CategoryId = 2, CategoryName = "Meals", IsActive = true },
            new() { CategoryId = 3, CategoryName = "Supplies", IsActive = true },
            new() { CategoryId = 4, CategoryName = "Accommodation", IsActive = true },
            new() { CategoryId = 5, CategoryName = "Other", IsActive = true }
        };

        Users = new List<User>
        {
            new() { UserId = 1, UserName = "Alice Example", Email = "alice@example.co.uk", RoleName = "Employee" },
            new() { UserId = 2, UserName = "Bob Manager", Email = "bob.manager@example.co.uk", RoleName = "Manager" }
        };

        Expenses = new List<Expense>
        {
            new()
            {
                ExpenseId = 1,
                UserId = 1,
                UserName = "Alice Example",
                Email = "alice@example.co.uk",
                CategoryId = 1,
                CategoryName = "Travel",
                StatusId = 2,
                StatusName = "Submitted",
                AmountMinor = 2540,
                AmountDecimal = 25.40m,
                Currency = "GBP",
                ExpenseDate = DateTime.Now.AddDays(-5),
                Description = "Taxi from airport to client site",
                CreatedAt = DateTime.Now.AddDays(-5)
            },
            new()
            {
                ExpenseId = 2,
                UserId = 1,
                UserName = "Alice Example",
                Email = "alice@example.co.uk",
                CategoryId = 2,
                CategoryName = "Meals",
                StatusId = 3,
                StatusName = "Approved",
                AmountMinor = 1425,
                AmountDecimal = 14.25m,
                Currency = "GBP",
                ExpenseDate = DateTime.Now.AddDays(-15),
                Description = "Client lunch meeting",
                ReviewerName = "Bob Manager",
                CreatedAt = DateTime.Now.AddDays(-15)
            }
        };
    }
}
