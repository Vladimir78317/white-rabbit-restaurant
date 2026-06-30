/*
 White Rabbit v3.0 — общее обновление с v2.8 до v3.0.
 Выполняйте один раз в SSMS для существующей базы WhiteRabbitRestaurant версии v2.8.
 Скрипт включает визуальные схемы v2.9, фильтры смен и защиту броней v3.0.
*/

/*
 White Rabbit v2.9 — интерактивные схемы столиков, брони по дате и фильтры смен.
 Выполните ОДИН РАЗ после SQL_Update_v2_8_Waiter_Table_Assignment_Fix.sql.

 Добавлено:
 1. Схема столиков для администратора на выбранную дату.
 2. Просмотр всех броней выбранного столика за выбранный день.
 3. Фильтрация смен администратора по дате, официанту, статусу и типу.
*/
USE WhiteRabbitRestaurant;
GO

/* Возвращает все столики и количество активных броней, пересекающих выбранный день. */
CREATE OR ALTER PROCEDURE dbo.sp_GetReservationDayTableMap
    @ReservationDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @DayStart DATETIME2 = CAST(@ReservationDate AS DATETIME2);
    DECLARE @DayEnd DATETIME2 = DATEADD(DAY, 1, @DayStart);

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        t.HallZone,
        ISNULL(dayReservations.ReservationCount, 0) AS ReservationCount,
        dayReservations.FirstReservationAt,
        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.CustomerOrder o
                JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
                WHERE o.TableId = t.TableId
                  AND os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
            ) THEN N'Занят заказом'
            WHEN ISNULL(dayReservations.ReservationCount, 0) > 0 THEN N'Есть брони'
            ELSE N'Свободен'
        END AS DayStatus
    FROM dbo.RestaurantTable t
    OUTER APPLY
    (
        SELECT
            COUNT(*) AS ReservationCount,
            MIN(r.StartAt) AS FirstReservationAt
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = t.TableId
          AND rs.StatusCode = 'ACTIVE'
          AND r.StartAt < @DayEnd
          AND r.EndAt > @DayStart
    ) dayReservations
    WHERE t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

/* Все активные брони выбранного столика, которые пересекают выбранный день. */
CREATE OR ALTER PROCEDURE dbo.sp_GetReservationsByTableAndDate
    @ReservationDate DATE,
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.RestaurantTable WHERE TableId = @TableId AND IsActive = 1)
        THROW 51701, N'Выбранный столик не найден или отключён.', 1;

    DECLARE @DayStart DATETIME2 = CAST(@ReservationDate AS DATETIME2);
    DECLARE @DayEnd DATETIME2 = DATEADD(DAY, 1, @DayStart);

    SELECT
        r.ReservationId,
        t.TableNumber AS [Столик],
        c.FullName AS [Клиент],
        c.Phone AS [Телефон],
        r.StartAt AS [Начало],
        r.EndAt AS [Конец],
        r.GuestCount AS [Гостей],
        rs.StatusName AS [Статус]
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
    JOIN dbo.Client c ON c.ClientId = r.ClientId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE rt.TableId = @TableId
      AND rs.StatusCode = 'ACTIVE'
      AND r.StartAt < @DayEnd
      AND r.EndAt > @DayStart
    ORDER BY r.StartAt, r.ReservationId;
END
GO

