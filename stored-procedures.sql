-- Stored Procedures for Expense Management System
-- All database operations should use these stored procedures

-- =============================================
-- User Management Stored Procedures
-- =============================================

-- Get all users
CREATE OR ALTER PROCEDURE sp_GetAllUsers
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        u.UserId,
        u.UserName,
        u.Email,
        r.RoleName,
        u.ManagerId,
        m.UserName AS ManagerName,
        u.IsActive,
        u.CreatedAt
    FROM dbo.Users u
    INNER JOIN dbo.Roles r ON u.RoleId = r.RoleId
    LEFT JOIN dbo.Users m ON u.ManagerId = m.UserId
    WHERE u.IsActive = 1
    ORDER BY u.UserName;
END
GO

-- Get user by ID
CREATE OR ALTER PROCEDURE sp_GetUserById
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        u.UserId,
        u.UserName,
        u.Email,
        u.RoleId,
        r.RoleName,
        u.ManagerId,
        m.UserName AS ManagerName,
        u.IsActive,
        u.CreatedAt
    FROM dbo.Users u
    INNER JOIN dbo.Roles r ON u.RoleId = r.RoleId
    LEFT JOIN dbo.Users m ON u.ManagerId = m.UserId
    WHERE u.UserId = @UserId;
END
GO

-- =============================================
-- Expense Management Stored Procedures
-- =============================================

-- Get all expenses
CREATE OR ALTER PROCEDURE sp_GetAllExpenses
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ExpenseId,
        e.UserId,
        u.UserName,
        u.Email,
        e.CategoryId,
        c.CategoryName,
        e.StatusId,
        s.StatusName,
        e.AmountMinor,
        CAST(e.AmountMinor / 100.0 AS DECIMAL(10,2)) AS AmountDecimal,
        e.Currency,
        e.ExpenseDate,
        e.Description,
        e.ReceiptFile,
        e.SubmittedAt,
        e.ReviewedBy,
        r.UserName AS ReviewerName,
        e.ReviewedAt,
        e.CreatedAt
    FROM dbo.Expenses e
    INNER JOIN dbo.Users u ON e.UserId = u.UserId
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    LEFT JOIN dbo.Users r ON e.ReviewedBy = r.UserId
    ORDER BY e.CreatedAt DESC;
END
GO

-- Get expense by ID
CREATE OR ALTER PROCEDURE sp_GetExpenseById
    @ExpenseId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ExpenseId,
        e.UserId,
        u.UserName,
        u.Email,
        e.CategoryId,
        c.CategoryName,
        e.StatusId,
        s.StatusName,
        e.AmountMinor,
        CAST(e.AmountMinor / 100.0 AS DECIMAL(10,2)) AS AmountDecimal,
        e.Currency,
        e.ExpenseDate,
        e.Description,
        e.ReceiptFile,
        e.SubmittedAt,
        e.ReviewedBy,
        r.UserName AS ReviewerName,
        e.ReviewedAt,
        e.CreatedAt
    FROM dbo.Expenses e
    INNER JOIN dbo.Users u ON e.UserId = u.UserId
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    LEFT JOIN dbo.Users r ON e.ReviewedBy = r.UserId
    WHERE e.ExpenseId = @ExpenseId;
END
GO

-- Get expenses by user ID
CREATE OR ALTER PROCEDURE sp_GetExpensesByUserId
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ExpenseId,
        e.UserId,
        u.UserName,
        e.CategoryId,
        c.CategoryName,
        e.StatusId,
        s.StatusName,
        e.AmountMinor,
        CAST(e.AmountMinor / 100.0 AS DECIMAL(10,2)) AS AmountDecimal,
        e.Currency,
        e.ExpenseDate,
        e.Description,
        e.ReceiptFile,
        e.SubmittedAt,
        e.ReviewedBy,
        r.UserName AS ReviewerName,
        e.ReviewedAt,
        e.CreatedAt
    FROM dbo.Expenses e
    INNER JOIN dbo.Users u ON e.UserId = u.UserId
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    LEFT JOIN dbo.Users r ON e.ReviewedBy = r.UserId
    WHERE e.UserId = @UserId
    ORDER BY e.CreatedAt DESC;
