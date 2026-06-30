/* Проверка White Rabbit v2.9. Выполнять после SQL_Update_v2_9_Visual_Table_Maps_And_Shift_Filters.sql. */
USE WhiteRabbitRestaurant;
GO

DECLARE @Today DATE = CONVERT(DATE, SYSDATETIME());
DECLARE @FirstTableId INT = (SELECT TOP (1) TableId FROM dbo.RestaurantTable WHERE IsActive = 1 ORDER BY TableNumber);

PRINT N'1. Схема столиков на выбранный день:';
EXEC dbo.sp_GetReservationDayTableMap @ReservationDate = @Today;

IF @FirstTableId IS NOT NULL
BEGIN
    PRINT N'2. Брони первого активного столика на выбранный день:';
    EXEC dbo.sp_GetReservationsByTableAndDate @ReservationDate = @Today, @TableId = @FirstTableId;
END
GO

PRINT N'3. Все смены без фильтра:';
EXEC dbo.sp_GetAdminWaiterShiftsFiltered;
GO

PRINT N'4. Открытые смены за сегодня:';
EXEC dbo.sp_GetAdminWaiterShiftsFiltered @ShiftDate = CONVERT(DATE, SYSDATETIME()), @StatusCode = 'OPEN';
GO
