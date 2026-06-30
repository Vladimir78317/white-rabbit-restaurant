/*
 White Rabbit v2.4 — статусы заказов и полный контроль смен.
 Выполните ОДИН РАЗ в SSMS после обновлений v2.0, v2.1 и v2.3.

 Добавлено:
 1) Просмотр статусов заказов: администратор — все заказы, клиент — свои заказы.
 2) Администратор может открыть и закрыть выбранную смену официанта.
 3) Смена автоматически закрывается по PlannedEndAt, если по ней нет незавершённых заказов.
 4) При раннем закрытии смены причина обязательна.
 5) Официант открывает только назначенную смену в её плановом временном интервале.
 6) Смену нельзя назначить «на год»: только в пределах одного дня, с 09:00 до 23:00,
    длительностью не более 14 часов.
*/
USE WhiteRabbitRestaurant;
GO

/* ====== 1. Поля аудита закрытия смены ====== */
IF COL_LENGTH('dbo.WaiterShift', 'CloseReason') IS NULL
    ALTER TABLE dbo.WaiterShift ADD CloseReason NVARCHAR(500) NULL;
GO

IF COL_LENGTH('dbo.WaiterShift', 'ClosedByUserId') IS NULL
    ALTER TABLE dbo.WaiterShift ADD ClosedByUserId INT NULL;
GO

IF COL_LENGTH('dbo.WaiterShift', 'WasClosedAutomatically') IS NULL
    ALTER TABLE dbo.WaiterShift
        ADD WasClosedAutomatically BIT NOT NULL
            CONSTRAINT DF_WaiterShift_WasClosedAutomatically DEFAULT (0) WITH VALUES;
GO

/* ====== 2. Автоматическое закрытие по окончании планового времени ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AutoCloseExpiredWaiterShifts
    @ReturnResult BIT = 1
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @Now DATETIME2 = SYSDATETIME();

    /*
      Не закрываем смену автоматически, если есть незавершённый заказ.
      Это защищает обслуживание и оплату: после завершения заказа администратор
      или официант сможет закрыть смену вручную с сохранением причины.
    */
    UPDATE ws
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = CASE
            WHEN ss.StatusCode = 'PLANNED' THEN N'Автоматически закрыта: смена не была открыта до окончания планового времени.'
            ELSE N'Автоматически закрыта по окончании планового времени.'
        END,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 1
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ss.StatusCode IN ('OPEN', 'PLANNED')
      AND ws.ActualCloseAt IS NULL
      AND ws.PlannedEndAt <= @Now
      AND
      (
          ss.StatusCode = 'PLANNED'
          OR NOT EXISTS
          (
          SELECT 1
          FROM dbo.CustomerOrder o
          JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
          WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
            AND
            (
                o.WaiterShiftId = ws.ShiftId
                OR
                (
                    o.WaiterShiftId IS NULL
                    AND EXISTS
                    (
                        SELECT 1
                        FROM dbo.WaiterTableAssignment assignment_check
                        WHERE assignment_check.ShiftId = ws.ShiftId
                          AND assignment_check.TableId = o.TableId
                    )
                )
            )
          )
      );

    DECLARE @ClosedCount INT = @@ROWCOUNT;

    IF @ReturnResult = 1
    BEGIN
        SELECT
            @ClosedCount AS ClosedCount,
            CASE
                WHEN @ClosedCount = 0 THEN N'Смен для автоматического закрытия нет.'
                ELSE CONCAT(N'Автоматически закрыто смен: ', @ClosedCount, N'.')
            END AS Message;
    END
END
GO

/* ====== 3. Открытие смены официантом только в назначенное время ====== */
CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @ShiftId INT;

    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE w.UserId = @UserId
      AND u.IsActive = 1
      AND ss.StatusCode = 'PLANNED'
      AND ws.ActualOpenAt IS NULL
      AND ws.PlannedStartAt <= @Now
      AND ws.PlannedEndAt > @Now
    ORDER BY ws.PlannedStartAt, ws.ShiftId;

    IF @ShiftId IS NULL
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.WaiterShift ws
            JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
            JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
            WHERE w.UserId = @UserId
              AND ss.StatusCode = 'PLANNED'
              AND ws.ActualOpenAt IS NULL
              AND @Now < ws.PlannedStartAt
        )
            THROW 51401, N'Смену нельзя открыть раньше назначенного времени.', 1;

        THROW 51402, N'Нет доступной запланированной смены на текущее время. Открыть смену на произвольный срок нельзя.', 1;
    END

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT @ShiftId AS ShiftId, N'Смена успешно открыта.' AS Message;
END
GO

