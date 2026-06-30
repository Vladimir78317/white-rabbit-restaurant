/* Tests for White Rabbit v2.6 */
USE WhiteRabbitRestaurant;
GO

SELECT p.name AS ProcedureName
FROM sys.procedures p
WHERE p.name IN (N'sp_CreateReservationSafe', N'sp_GetReservationTableMap');
GO

EXEC dbo.sp_GetReservationTableMap
    @StartAt = '2026-07-01T12:00:00',
    @EndAt = '2026-07-01T14:00:00',
    @GuestCount = 2;
GO

/* Check that only non-NULL UserId values are unique. */
SELECT i.name, i.has_filter, i.filter_definition
FROM sys.indexes i
WHERE i.object_id = OBJECT_ID(N'dbo.Client')
  AND i.name = N'UX_Client_UserId_NotNull';
GO