END
GO

-- Get expenses by status
CREATE OR ALTER PROCEDURE sp_GetExpensesByStatus
    @StatusName NVARCHAR(50)
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ExpenseId,
        e.UserId,
        u.UserName,
        u.Email,
        e.CategoryId,
        c.CategoryName,
        e.StatusId,
        s.StatusName,
        e.AmountMinor,
        CAST(e.AmountMinor / 100.0 AS DECIMAL(10,2)) AS AmountDecimal,
        e.Currency,
        e.ExpenseDate,
        e.Description,
        e.ReceiptFile,
        e.SubmittedAt,
        e.ReviewedBy,
        r.UserName AS ReviewerName,
        e.ReviewedAt,
        e.CreatedAt
    FROM dbo.Expenses e
    INNER JOIN dbo.Users u ON e.UserId = u.UserId
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    LEFT JOIN dbo.Users r ON e.ReviewedBy = r.UserId
    WHERE s.StatusName = @StatusName
    ORDER BY e.SubmittedAt ASC;
END
GO

-- Create new expense
CREATE OR ALTER PROCEDURE sp_CreateExpense
    @UserId INT,
    @CategoryId INT,
    @AmountMinor INT,
    @Currency NVARCHAR(3),
    @ExpenseDate DATE,
    @Description NVARCHAR(1000),
    @ReceiptFile NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @DraftStatusId INT;
    SELECT @DraftStatusId = StatusId FROM dbo.ExpenseStatus WHERE StatusName = 'Draft';
    
    INSERT INTO dbo.Expenses (UserId, CategoryId, StatusId, AmountMinor, Currency, ExpenseDate, Description, ReceiptFile)
    VALUES (@UserId, @CategoryId, @DraftStatusId, @AmountMinor, @Currency, @ExpenseDate, @Description, @ReceiptFile);
    
    SELECT SCOPE_IDENTITY() AS ExpenseId;
END
GO

-- Submit expense
CREATE OR ALTER PROCEDURE sp_SubmitExpense
    @ExpenseId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @SubmittedStatusId INT;
    SELECT @SubmittedStatusId = StatusId FROM dbo.ExpenseStatus WHERE StatusName = 'Submitted';
    
    UPDATE dbo.Expenses
    SET StatusId = @SubmittedStatusId,
        SubmittedAt = SYSUTCDATETIME()
    WHERE ExpenseId = @ExpenseId;
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Approve expense
CREATE OR ALTER PROCEDURE sp_ApproveExpense
    @ExpenseId INT,
    @ReviewerId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @ApprovedStatusId INT;
    SELECT @ApprovedStatusId = StatusId FROM dbo.ExpenseStatus WHERE StatusName = 'Approved';
    
    UPDATE dbo.Expenses
    SET StatusId = @ApprovedStatusId,
        ReviewedBy = @ReviewerId,
        ReviewedAt = SYSUTCDATETIME()
    WHERE ExpenseId = @ExpenseId;
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Reject expense
CREATE OR ALTER PROCEDURE sp_RejectExpense
    @ExpenseId INT,
    @ReviewerId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DECLARE @RejectedStatusId INT;
    SELECT @RejectedStatusId = StatusId FROM dbo.ExpenseStatus WHERE StatusName = 'Rejected';
    
    UPDATE dbo.Expenses
    SET StatusId = @RejectedStatusId,
        ReviewedBy = @ReviewerId,
        ReviewedAt = SYSUTCDATETIME()
    WHERE ExpenseId = @ExpenseId;
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Update expense
CREATE OR ALTER PROCEDURE sp_UpdateExpense
    @ExpenseId INT,
    @CategoryId INT,
    @AmountMinor INT,
    @ExpenseDate DATE,
    @Description NVARCHAR(1000),
    @ReceiptFile NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    
    UPDATE dbo.Expenses
    SET CategoryId = @CategoryId,
        AmountMinor = @AmountMinor,
        ExpenseDate = @ExpenseDate,
        Description = @Description,
        ReceiptFile = ISNULL(@ReceiptFile, ReceiptFile)
    WHERE ExpenseId = @ExpenseId;
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- Delete expense (only if Draft)
CREATE OR ALTER PROCEDURE sp_DeleteExpense
    @ExpenseId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    DELETE FROM dbo.Expenses
    WHERE ExpenseId = @ExpenseId
    AND StatusId = (SELECT StatusId FROM dbo.ExpenseStatus WHERE StatusName = 'Draft');
    
    SELECT @@ROWCOUNT AS RowsAffected;
