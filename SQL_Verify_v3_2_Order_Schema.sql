/* White Rabbit v3.2 — обязательная проверка после SQL_Repair_v3_2... */
USE WhiteRabbitRestaurant;
GO
SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.CustomerOrder', N'U') IS NULL
    THROW 51600, N'Проверка не пройдена: dbo.CustomerOrder не найдена.', 1;

IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    THROW 51601, N'Проверка не пройдена: один или несколько обязательных столбцов отсутствуют.', 1;
GO

SELECT
    c.name AS ColumnName,
    TYPE_NAME(c.user_type_id) AS DataType,
    c.max_length AS MaxLength,
    c.is_nullable AS IsNullable
FROM sys.columns c
WHERE c.object_id = OBJECT_ID(N'dbo.CustomerOrder')
  AND c.name IN (N'ClientId', N'ChannelCode', N'GuestCount', N'WaiterShiftId')
ORDER BY c.column_id;
GO

DECLARE @Missing TABLE (ProcedureName SYSNAME NOT NULL);

INSERT INTO @Missing (ProcedureName)
SELECT v.ProcedureName
FROM (VALUES
    (N'sp_CreateUser'),
    (N'sp_GetKitchenOrders'),
    (N'sp_CreateOrderForWaiter'),
    (N'sp_CreateClientAppOrder'),
    (N'sp_AdminGetOrderStatuses'),
    (N'sp_GetClientOrderStatuses'),
    (N'sp_AdminCreateEmployee')
) v(ProcedureName)
WHERE OBJECT_ID(N'dbo.' + v.ProcedureName, N'P') IS NULL;

IF EXISTS (SELECT 1 FROM @Missing)
BEGIN
    SELECT ProcedureName AS MissingProcedure FROM @Missing;
    THROW 51602, N'Проверка не пройдена: отсутствуют обязательные процедуры.', 1;
END;
GO

EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetKitchenOrders';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateOrderForWaiter';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateClientAppOrder';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_AdminGetOrderStatuses';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetClientOrderStatuses';
GO

PRINT N'Проверка v3.2 завершена успешно: необходимые поля и процедуры доступны.';
GO
