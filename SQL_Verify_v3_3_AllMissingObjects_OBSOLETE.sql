
/* White Rabbit v3.3 — проверка базы, к которой подключено приложение. */
USE WhiteRabbitRestaurant;
GO
SET NOCOUNT ON;
GO

SELECT
    CAST(SERVERPROPERTY(N'ServerName') AS NVARCHAR(256)) AS [SQL Server],
    @@SERVERNAME AS [Имя экземпляра],
    DB_NAME() AS [База данных],
    SUSER_SNAME() AS [Текущий пользователь];
GO

DECLARE @Required TABLE (ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT INTO @Required(ObjectName, ObjectType)
VALUES
    (N'DishStopList', N'U'),
    (N'DishStockMovement', N'U'),
    (N'sp_GetAvailableMenu', N'P'),
    (N'sp_GetKitchenDishes', N'P'),
    (N'sp_SetDishStopListStatus', N'P'),
    (N'sp_GetReservationDayTableMap', N'P'),
    (N'sp_GetReservationsByTableAndDate', N'P'),
    (N'sp_GetAdminWaiterShiftsFiltered', N'P'),
    (N'sp_GetAdminShiftsFiltered', N'P'),
    (N'sp_GetClientReservations', N'P'),
    (N'sp_GetWaiterReservationDayTableMap', N'P'),
    (N'sp_GetWaiterReservationsByTableAndDate', N'P'),
    (N'sp_GetKitchenOrders', N'P'),
    (N'sp_CreateOrderForWaiter', N'P'),
    (N'sp_CreateClientAppOrder', N'P'),
    (N'sp_AdminGetOrderStatuses', N'P'),
    (N'sp_GetClientOrderStatuses', N'P');

SELECT
    N'dbo.' + ObjectName AS [Объект],
    CASE WHEN OBJECT_ID(N'dbo.' + ObjectName, ObjectType) IS NULL THEN N'ОТСУТСТВУЕТ' ELSE N'OK' END AS [Статус]
FROM @Required
ORDER BY ObjectType, ObjectName;

DECLARE @Missing NVARCHAR(MAX) =
(
    SELECT STRING_AGG(ObjectName, N', ')
    FROM @Required
    WHERE OBJECT_ID(N'dbo.' + ObjectName, ObjectType) IS NULL
);

IF @Missing IS NOT NULL
    THROW 51910, CONCAT(N'Проверка не пройдена. Отсутствуют: ', @Missing), 1;

IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    THROW 51911, N'Проверка не пройдена: в CustomerOrder отсутствуют обязательные поля.', 1;

/* Две процедуры выполняются без передачи пользователя и проверяют, что схема читается. */
EXEC dbo.sp_GetAvailableMenu;
EXEC dbo.sp_GetReservationDayTableMap @ReservationDate = CONVERT(DATE, SYSDATETIME());

PRINT N'Проверка v3.3 завершена успешно.';
GO
