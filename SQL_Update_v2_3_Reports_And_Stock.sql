/*
  White Rabbit v2.3 — отчёт по продажам и пополнение склада.
  Выполните ОДИН РАЗ в SSMS после SQL-обновлений v2.0 и v2.1.
*/
USE WhiteRabbitRestaurant;
GO

/* История пополнений склада. Создаётся один раз и не влияет на старые данные. */
IF OBJECT_ID(N'dbo.DishStockMovement', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DishStockMovement
    (
        StockMovementId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DishStockMovement PRIMARY KEY,
        DishId INT NOT NULL,
        Quantity INT NOT NULL,
        OperationType VARCHAR(20) NOT NULL CONSTRAINT DF_DishStockMovement_OperationType DEFAULT ('RESTOCK'),
        AdminUserId INT NOT NULL,
        Comment NVARCHAR(250) NULL,
        CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_DishStockMovement_CreatedAt DEFAULT (SYSDATETIME()),

        CONSTRAINT CK_DishStockMovement_Quantity CHECK (Quantity > 0),
        CONSTRAINT FK_DishStockMovement_Dish FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId),
        CONSTRAINT FK_DishStockMovement_Admin FOREIGN KEY (AdminUserId) REFERENCES dbo.AppUser(UserId)
    );
END
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_DishStockMovement_Dish_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.DishStockMovement')
)
BEGIN
    CREATE INDEX IX_DishStockMovement_Dish_CreatedAt
        ON dbo.DishStockMovement(DishId, CreatedAt DESC);
END
GO

/* Детальный отчёт по фактически оплаченным продажам за выбранный период. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminSalesReport
    @DateFrom DATE,
    @DateTo DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @DateTo < @DateFrom
        THROW 51401, N'Дата окончания периода не может быть раньше даты начала.', 1;

    DECLARE @StartDateTime DATETIME2 = CAST(@DateFrom AS DATETIME2);
    DECLARE @EndDateTime DATETIME2 = DATEADD(DAY, 1, CAST(@DateTo AS DATETIME2));

    SELECT
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        SUM(oi.Quantity) AS [Продано порций],
        COUNT(DISTINCT o.OrderId) AS [Заказов],
        CAST(SUM(oi.Quantity * oi.UnitPrice) AS DECIMAL(12,2)) AS [Выручка, руб.]
    FROM dbo.Bill b
    JOIN dbo.CustomerOrder o ON o.OrderId = b.OrderId
    JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    JOIN dbo.Dish d ON d.DishId = oi.DishId
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    WHERE b.IsPaid = 1
      AND COALESCE(b.PaidAt, b.IssuedAt, o.FinalizedAt, o.CreatedAt) >= @StartDateTime
      AND COALESCE(b.PaidAt, b.IssuedAt, o.FinalizedAt, o.CreatedAt) < @EndDateTime
    GROUP BY c.CategoryName, d.DishName
    ORDER BY c.CategoryName, d.DishName;
END
GO

/* Остатки блюд и их доступность для администратора. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStock
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        ds.AvailablePortions AS [Остаток, порций],
        CASE WHEN ISNULL(sl.IsStopListed, 0) = 1 THEN N'Да' ELSE N'Нет' END AS [Стоп-лист],
        CASE WHEN d.IsActive = 1 THEN N'Да' ELSE N'Нет' END AS [Доступно в меню]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    LEFT JOIN dbo.DishStock ds ON ds.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    ORDER BY c.CategoryName, d.DishName;
END
GO

/* История последних пополнений склада. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStockMovements
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
        m.StockMovementId,
        m.CreatedAt AS [Дата и время],
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        m.Quantity AS [Добавлено порций],
        CONCAT(u.LastName, N' ', u.FirstName) AS [Администратор],
        m.Comment AS [Комментарий]
    FROM dbo.DishStockMovement m
    JOIN dbo.Dish d ON d.DishId = m.DishId
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.AppUser u ON u.UserId = m.AdminUserId
    ORDER BY m.CreatedAt DESC, m.StockMovementId DESC;
END
GO

/* Пополнение остатков. Доступно только активному администратору. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminRestockDish
    @AdminUserId INT,
    @DishId INT,
    @Quantity INT,
    @Comment NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 51402, N'Количество порций для пополнения должно быть больше нуля.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @AdminUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51403, N'Пополнять склад может только активный администратор.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dish WHERE DishId = @DishId)
        THROW 51404, N'Блюдо не найдено.', 1;

    DECLARE @DishName NVARCHAR(150);
    DECLARE @NewStock INT;

    BEGIN TRANSACTION;

    SELECT @DishName = DishName
    FROM dbo.Dish
    WHERE DishId = @DishId;

    IF EXISTS (SELECT 1 FROM dbo.DishStock WITH (UPDLOCK, HOLDLOCK) WHERE DishId = @DishId)
    BEGIN
        UPDATE dbo.DishStock
        SET AvailablePortions = AvailablePortions + @Quantity
        WHERE DishId = @DishId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.DishStock(DishId, AvailablePortions)
        VALUES(@DishId, @Quantity);
    END

    SELECT @NewStock = AvailablePortions
    FROM dbo.DishStock
    WHERE DishId = @DishId;

    INSERT INTO dbo.DishStockMovement(DishId, Quantity, OperationType, AdminUserId, Comment)
    VALUES(@DishId, @Quantity, 'RESTOCK', @AdminUserId, @Comment);

    COMMIT TRANSACTION;

    SELECT
        CONCAT(N'Склад пополнен: «', @DishName, N'» +', @Quantity, N' порц. Текущий остаток: ', @NewStock, N' порц.') AS Message,
        @NewStock AS AvailablePortions;
END
GO
