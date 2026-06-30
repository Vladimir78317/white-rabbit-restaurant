/*
 White Rabbit v2.7 — гибкие смены и автоматическое распределение столиков.
 Выполните ОДИН РАЗ после обновления v2.6.

 Что изменено:
 1) Администратор по-прежнему может планировать смену официанту.
 2) Официант может открыть самостоятельную смену по приходу, если на это время
    у него нет назначенной смены. Такая смена действует до 23:00 текущего дня.
 3) Все открытые смены отображаются администратору.
 4) Столики автоматически распределяются по кругу между всеми официантами
    с открытой сменой. При открытии или закрытии смены распределение пересчитывается.
*/
USE WhiteRabbitRestaurant;
GO

IF COL_LENGTH('dbo.WaiterShift', 'IsWalkInShift') IS NULL
    ALTER TABLE dbo.WaiterShift
        ADD IsWalkInShift BIT NOT NULL
            CONSTRAINT DF_WaiterShift_IsWalkInShift DEFAULT (0) WITH VALUES;
GO

/* ====== 1. Автоматическое равномерное распределение активных столиков ====== */
CREATE OR ALTER PROCEDURE dbo.sp_RebalanceOpenWaiterTables
    @AdminUserId INT = NULL
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

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @OpenShifts TABLE
    (
        ShiftId INT NOT NULL PRIMARY KEY,
        ShiftRank INT NOT NULL
    );

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
      AND ws.ActualCloseAt IS NULL
      AND @Now < ws.PlannedEndAt;

    DECLARE @WaiterCount INT = (SELECT COUNT(*) FROM @OpenShifts);

    IF @WaiterCount = 0
    BEGIN
        SELECT 0 AS WaiterCount, 0 AS TableCount, N'Открытых смен нет: распределение столиков не требуется.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION;

    /* Меняются только назначения открытых смен. История закрытых и будущих смен сохраняется. */
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

    DECLARE @TableCount INT = (SELECT COUNT(*) FROM dbo.RestaurantTable WHERE IsActive = 1);

    COMMIT TRANSACTION;

    SELECT
        @WaiterCount AS WaiterCount,
        @TableCount AS TableCount,
        N'Столики автоматически распределены между открытыми сменами официантов.' AS Message;
END
GO

/* ====== 2. Открытие смены официантом: плановая или самостоятельная ====== */
CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @WaiterId INT;
    DECLARE @ShiftId INT;
    DECLARE @IsWalkInShift BIT = 0;

    SELECT @WaiterId = w.WaiterId
    FROM dbo.Waiter w
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE w.UserId = @UserId
      AND u.IsActive = 1
      AND r.RoleCode = 'WAITER';

    IF @WaiterId IS NULL
        THROW 51502, N'Открыть смену может только активный официант.', 1;

    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NOT NULL
    BEGIN
        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N'У вас уже открыта смена. Столики актуализированы автоматически.' AS Message;
        RETURN;
    END

    /* Сначала открываем подходящую смену, созданную администратором. */
    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = 'PLANNED'
      AND ws.ActualOpenAt IS NULL
      AND ws.PlannedStartAt <= @Now
      AND ws.PlannedEndAt > @Now
    ORDER BY ws.PlannedStartAt, ws.ShiftId;

    IF @ShiftId IS NOT NULL
    BEGIN
        UPDATE dbo.WaiterShift
        SET
            ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
            ActualOpenAt = @Now,
            ActualCloseAt = NULL,
            CloseReason = NULL,
            ClosedByUserId = NULL,
            WasClosedAutomatically = 0,
            IsWalkInShift = 0
        WHERE ShiftId = @ShiftId;

        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N'Назначенная смена открыта. Столики распределены автоматически.' AS Message;
        RETURN;
    END

    /* Если графика на текущее время нет, создаётся самостоятельная смена до 23:00. */
    IF CONVERT(TIME, @Now) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @Now) >= CONVERT(TIME, '23:00:00')
        THROW 51503, N'Самостоятельную смену можно открыть только в часы работы ресторана: с 09:00 до 23:00.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode = 'PLANNED'
          AND ws.ActualOpenAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
          AND ws.PlannedStartAt > @Now
    )
        THROW 51504, N'На сегодня уже есть назначенная смена. Откройте её в указанное время.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        WHERE ws.WaiterId = @WaiterId
          AND ws.IsWalkInShift = 1
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
    )
        THROW 51505, N'Самостоятельная смена этого официанта уже была создана сегодня.', 1;

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
        WasClosedAutomatically,
        IsWalkInShift
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        @Now,
        DATEADD(HOUR, 23, CAST(CONVERT(DATE, @Now) AS DATETIME2)),
        @Now,
        NULL,
        NULL,
        NULL,
        0,
        1
    );

    SET @ShiftId = SCOPE_IDENTITY();
    COMMIT TRANSACTION;

    EXEC dbo.sp_RebalanceOpenWaiterTables;
    SELECT @ShiftId AS ShiftId, N'Самостоятельная смена открыта до 23:00 и отображается у администратора. Столики распределены автоматически.' AS Message;
