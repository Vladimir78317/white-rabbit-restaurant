/*
 White Rabbit v2.8 — исправление отображения столиков у официанта.
 Выполните ОДИН РАЗ после SQL_Update_v2_7_Flexible_Shifts_And_Auto_Table_Distribution.sql.

 Причина исправления:
 sp_GetWaiterAssignedTables вызывала процедуру перераспределения, которая
 возвращала служебную таблицу первой. Приложение читало именно её вместо
 списка столиков, поэтому ComboBox «Столик» оставался пустым.
*/
USE WhiteRabbitRestaurant;
GO

/*
 @ReturnResult = 0 по умолчанию: при внутренних вызовах процедура не должна
 возвращать дополнительный result set и мешать следующему SELECT.
*/
CREATE OR ALTER PROCEDURE dbo.sp_RebalanceOpenWaiterTables
    @AdminUserId INT = NULL,
    @ReturnResult BIT = 0
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @AdminUserId IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.AppUser u
           JOIN dbo.AppRole r ON r.RoleId = u.RoleId
           WHERE u.UserId = @AdminUserId
             AND u.IsActive = 1
             AND r.RoleCode = 'ADMIN'
       )
        THROW 51501, N'Перераспределять столики может только администратор.', 1;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @OpenShifts TABLE
    (
        ShiftId INT NOT NULL PRIMARY KEY,
        ShiftRank INT NOT NULL
    );

    /*
      Открытая смена с незавершёнными заказами остаётся в распределении даже
      после планового времени окончания: её нельзя закрыть автоматически,
      пока обслуживание и оплата не завершены.
    */
    INSERT INTO @OpenShifts (ShiftId, ShiftRank)
    SELECT
        ws.ShiftId,
        ROW_NUMBER() OVER (ORDER BY ws.ActualOpenAt, ws.ShiftId)
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE ss.StatusCode = 'OPEN'
      AND u.IsActive = 1
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL;

    DECLARE @WaiterCount INT = (SELECT COUNT(*) FROM @OpenShifts);
    DECLARE @TableCount INT = (SELECT COUNT(*) FROM dbo.RestaurantTable WHERE IsActive = 1);

    IF @WaiterCount = 0
    BEGIN
        IF @ReturnResult = 1
            SELECT 0 AS WaiterCount, @TableCount AS TableCount,
                   N'Открытых смен нет: распределение столиков не требуется.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION;

    DELETE a
    FROM dbo.WaiterTableAssignment a
    JOIN @OpenShifts os ON os.ShiftId = a.ShiftId;

    ;WITH ActiveTables AS
    (
        SELECT
            t.TableId,
            ROW_NUMBER() OVER (ORDER BY t.TableNumber, t.TableId) AS TableRank
        FROM dbo.RestaurantTable t
        WHERE t.IsActive = 1
    )
    INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
    SELECT os.ShiftId, at.TableId
    FROM ActiveTables at
    JOIN @OpenShifts os
      ON os.ShiftRank = ((at.TableRank - 1) % @WaiterCount) + 1;

    COMMIT TRANSACTION;

    IF @ReturnResult = 1
        SELECT
            @WaiterCount AS WaiterCount,
            @TableCount AS TableCount,
            N'Столики автоматически распределены между открытыми сменами официантов.' AS Message;
END
GO

/*
 Возвращает только список столиков, без служебных result set.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_RebalanceOpenWaiterTables @ReturnResult = 0;

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        t.HallZone
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    WHERE w.UserId = @UserId
      AND u.IsActive = 1
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.8: исправлено получение и отображение автоматически назначенных столиков.';
GO