/* Фильтр графика смен администратора. Пустые параметры означают «все значения». */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShiftsFiltered
    @ShiftDate DATE = NULL,
    @WaiterUserId INT = NULL,
    @StatusCode VARCHAR(20) = NULL,
    @ShiftType VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    IF @StatusCode IS NOT NULL AND @StatusCode NOT IN ('PLANNED', 'OPEN', 'CLOSED')
        THROW 51702, N'Указан неизвестный статус смены.', 1;

    IF @ShiftType IS NOT NULL AND @ShiftType NOT IN ('SCHEDULED', 'WALKIN')
        THROW 51703, N'Указан неизвестный тип смены.', 1;

    SELECT
        ws.ShiftId,
        u.UserId AS WaiterUserId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        CASE WHEN ws.IsWalkInShift = 1 THEN N'Самостоятельная' ELSE N'По графику' END AS [Тип смены],
        CASE WHEN ws.IsWalkInShift = 1 THEN 'WALKIN' ELSE 'SCHEDULED' END AS ShiftTypeCode,
        ws.PlannedStartAt AS [Начало по графику],
        ws.PlannedEndAt AS [Конец по графику],
        ws.ActualOpenAt AS [Фактическое открытие],
        ws.ActualCloseAt AS [Фактическое закрытие],
        ss.StatusName AS [Статус],
        ss.StatusCode,
        ISNULL(ws.CloseReason, N'—') AS [Причина закрытия],
        CASE WHEN ws.WasClosedAutomatically = 1 THEN N'Да' ELSE N'Нет' END AS [Автозакрытие],
        ISNULL(STRING_AGG(CONCAT(N'№', t.TableNumber), N', '), N'—') AS [Столики]
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    LEFT JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    LEFT JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    WHERE (@ShiftDate IS NULL OR CONVERT(DATE, COALESCE(ws.ActualOpenAt, ws.PlannedStartAt)) = @ShiftDate)
      AND (@WaiterUserId IS NULL OR u.UserId = @WaiterUserId)
      AND (@StatusCode IS NULL OR ss.StatusCode = @StatusCode)
      AND (@ShiftType IS NULL
           OR (@ShiftType = 'WALKIN' AND ws.IsWalkInShift = 1)
           OR (@ShiftType = 'SCHEDULED' AND ws.IsWalkInShift = 0))
    GROUP BY
        ws.ShiftId, u.UserId, u.LastName, u.FirstName, ws.IsWalkInShift,
        ws.PlannedStartAt, ws.PlannedEndAt, ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ss.StatusCode, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY COALESCE(ws.ActualOpenAt, ws.PlannedStartAt) DESC, ws.ShiftId DESC;
END
GO

/* Сохраняется прежнее имя процедуры, чтобы старые версии интерфейса также работали. */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_GetAdminWaiterShiftsFiltered;
END
GO

PRINT N'White Rabbit v2.9: добавлены интерактивные схемы столиков, брони по дате и фильтры смен.';
GO

/*
 White Rabbit v3.0 — защита броней клиентов и визуальные брони официанта.
 Выполните ОДИН РАЗ после SQL_Update_v2_9_Visual_Table_Maps_And_Shift_Filters.sql.

 Добавлено:
 1. Клиент получает через SQL только собственные брони.
 2. Клиент может отменить только свою бронь; администратор может отменить любую.
 3. Официант видит свои назначенные столики карточками и по нажатию получает
    брони выбранного столика на выбранную дату.
 4. Данные бронирований официанта ограничены только столиками его открытой смены.
*/
USE WhiteRabbitRestaurant;
GO

/*
 Возвращает только активные брони текущего клиента.
 Проверка роли выполняется в базе данных, а не только в интерфейсе.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetClientReservations
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole role ON role.RoleId = u.RoleId
        WHERE u.UserId = @UserId
          AND u.IsActive = 1
          AND role.RoleCode = 'CLIENT'
    )
        THROW 51801, N'Просматривать личные брони может только активный клиент.', 1;

    SELECT
        r.ReservationId,
        r.StartAt AS [Начало],
        r.EndAt AS [Конец],
        r.GuestCount AS [Гостей],
        rs.StatusName AS [Статус],
        STRING_AGG(CONVERT(NVARCHAR(10), t.TableNumber), N', ') AS [Столики]
    FROM dbo.Reservation r
    JOIN dbo.Client c ON c.ClientId = r.ClientId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
    WHERE c.UserId = @UserId
      AND rs.StatusCode = 'ACTIVE'
    GROUP BY
        r.ReservationId,
        r.StartAt,
        r.EndAt,
        r.GuestCount,
        rs.StatusName
    ORDER BY r.StartAt DESC, r.ReservationId DESC;
END;
GO

/*
 Отмена брони с обязательной проверкой владельца.
 Клиент отменяет только бронь, связанную со своим Client.UserId.
 Администратор сохраняет право отменить любую активную бронь.
*/
CREATE OR ALTER PROCEDURE dbo.sp_CancelReservation
    @ReservationId INT,
    @RequesterUserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RoleCode VARCHAR(30);

    SELECT @RoleCode = role.RoleCode
    FROM dbo.AppUser u
    JOIN dbo.AppRole role ON role.RoleId = u.RoleId
    WHERE u.UserId = @RequesterUserId
      AND u.IsActive = 1;

    IF @RoleCode IS NULL
        THROW 51802, N'Пользователь не найден или его учетная запись отключена.', 1;

    IF @RoleCode NOT IN ('CLIENT', 'ADMIN')
        THROW 51803, N'Отменять бронирования могут только клиент-владелец или администратор.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE r.ReservationId = @ReservationId
          AND rs.StatusCode = 'ACTIVE'
    )
        THROW 51804, N'Активная бронь с указанным номером не найдена.', 1;

    IF @RoleCode = 'CLIENT'
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.Reservation r
           JOIN dbo.Client c ON c.ClientId = r.ClientId
           WHERE r.ReservationId = @ReservationId
             AND c.UserId = @RequesterUserId
       )
        THROW 51805, N'Клиент может отменить только собственную бронь.', 1;

    UPDATE dbo.Reservation
    SET ReservationStatusId =
    (
        SELECT ReservationStatusId
        FROM dbo.ReservationStatus
        WHERE StatusCode = 'CANCELLED'
    )
    WHERE ReservationId = @ReservationId;

    SELECT N'Бронь успешно отменена.' AS Message;
