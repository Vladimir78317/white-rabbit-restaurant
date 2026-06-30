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
