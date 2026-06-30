
/* White Rabbit v3.4 — проверка базы с совместимым T-SQL. */
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

/* В THROW передаётся только переменная или строка, а не CONCAT(...). */
DECLARE @Missing NVARCHAR(MAX);

SELECT @Missing = STUFF
(
    (
        SELECT N', ' + required.ObjectName
        FROM @Required AS required
        WHERE OBJECT_ID(N'dbo.' + required.ObjectName, required.ObjectType) IS NULL
        ORDER BY required.ObjectName
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'),
    1,
    2,
    N''
);

IF NULLIF(@Missing, N'') IS NOT NULL
BEGIN
    DECLARE @VerificationErrorMessage NVARCHAR(2048);
    SET @VerificationErrorMessage = N'Проверка не пройдена. Отсутствуют: ' + @Missing;
    THROW 51910, @VerificationErrorMessage, 1;
END;

IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    THROW 51911, N'Проверка не пройдена: в CustomerOrder отсутствуют обязательные поля.', 1;

/* Две процедуры выполняются без передачи пользователя и проверяют, что схема читается. */
EXEC dbo.sp_GetAvailableMenu;
EXEC dbo.sp_GetReservationDayTableMap @ReservationDate = CONVERT(DATE, SYSDATETIME());

PRINT N'Проверка v3.4 завершена успешно.';
GO
