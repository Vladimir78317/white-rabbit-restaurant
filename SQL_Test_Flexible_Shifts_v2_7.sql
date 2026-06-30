/* White Rabbit v2.7 — quick verification */
USE WhiteRabbitRestaurant;
GO

-- 1. See all shifts, including the type of shift and automatically assigned tables.
EXEC dbo.sp_GetAdminWaiterShifts;
GO

-- 2. Recalculate table assignments for all open shifts.
-- Replace 1 with the real administrator UserId if needed.
-- EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = 1;
GO

-- 3. For an open waiter, see currently automatically assigned tables.
-- Replace 2 with the real waiter UserId.
-- EXEC dbo.sp_GetWaiterAssignedTables @UserId = 2;
GO
