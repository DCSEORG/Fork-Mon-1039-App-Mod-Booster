using Microsoft.AspNetCore.Mvc.RazorPages;

namespace ExpenseManagement.Pages;

public class ChatModel : PageModel
{
    private readonly ILogger<ChatModel> _logger;

    public ChatModel(ILogger<ChatModel> logger)
    {
        _logger = logger;
    }

    public void OnGet()
    {
    }
}
