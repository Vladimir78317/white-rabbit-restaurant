/*
 White Rabbit v2.0 — исправление бизнес-логики.
 Запустите ОДИН РАЗ в SSMS после ранее применённых обновлений v1.8 / v1.9.

 Исправления:
 1) Официант не может создать заказ без фактически открытой смены.
 2) Официант видит только столики, закреплённые за ним в открытой смене.
 3) Гостей в заказе нельзя указать больше вместимости столика.
 4) Администратор может удалить сотрудника из рабочего списка без удаления истории.
 5) Процедура бронирования от имени официанта удаляется.
*/
USE WhiteRabbitRestaurant;
GO

IF COL_LENGTH('dbo.WaiterShift', 'ActualCloseAt') IS NULL
BEGIN
    ALTER TABLE dbo.WaiterShift ADD ActualCloseAt DATETIME2 NULL;
END
GO

/* Бронирование столиков выполняют клиент и администратор. Официанту этот сценарий больше недоступен. */
IF OBJECT_ID(N'dbo.sp_CreateReservationForWaiter', N'P') IS NOT NULL
    DROP PROCEDURE dbo.sp_CreateReservationForWaiter;
GO

/*
 Возвращает столики только при открытой смене.
 Условие ActualOpenAt не позволяет использовать плановую, но не открытую смену.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

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
      AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

/*
 Заказ официанта можно создать ТОЛЬКО при открытой смене и только на закреплённый столик.
 Вместимость проверяется на уровне базы, поэтому её невозможно обойти через интерфейс.
*/
CREATE OR ALTER PROCEDURE dbo.sp_CreateOrderForWaiter
    @WaiterUserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51201, N'Количество гостей должно быть не меньше одного.', 1;

    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT
        @TableId = t.TableId,
        @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @TableId IS NULL
        THROW 51202, N'Столик не найден или отключён.', 1;

    IF @GuestCount > @SeatsCount
        THROW 51203, N'Количество гостей превышает вместимость выбранного столика.', 1;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
        WHERE w.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND a.TableId = @TableId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51204, N'Сначала откройте запланированную смену. Без открытой смены заказ создать нельзя.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED')
    )
        THROW 51205, N'У выбранного столика уже есть активный заказ.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = @TableId
          AND rs.StatusCode = 'ACTIVE'
          AND SYSDATETIME() >= r.StartAt
          AND SYSDATETIME() < r.EndAt
    )
        THROW 51206, N'Столик забронирован на текущее время.', 1;

    INSERT INTO dbo.CustomerOrder
    (
        TableId,
        WaiterShiftId,
        OrderStatusId,
        ChannelCode,
        GuestCount
    )
    VALUES
    (
        @TableId,
        @ShiftId,
        (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'DRAFT'),
        'WAITER',
        @GuestCount
    );

    SELECT
        SCOPE_IDENTITY() AS OrderId,
        N'Заказ создан. Можно добавлять блюда.' AS Message;
END
GO

/* Такая же проверка вместимости нужна для заказа клиента через приложение. */
CREATE OR ALTER PROCEDURE dbo.sp_CreateClientAppOrder
    @UserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51207, N'Количество гостей должно быть не меньше одного.', 1;

    DECLARE @ClientId INT =
    (
        SELECT ClientId
        FROM dbo.Client
        WHERE UserId = @UserId
    );

    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT
        @TableId = t.TableId,
        @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @ClientId IS NULL
        THROW 51208, N'Клиент не найден.', 1;

    IF @TableId IS NULL
        THROW 51209, N'Столик не найден или отключён.', 1;

    IF @GuestCount > @SeatsCount
        THROW 51210, N'Количество гостей превышает вместимость выбранного столика.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED')
    )
        THROW 51211, N'Этот столик уже занят.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = @TableId
          AND rs.StatusCode = 'ACTIVE'
          AND SYSDATETIME() >= r.StartAt
          AND SYSDATETIME() < r.EndAt
    )
        THROW 51212, N'Столик забронирован на текущее время.', 1;

    INSERT INTO dbo.CustomerOrder
    (
        ClientId,
        TableId,
        OrderStatusId,
        ChannelCode,
        GuestCount
    )
    VALUES
    (
        @ClientId,
        @TableId,
        (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'DRAFT'),
        'CLIENT_APP',
        @GuestCount
    );

    SELECT
        SCOPE_IDENTITY() AS OrderId,
        N'Корзина создана. Добавьте блюда и отправьте заказ на кухню.' AS Message;
END
GO

/* В рабочем списке администратора видны только действующие сотрудники. */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminEmployees
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        u.Login AS [Логин],
        CONCAT(u.LastName, N' ', u.FirstName) AS [Сотрудник],
        r.RoleName AS [Роль],
        ISNULL(u.Phone, N'—') AS [Телефон]
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE r.RoleCode IN ('WAITER', 'KITCHEN')
      AND u.IsActive = 1
    ORDER BY r.RoleName, u.LastName, u.FirstName;
END
GO

/*
 «Удаление» сотрудника безопасное: учётная запись отключается и пропадает из рабочего списка.
 История заказов и смен остаётся целой, поэтому внешние ключи не нарушаются.
*/
CREATE OR ALTER PROCEDURE dbo.sp_AdminDeactivateEmployee
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @RoleCode VARCHAR(20);
    DECLARE @WaiterId INT;
    DECLARE @FullName NVARCHAR(130);

    SELECT
        @RoleCode = r.RoleCode,
        @FullName = CONCAT(u.LastName, N' ', u.FirstName)
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE u.UserId = @UserId
      AND u.IsActive = 1;

    IF @RoleCode IS NULL
        THROW 51213, N'Сотрудник не найден или уже удалён из рабочего списка.', 1;

    IF @RoleCode NOT IN ('WAITER', 'KITCHEN')
        THROW 51214, N'Удалять можно только официанта или сотрудника кухни.', 1;

    SELECT @WaiterId = WaiterId
    FROM dbo.Waiter
    WHERE UserId = @UserId;

    IF @WaiterId IS NOT NULL
       AND EXISTS
       (
           SELECT 1
           FROM dbo.WaiterShift ws
           JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
           WHERE ws.WaiterId = @WaiterId
             AND ss.StatusCode = 'OPEN'
       )
        THROW 51215, N'Нельзя удалить официанта с открытой сменой. Сначала закройте смену.', 1;

    BEGIN TRANSACTION;

    /* Плановые смены сотрудника больше не участвуют в графике. */
    IF @WaiterId IS NOT NULL
    BEGIN
        UPDATE ws
        SET
            ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
            ActualCloseAt = COALESCE(ws.ActualCloseAt, SYSDATETIME())
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode = 'PLANNED';
    END

    UPDATE dbo.AppUser
    SET IsActive = 0
    WHERE UserId = @UserId;

    COMMIT TRANSACTION;

    SELECT CONCAT(N'Сотрудник «', @FullName, N'» удалён из рабочего списка.') AS Message;
END
GO

PRINT N'White Rabbit v2.0: ограничения смен, вместимости и удаление сотрудников добавлены.';
GO