END
GO

/* ====== 3. Открытие плановой смены администратором ====== */
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
        THROW 51506, N'Открывать смены может только администратор.', 1;

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
        THROW 51507, N'Смена не найдена.', 1;
    IF @StatusCode <> 'PLANNED'
        THROW 51508, N'Открыть можно только запланированную смену.', 1;
    IF @Now < @PlannedStartAt OR @Now >= @PlannedEndAt
        THROW 51509, N'Открыть смену можно только в её назначенном временном интервале.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0,
        IsWalkInShift = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N'Смена официанта открыта администратором. Столики распределены автоматически.' AS Message;
END
GO

/* ====== 4. Закрытие смен: после закрытия распределение обновляется ====== */
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
        THROW 51510, N'У вас нет открытой смены.', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51511, N'При досрочном закрытии смены обязательно укажите причину.', 1;

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
        THROW 51512, N'Нельзя закрыть смену: есть незавершённые заказы. Завершите обслуживание и закройте счета.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @UserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables;
    SELECT N'Смена закрыта. Столики перераспределены между оставшимися официантами.' AS Message;
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
        THROW 51513, N'Закрывать смены может только администратор.', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT @PlannedEndAt = ws.PlannedEndAt, @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51514, N'Смена не найдена.', 1;
    IF @StatusCode <> 'OPEN'
        THROW 51515, N'Закрыть можно только открытую смену.', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51516, N'При досрочном закрытии смены обязательно укажите причину.', 1;

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
        THROW 51517, N'Нельзя закрыть смену: у официанта есть незавершённые заказы.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @AdminUserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N'Смена официанта закрыта администратором. Столики перераспределены автоматически.' AS Message;
END
GO

/* ====== 5. Планирование смен администратором без ручного назначения столиков ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(400) = NULL /* оставлен для совместимости со старым интерфейсом; не используется */
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51518, N'Время окончания смены должно быть позже времени начала.', 1;
    IF CONVERT(DATE, @PlannedStartAt) <> CONVERT(DATE, @PlannedEndAt)
       OR CONVERT(TIME, @PlannedStartAt) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @PlannedEndAt) > CONVERT(TIME, '23:00:00')
       OR DATEDIFF(MINUTE, @PlannedStartAt, @PlannedEndAt) > 840
        THROW 51519, N'Смена должна быть в пределах одного дня, времени работы ресторана 09:00–23:00 и длиться не более 14 часов.', 1;

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
        THROW 51520, N'Выбранный пользователь не является активным официантом.', 1;

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
        THROW 51521, N'У официанта уже есть пересекающаяся смена.', 1;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId, ShiftStatusId, PlannedStartAt, PlannedEndAt,
        ActualOpenAt, ActualCloseAt, CloseReason, ClosedByUserId,
        WasClosedAutomatically, IsWalkInShift
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt, @PlannedEndAt,
        NULL, NULL, NULL, NULL, 0, 0
    );

    SELECT SCOPE_IDENTITY() AS ShiftId,
           N'Смена запланирована. Столики будут автоматически распределены при её открытии.' AS Message;
END
GO

/* ====== 6. Отображение смен: виден тип и автоматические столики ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    SELECT
        ws.ShiftId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        CASE WHEN ws.IsWalkInShift = 1 THEN N'Самостоятельная' ELSE N'По графику' END AS [Тип смены],
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
        ws.ShiftId, u.LastName, u.FirstName, ws.IsWalkInShift,
        ws.PlannedStartAt, ws.PlannedEndAt, ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY ws.PlannedStartAt DESC, ws.ShiftId DESC;
END
GO

/* ====== 7. Получение столиков официанта: всегда с актуальным распределением ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_RebalanceOpenWaiterTables;

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
      AND @Now < ws.PlannedEndAt
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.7: самостоятельные смены и автоматическое распределение столиков добавлены.';
GO
