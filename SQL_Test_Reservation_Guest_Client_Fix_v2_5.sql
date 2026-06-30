/* White Rabbit v2.5 — проверка исправления бронирования. */
USE WhiteRabbitRestaurant;
GO

/* Должен существовать FILTERED UNIQUE INDEX с условием UserId IS NOT NULL. */
SELECT
    i.name AS IndexName,
    i.has_filter AS HasFilter,
    i.filter_definition AS FilterDefinition
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'dbo.Client')
  AND i.name = N'UX_Client_UserId_NotNull';
GO

/* Показать гостевых клиентов: несколько строк с UserId = NULL теперь допустимы. */
SELECT
    ClientId,
    UserId,
    FullName,
    Phone,
    CreatedAt
FROM dbo.Client
WHERE UserId IS NULL
ORDER BY ClientId DESC;
GO

/* Проверка параметров обновлённой процедуры. */
SELECT
    p.parameter_id,
    p.name AS ParameterName,
    TYPE_NAME(p.user_type_id) AS ParameterType
FROM sys.parameters p
WHERE p.object_id = OBJECT_ID(N'dbo.sp_CreateReservationByClientName')
ORDER BY p.parameter_id;
GO
