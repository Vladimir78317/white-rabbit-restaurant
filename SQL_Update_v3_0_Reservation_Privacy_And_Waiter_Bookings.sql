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