END;
GO

/*
 Карточки назначенных текущему официанту столиков на выбранную дату.
 Для каждого столика возвращается количество активных броней за день.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterReservationDayTableMap
    @WaiterUserId INT,
    @ReservationDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole role ON role.RoleId = u.RoleId
        JOIN dbo.Waiter w ON w.UserId = u.UserId AND w.IsActive = 1
        WHERE u.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND role.RoleCode = 'WAITER'
    )
        THROW 51806, N'Пользователь не является активным официантом.', 1;

    EXEC dbo.sp_RebalanceOpenWaiterTables @ReturnResult = 0;

    DECLARE @DayStart DATETIME2 = CAST(@ReservationDate AS DATETIME2);
    DECLARE @DayEnd DATETIME2 = DATEADD(DAY, 1, @DayStart);

    ;WITH AssignedTables AS
    (
        SELECT DISTINCT t.TableId, t.TableNumber, t.SeatsCount, t.HallZone
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment assignment ON assignment.ShiftId = ws.ShiftId
        JOIN dbo.RestaurantTable t ON t.TableId = assignment.TableId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND t.IsActive = 1
    )
    SELECT
        assigned.TableId,
        assigned.TableNumber,
        assigned.SeatsCount,
        assigned.HallZone,
        ISNULL(dayReservations.ReservationCount, 0) AS ReservationCount,
        dayReservations.FirstReservationAt,
        CASE
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.CustomerOrder orderHeader
                JOIN dbo.OrderStatus orderStatus ON orderStatus.OrderStatusId = orderHeader.OrderStatusId
                WHERE orderHeader.TableId = assigned.TableId
                  AND orderStatus.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
            ) THEN N'Занят заказом'
            WHEN ISNULL(dayReservations.ReservationCount, 0) > 0 THEN N'Есть брони'
            ELSE N'Свободен'
        END AS DayStatus
    FROM AssignedTables assigned
    OUTER APPLY
    (
        SELECT
            COUNT(*) AS ReservationCount,
            MIN(r.StartAt) AS FirstReservationAt
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = assigned.TableId
          AND rs.StatusCode = 'ACTIVE'
          AND r.StartAt < @DayEnd
          AND r.EndAt > @DayStart
    ) dayReservations
    ORDER BY assigned.TableNumber;
END;
GO

/*
 Брони выбранного столика за выбранный день для официанта.
 Проверяется, что столик назначен этому официанту в его открытой смене.
 Телефон клиента не возвращается, так как для работы с рассадкой достаточно имени и числа гостей.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterReservationsByTableAndDate
    @WaiterUserId INT,
    @ReservationDate DATE,
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment assignment ON assignment.ShiftId = ws.ShiftId
        JOIN dbo.RestaurantTable t ON t.TableId = assignment.TableId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND t.TableId = @TableId
          AND t.IsActive = 1
    )
        THROW 51807, N'Выбранный столик не назначен текущему официанту.', 1;

    DECLARE @DayStart DATETIME2 = CAST(@ReservationDate AS DATETIME2);
    DECLARE @DayEnd DATETIME2 = DATEADD(DAY, 1, @DayStart);

    SELECT
        r.ReservationId,
        t.TableNumber AS [Столик],
        c.FullName AS [Клиент],
        r.StartAt AS [Начало],
        r.EndAt AS [Конец],
        r.GuestCount AS [Гостей],
        rs.StatusName AS [Статус]
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
    JOIN dbo.Client c ON c.ClientId = r.ClientId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE rt.TableId = @TableId
      AND rs.StatusCode = 'ACTIVE'
      AND r.StartAt < @DayEnd
      AND r.EndAt > @DayStart
    ORDER BY r.StartAt, r.ReservationId;
END;
GO

PRINT N'White Rabbit v3.0: защищены личные брони клиента и добавлены брони назначенных столиков официанта.';
GO

PRINT N'Общее обновление White Rabbit с v2.8 до v3.0 успешно выполнено.';
GO
