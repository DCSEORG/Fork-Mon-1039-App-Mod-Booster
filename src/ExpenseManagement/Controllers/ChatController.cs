using ExpenseManagement.Services;
using Microsoft.AspNetCore.Mvc;

namespace ExpenseManagement.Controllers;

[ApiController]
[Route("api/[controller]")]
[Produces("application/json")]
public class ChatController : ControllerBase
{
    private readonly IChatService _chatService;
    private readonly ILogger<ChatController> _logger;

    public ChatController(IChatService chatService, ILogger<ChatController> logger)
    {
        _chatService = chatService;
        _logger = logger;
    }

    public class ChatRequest
    {
        public string Message { get; set; } = string.Empty;
    }

    /// <summary>
    /// Send a chat message and get AI response
    /// </summary>
    [HttpPost]
    public async Task<ActionResult<string>> Chat([FromBody] ChatRequest request)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(request.Message))
            {
                return BadRequest(new { error = "Message cannot be empty" });
            }

            var response = await _chatService.GetChatResponseAsync(request.Message);
            
            return Ok(new { response });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Error processing chat request");
            return StatusCode(500, new { error = "Failed to process chat request", details = ex.Message });
        }
    }
}
