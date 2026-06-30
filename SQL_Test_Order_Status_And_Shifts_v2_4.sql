/* Проверочные запросы для White Rabbit v2.4 */
USE WhiteRabbitRestaurant;
GO

/* 1. Проверить, какие смены будут закрыты автоматически. */
EXEC dbo.sp_AutoCloseExpiredWaiterShifts;
GO

/* 2. Просмотреть график смен, фактическое время и причины закрытия. */
EXEC dbo.sp_GetAdminWaiterShifts;
GO

/* 3. Просмотреть статусы всех заказов (для администратора). */
EXEC dbo.sp_AdminGetOrderStatuses;
GO

/* 4. Проверить, что смена не может быть длиннее 14 часов.
   Замените @WaiterUserId на UserId нужного официанта.

EXEC dbo.sp_AdminCreateWaiterShift
    @WaiterUserId = 2,
    @PlannedStartAt = '2026-07-01T09:00:00',
    @PlannedEndAt = '2026-07-01T23:01:00',
    @TableNumbers = N'1,2';
*/
