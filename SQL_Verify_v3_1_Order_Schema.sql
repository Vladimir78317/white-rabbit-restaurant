/* White Rabbit v3.1 — быстрая проверка после установки или обновления */
USE WhiteRabbitRestaurant;
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

SELECT name AS ProcedureName
FROM sys.procedures
WHERE name IN
(
    N'sp_CreateUser',
    N'sp_GetKitchenOrders',
    N'sp_CreateOrderForWaiter',
    N'sp_CreateClientAppOrder',
    N'sp_AdminGetOrderStatuses',
    N'sp_GetClientOrderStatuses'
)
ORDER BY name;
GO

EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetKitchenOrders';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateOrderForWaiter';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateClientAppOrder';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_AdminGetOrderStatuses';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetClientOrderStatuses';
GO

PRINT N'Проверка v3.1 завершена. Ошибок 207 быть не должно.';
GO
