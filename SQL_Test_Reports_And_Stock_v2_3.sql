/* Быстрая проверка после выполнения SQL_Update_v2_3_Reports_And_Stock.sql */
USE WhiteRabbitRestaurant;
GO

/* 1. Посмотреть остатки и историю пополнений */
EXEC dbo.sp_AdminGetStock;
EXEC dbo.sp_AdminGetStockMovements;
GO

/* 2. Найти пользователя-администратора и одно блюдо */
DECLARE @AdminUserId INT =
(
    SELECT TOP (1) u.UserId
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE r.RoleCode = 'ADMIN'
      AND u.IsActive = 1
    ORDER BY u.UserId
);

DECLARE @DishId INT = (SELECT TOP (1) DishId FROM dbo.Dish ORDER BY DishId);

/* 3. Пополнить склад на 5 порций */
EXEC dbo.sp_AdminRestockDish
    @AdminUserId = @AdminUserId,
    @DishId = @DishId,
    @Quantity = 5,
    @Comment = N'Проверка пополнения склада v2.3';
GO

/* 4. Отчёт за текущий месяц */
EXEC dbo.sp_AdminSalesReport
    @DateFrom = DATEFROMPARTS(YEAR(GETDATE()), MONTH(GETDATE()), 1),
    @DateTo = CONVERT(DATE, GETDATE());
GO