/* ====== 4. Закрытие смены официантом ====== */
CREATE OR ALTER PROCEDURE dbo.sp_CloseCurrentWaiterShift
    @UserId INT,
    @Reason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @ShiftId INT;
    DECLARE @PlannedEndAt DATETIME2;

    SELECT TOP (1)
        @ShiftId = ws.ShiftId,
        @PlannedEndAt = ws.PlannedEndAt
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE w.UserId = @UserId
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NULL
        THROW 51403, N'У вас нет открытой смены.', 1;

    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51404, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
          AND
          (
              o.WaiterShiftId = @ShiftId
              OR
              (
                  o.WaiterShiftId IS NULL
                  AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.WaiterTableAssignment assignment_check
                      WHERE assignment_check.ShiftId = @ShiftId
                        AND assignment_check.TableId = o.TableId
                  )
              )
          )
    )
        THROW 51405, N'Нельзя закрыть смену: есть незавершённые заказы. Завершите обслуживание и закройте счета.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @UserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена закрыта.' AS Message;
END
GO

/* ====== 5. Управление сменами администратором ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminOpenWaiterShift
    @AdminUserId INT,
    @ShiftId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @AdminUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51406, N'Открывать смены может только администратор.', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedStartAt DATETIME2;
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT
        @PlannedStartAt = ws.PlannedStartAt,
        @PlannedEndAt = ws.PlannedEndAt,
        @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51407, N'Смена не найдена.', 1;

    IF @StatusCode <> 'PLANNED'
        THROW 51408, N'Открыть можно только запланированную смену.', 1;

    IF @Now < @PlannedStartAt OR @Now >= @PlannedEndAt
        THROW 51409, N'Открыть смену можно только в её назначенном временном интервале.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена официанта открыта администратором.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AdminCloseWaiterShift
    @AdminUserId INT,
    @ShiftId INT,
    @Reason NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @AdminUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51410, N'Закрывать смены может только администратор.', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT
        @PlannedEndAt = ws.PlannedEndAt,
        @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51411, N'Смена не найдена.', 1;

    IF @StatusCode <> 'OPEN'
        THROW 51412, N'Закрыть можно только открытую смену.', 1;

    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51413, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
          AND
          (
              o.WaiterShiftId = @ShiftId
              OR
              (
                  o.WaiterShiftId IS NULL
                  AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.WaiterTableAssignment assignment_check
                      WHERE assignment_check.ShiftId = @ShiftId
                        AND assignment_check.TableId = o.TableId
                  )
              )
          )
    )
        THROW 51414, N'Нельзя закрыть смену: у официанта есть незавершённые заказы.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @AdminUserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена официанта закрыта администратором.' AS Message;
END
GO

/* ====== 6. Планирование смен: защита от смен «на год» ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51415, N'Время окончания смены должно быть позже времени начала.', 1;

    IF CONVERT(DATE, @PlannedStartAt) <> CONVERT(DATE, @PlannedEndAt)
       OR CONVERT(TIME, @PlannedStartAt) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @PlannedEndAt) > CONVERT(TIME, '23:00:00')
       OR DATEDIFF(MINUTE, @PlannedStartAt, @PlannedEndAt) > 840
        THROW 51416, N'Смена должна быть в пределах одного дня, времени работы ресторана 09:00–23:00 и длиться не более 14 часов.', 1;

    DECLARE @WaiterId INT =
    (
        SELECT w.WaiterId
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE w.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'WAITER'
    );

    IF @WaiterId IS NULL
        THROW 51417, N'Выбранный пользователь не является активным официантом.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51418, N'У официанта уже есть пересекающаяся смена.', 1;

    DECLARE @Tables TABLE (TableId INT NOT NULL PRIMARY KEY);

    INSERT INTO @Tables (TableId)
    SELECT DISTINCT t.TableId
    FROM STRING_SPLIT(@TableNumbers, ',') value_list
    JOIN dbo.RestaurantTable t
      ON t.TableNumber = TRY_CONVERT(INT, LTRIM(RTRIM(value_list.value)))
     AND t.IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM @Tables)
        THROW 51419, N'Укажите хотя бы один действующий столик.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
        JOIN @Tables nt ON nt.TableId = a.TableId
        WHERE ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51420, N'Один из выбранных столиков уже закреплён за другим официантом в пересекающуюся смену.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId,
        ShiftStatusId,
        PlannedStartAt,
        PlannedEndAt,
        ActualOpenAt,
        ActualCloseAt,
        CloseReason,
        ClosedByUserId,
        WasClosedAutomatically
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt,
        @PlannedEndAt,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    );

    DECLARE @ShiftId INT = SCOPE_IDENTITY();

    INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
    SELECT @ShiftId, TableId
    FROM @Tables;

    COMMIT TRANSACTION;

    SELECT @ShiftId AS ShiftId, N'Смена создана, столики закреплены.' AS Message;
END
GO

/* ====== 7. Вывод графика и статусов заказов ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    SELECT
        ws.ShiftId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        ws.PlannedStartAt AS [Начало по графику],
        ws.PlannedEndAt AS [Конец по графику],
        ws.ActualOpenAt AS [Фактическое открытие],
        ws.ActualCloseAt AS [Фактическое закрытие],
        ss.StatusName AS [Статус],
        ISNULL(ws.CloseReason, N'—') AS [Причина закрытия],
        CASE WHEN ws.WasClosedAutomatically = 1 THEN N'Да' ELSE N'Нет' END AS [Автозакрытие],
        ISNULL(STRING_AGG(CONCAT(N'№', t.TableNumber), N', '), N'—') AS [Столики]
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    LEFT JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    LEFT JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    GROUP BY
        ws.ShiftId, u.LastName, u.FirstName,
        ws.PlannedStartAt, ws.PlannedEndAt,
        ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY ws.PlannedStartAt DESC, ws.ShiftId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AdminGetOrderStatuses
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        os.StatusName AS [Статус заказа],
        o.ChannelCode AS [Источник],
        CONCAT(ISNULL(c.FullName, N'Гость'), N'') AS [Клиент],
        CONCAT(ISNULL(wu.LastName, N'Не назначен'), N' ', ISNULL(wu.FirstName, N'')) AS [Официант],
        o.CreatedAt AS [Создан],
        o.FinalizedAt AS [Отправлен на кухню],
        CASE
            WHEN b.BillId IS NULL THEN N'Не пробит'
            WHEN b.IsPaid = 1 THEN N'Оплачен'
            WHEN b.IssuedAt IS NOT NULL THEN N'Ожидает оплаты'
            ELSE N'Не пробит'
        END AS [Состояние счёта],
        b.PaidAt AS [Оплачен в]
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Client c ON c.ClientId = o.ClientId
    LEFT JOIN dbo.WaiterShift ws ON ws.ShiftId = o.WaiterShiftId
    LEFT JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    LEFT JOIN dbo.AppUser wu ON wu.UserId = w.UserId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    ORDER BY o.CreatedAt DESC, o.OrderId DESC;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetClientOrderStatuses
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ClientId INT = (SELECT ClientId FROM dbo.Client WHERE UserId = @UserId);

    IF @ClientId IS NULL
        THROW 51421, N'Клиент не найден.', 1;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        os.StatusName AS [Статус заказа],
        o.CreatedAt AS [Создан],
        o.FinalizedAt AS [Отправлен на кухню],
        CASE
            WHEN b.BillId IS NULL THEN N'Не пробит'
            WHEN b.IsPaid = 1 THEN N'Оплачен'
            WHEN b.IssuedAt IS NOT NULL THEN N'Ожидает оплаты'
            ELSE N'Не пробит'
        END AS [Счёт]
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    WHERE o.ClientId = @ClientId
    ORDER BY o.CreatedAt DESC, o.OrderId DESC;
END
GO

/* После окончания времени смены столики официанту больше не выдаются для новых заказов. */
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();

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
      AND @Now >= ws.PlannedStartAt
      AND @Now < ws.PlannedEndAt
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.4: статусы заказов и безопасное управление сменами добавлены.';
GO
