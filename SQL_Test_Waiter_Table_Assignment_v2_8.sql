/* White Rabbit v2.8 — проверка назначенных столиков */
USE WhiteRabbitRestaurant;
GO

-- 1. Столики каждой открытой смены должны быть видны в этом списке.
EXEC dbo.sp_GetAdminWaiterShifts;
GO

-- 2. Замените 2 на UserId официанта.
-- Результат должен содержать TableId, TableNumber, SeatsCount, HallZone.
-- EXEC dbo.sp_GetWaiterAssignedTables @UserId = 2;
GO

-- 3. Ручное обновление распределения (только администратор).
-- Замените 1 на UserId администратора.
-- EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = 1, @ReturnResult = 1;
GO