END
GO

-- =============================================
-- Category Management Stored Procedures
-- =============================================

-- Get all categories
CREATE OR ALTER PROCEDURE sp_GetAllCategories
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        CategoryId,
        CategoryName,
        IsActive
    FROM dbo.ExpenseCategories
    WHERE IsActive = 1
    ORDER BY CategoryName;
END
GO

-- Get category by ID
CREATE OR ALTER PROCEDURE sp_GetCategoryById
    @CategoryId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        CategoryId,
        CategoryName,
        IsActive
    FROM dbo.ExpenseCategories
    WHERE CategoryId = @CategoryId;
END
GO

-- =============================================
-- Status Management Stored Procedures
-- =============================================

-- Get all statuses
CREATE OR ALTER PROCEDURE sp_GetAllStatuses
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        StatusId,
        StatusName
    FROM dbo.ExpenseStatus
    ORDER BY StatusId;
END
GO

-- =============================================
-- Role Management Stored Procedures
-- =============================================

-- Get all roles
CREATE OR ALTER PROCEDURE sp_GetAllRoles
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        RoleId,
        RoleName,
        Description
    FROM dbo.Roles
    ORDER BY RoleName;
END
GO

-- =============================================
-- Statistics and Reports Stored Procedures
-- =============================================

-- Get expense summary by status
CREATE OR ALTER PROCEDURE sp_GetExpenseSummaryByStatus
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.StatusName,
        COUNT(*) AS ExpenseCount,
        SUM(e.AmountMinor) AS TotalAmountMinor,
        CAST(SUM(e.AmountMinor) / 100.0 AS DECIMAL(10,2)) AS TotalAmount
    FROM dbo.Expenses e
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    GROUP BY s.StatusName
    ORDER BY s.StatusName;
END
GO

-- Get expense summary by category
CREATE OR ALTER PROCEDURE sp_GetExpenseSummaryByCategory
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        c.CategoryName,
        COUNT(*) AS ExpenseCount,
        SUM(e.AmountMinor) AS TotalAmountMinor,
        CAST(SUM(e.AmountMinor) / 100.0 AS DECIMAL(10,2)) AS TotalAmount
    FROM dbo.Expenses e
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    GROUP BY c.CategoryName
    ORDER BY TotalAmountMinor DESC;
END
GO

-- Get pending expenses for approval (for managers)
CREATE OR ALTER PROCEDURE sp_GetPendingExpenses
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        e.ExpenseId,
        e.UserId,
        u.UserName,
        u.Email,
        e.CategoryId,
        c.CategoryName,
        e.StatusId,
        s.StatusName,
        e.AmountMinor,
        CAST(e.AmountMinor / 100.0 AS DECIMAL(10,2)) AS AmountDecimal,
        e.Currency,
        e.ExpenseDate,
        e.Description,
        e.ReceiptFile,
        e.SubmittedAt,
        e.CreatedAt
    FROM dbo.Expenses e
    INNER JOIN dbo.Users u ON e.UserId = u.UserId
    INNER JOIN dbo.ExpenseCategories c ON e.CategoryId = c.CategoryId
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    WHERE s.StatusName = 'Submitted'
    ORDER BY e.SubmittedAt ASC;
END
GO

-- Get user's expense summary
CREATE OR ALTER PROCEDURE sp_GetUserExpenseSummary
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    
    SELECT 
        s.StatusName,
        COUNT(*) AS ExpenseCount,
        SUM(e.AmountMinor) AS TotalAmountMinor,
        CAST(SUM(e.AmountMinor) / 100.0 AS DECIMAL(10,2)) AS TotalAmount
    FROM dbo.Expenses e
    INNER JOIN dbo.ExpenseStatus s ON e.StatusId = s.StatusId
    WHERE e.UserId = @UserId
    GROUP BY s.StatusName
    ORDER BY s.StatusName;
END
GO
