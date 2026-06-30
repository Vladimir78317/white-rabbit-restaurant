/*
  White Rabbit v2.1 — цикл обслуживания, счёт и оплата.
  Выполните ОДИН РАЗ в SSMS после обновления v2.0.

  Новый порядок:
  1. Кухня передаёт готовый заказ официанту: статус «Принят на выдачу».
  2. Официант нажимает «Принести заказ»: статус «Выдан клиенту».
  3. Официант нажимает «Пробить счёт».
  4. После оплаты нажимает «Закрыть счёт».
  5. Только после закрытия счёта заказ завершается, а столик становится свободным.
*/
USE WhiteRabbitRestaurant;
GO

/* Статусы, требуемые для завершения обслуживания. */
IF NOT EXISTS (SELECT 1 FROM dbo.OrderStatus WHERE StatusCode = 'ISSUED')
BEGIN
    INSERT INTO dbo.OrderStatus (StatusCode, StatusName)
    VALUES ('ISSUED', N'Выдан клиенту');
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.OrderStatus WHERE StatusCode = 'COMPLETED')
BEGIN
    INSERT INTO dbo.OrderStatus (StatusCode, StatusName)
    VALUES ('COMPLETED', N'Завершён');
END
GO

IF NOT EXISTS (SELECT 1 FROM dbo.ReservationStatus WHERE StatusCode = 'COMPLETED')
BEGIN
    INSERT INTO dbo.ReservationStatus (StatusCode, StatusName)
    VALUES ('COMPLETED', N'Завершена');
END
GO

/* Храним момент пробития и оплаты счёта, способ оплаты и номер чека. */
IF COL_LENGTH('dbo.Bill', 'IssuedAt') IS NULL
    ALTER TABLE dbo.Bill ADD IssuedAt DATETIME2 NULL;
GO

IF COL_LENGTH('dbo.Bill', 'PaidAt') IS NULL
    ALTER TABLE dbo.Bill ADD PaidAt DATETIME2 NULL;
GO

IF COL_LENGTH('dbo.Bill', 'PaymentMethod') IS NULL
    ALTER TABLE dbo.Bill ADD PaymentMethod NVARCHAR(30) NULL;
GO

IF COL_LENGTH('dbo.Bill', 'ReceiptNumber') IS NULL
    ALTER TABLE dbo.Bill ADD ReceiptNumber NVARCHAR(50) NULL;
GO

IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'UX_Bill_ReceiptNumber' AND object_id = OBJECT_ID('dbo.Bill'))
    CREATE UNIQUE INDEX UX_Bill_ReceiptNumber ON dbo.Bill(ReceiptNumber) WHERE ReceiptNumber IS NOT NULL;
GO

/*
  После отправки на кухню счёт больше не создаётся автоматически.
  Он появляется только после действия официанта «Пробить счёт».
*/
CREATE OR ALTER PROCEDURE dbo.sp_FinalizeOrder
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE OrderId = @OrderId)
        THROW 51301, N'Нельзя отправить на кухню пустой заказ.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND s.StatusCode = 'DRAFT'
    )
        THROW 51302, N'Заказ уже отправлен на кухню или не найден.', 1;

    UPDATE dbo.CustomerOrder
    SET
        OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'PLACED'),
        FinalizedAt = SYSDATETIME()
    WHERE OrderId = @OrderId;

    SELECT N'Заказ отправлен на кухню. Счёт будет пробит официантом после выдачи заказа.' AS Message;
END
GO

/* Активные статусы: пока заказ не оплачен, столик нельзя использовать повторно. */
CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableTables
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @Now DATETIME2 = SYSDATETIME();

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        t.HallZone
    FROM dbo.RestaurantTable t
    WHERE t.IsActive = 1
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.CustomerOrder o
          JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
          WHERE o.TableId = t.TableId
            AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.Reservation r
          JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
          JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
          WHERE rt.TableId = t.TableId
            AND rs.StatusCode = 'ACTIVE'
            AND @Now >= r.StartAt
            AND @Now < r.EndAt
      )
    ORDER BY t.TableNumber;
END
GO

CREATE OR ALTER VIEW dbo.vw_TableScheme
AS
SELECT
    t.TableId,
    t.TableNumber AS [№ столика],
    t.SeatsCount AS [Мест],
    t.HallZone AS [Зона],
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM dbo.CustomerOrder o
            JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
            WHERE o.TableId = t.TableId
              AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
        ) THEN N'Занят заказом'
        WHEN EXISTS
        (
            SELECT 1
            FROM dbo.Reservation r
            JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
            JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
            WHERE rt.TableId = t.TableId
              AND rs.StatusCode = 'ACTIVE'
              AND SYSDATETIME() >= r.StartAt
              AND SYSDATETIME() < r.EndAt
        ) THEN N'Забронирован'
        ELSE N'Свободен'
    END AS Доступность
FROM dbo.RestaurantTable t
WHERE t.IsActive = 1;
GO

/* Официант не может закрыть смену, пока есть заказ, который ещё не закрыт по оплате. */
CREATE OR ALTER PROCEDURE dbo.sp_CloseCurrentWaiterShift
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @UserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51303, N'У вас нет открытой смены на сегодня.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
          AND
          (
              o.WaiterShiftId = @ShiftId
              OR
              (
                  o.WaiterShiftId IS NULL
                  AND EXISTS
                  (
                      SELECT 1
                      FROM dbo.WaiterTableAssignment a
                      WHERE a.ShiftId = @ShiftId
                        AND a.TableId = o.TableId
                  )
              )
          )
    )
        THROW 51304, N'Нельзя закрыть смену: есть незавершённые заказы. Доставьте заказ, пробейте и закройте счёт.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = SYSDATETIME()
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена закрыта.' AS Message;
END
GO

/*
  Активные заказы текущего официанта.
  Заказ из клиентского приложения на закреплённом столике также виден официанту,
  чтобы он мог принести его и закрыть счёт.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetOrdersForWaiter
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @UserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
    BEGIN
        SELECT
            CAST(NULL AS INT) AS OrderId,
            CAST(NULL AS INT) AS [№ заказа],
            CAST(NULL AS INT) AS [№ столика],
            CAST(NULL AS NVARCHAR(100)) AS Статус,
            CAST(NULL AS VARCHAR(20)) AS StatusCode,
            CAST(NULL AS DATETIME2) AS Создан,
            CAST(NULL AS INT) AS Порций,
            CAST(NULL AS DECIMAL(12,2)) AS [Сумма, руб.],
            CAST(NULL AS NVARCHAR(40)) AS [Счёт],
            CAST(NULL AS BIT) AS BillIssued,
            CAST(NULL AS BIT) AS BillPaid
        WHERE 1 = 0;
        RETURN;
    END

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        s.StatusName AS Статус,
        s.StatusCode,
        o.CreatedAt AS Создан,
        SUM(ISNULL(oi.Quantity, 0)) AS Порций,
        CAST(SUM(ISNULL(oi.Quantity * oi.UnitPrice, 0)) AS DECIMAL(12,2)) AS [Сумма, руб.],
        CASE
            WHEN b.BillId IS NULL THEN N'Не пробит'
            WHEN b.IsPaid = 1 THEN N'Оплачен'
            WHEN b.IssuedAt IS NULL THEN N'Не пробит'
            ELSE N'Ожидает оплаты'
        END AS [Счёт],
        CAST(CASE WHEN b.IssuedAt IS NULL THEN 0 ELSE 1 END AS BIT) AS BillIssued,
        CAST(ISNULL(b.IsPaid, 0) AS BIT) AS BillPaid
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    WHERE s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
      AND
      (
          o.WaiterShiftId = @ShiftId
          OR
          (
              o.WaiterShiftId IS NULL
              AND EXISTS
              (
                  SELECT 1
                  FROM dbo.WaiterTableAssignment a
                  WHERE a.ShiftId = @ShiftId
                    AND a.TableId = o.TableId
              )
          )
      )
    GROUP BY
        o.OrderId, t.TableNumber, s.StatusName, s.StatusCode, o.CreatedAt,
        b.BillId, b.IsPaid, b.IssuedAt
    ORDER BY o.CreatedAt DESC;
END
GO

/* Общая проверка: заказ может обслуживать только официант с открытой сменой и закреплённым столиком. */
CREATE OR ALTER PROCEDURE dbo.sp_WaiterServeOrder
    @WaiterUserId INT,
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51305, N'Сначала откройте смену.', 1;

    DECLARE @TableId INT;
    DECLARE @CurrentStatus VARCHAR(20);
    DECLARE @OrderShiftId INT;

    SELECT
        @TableId = o.TableId,
        @OrderShiftId = o.WaiterShiftId,
        @CurrentStatus = s.StatusCode
    FROM dbo.CustomerOrder o
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    WHERE o.OrderId = @OrderId;

    IF @TableId IS NULL
        THROW 51306, N'Заказ не найден.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterTableAssignment
        WHERE ShiftId = @ShiftId
          AND TableId = @TableId
    )
        THROW 51307, N'Этот столик не закреплён за вами в открытой смене.', 1;

    IF @OrderShiftId IS NOT NULL AND @OrderShiftId <> @ShiftId
        THROW 51308, N'Этот заказ закреплён за другим официантом.', 1;

    IF @CurrentStatus <> 'ACCEPTED'
        THROW 51309, N'Принести можно только заказ со статусом «Принят на выдачу».', 1;

    BEGIN TRANSACTION;

    UPDATE dbo.CustomerOrder
    SET
        WaiterShiftId = @ShiftId,
        OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'ISSUED')
    WHERE OrderId = @OrderId;

    COMMIT TRANSACTION;

    SELECT N'Заказ выдан клиенту. Теперь можно пробить счёт.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_WaiterCreateBill
    @WaiterUserId INT,
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51310, N'Сначала откройте смену.', 1;

    DECLARE @OrderShiftId INT;
    DECLARE @StatusCode VARCHAR(20);
    SELECT
        @OrderShiftId = o.WaiterShiftId,
        @StatusCode = s.StatusCode
    FROM dbo.CustomerOrder o
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    WHERE o.OrderId = @OrderId;

    IF @StatusCode IS NULL
        THROW 51311, N'Заказ не найден.', 1;

    IF @OrderShiftId <> @ShiftId
        THROW 51312, N'Пробить счёт может только официант, который выдал заказ клиенту.', 1;

    IF @StatusCode <> 'ISSUED'
        THROW 51313, N'Счёт можно пробить только после выдачи заказа клиенту.', 1;

    DECLARE @Amount DECIMAL(12,2) =
    (
        SELECT SUM(oi.Quantity * oi.UnitPrice)
        FROM dbo.OrderItem oi
        WHERE oi.OrderId = @OrderId
    );

    IF @Amount IS NULL OR @Amount <= 0
        THROW 51314, N'В заказе нет блюд для формирования счёта.', 1;

    BEGIN TRANSACTION;

    IF NOT EXISTS (SELECT 1 FROM dbo.Bill WHERE OrderId = @OrderId)
    BEGIN
        INSERT INTO dbo.Bill (OrderId, Amount, IsPaid, IssuedAt)
        VALUES (@OrderId, @Amount, 0, SYSDATETIME());
    END
    ELSE
    BEGIN
        IF EXISTS (SELECT 1 FROM dbo.Bill WHERE OrderId = @OrderId AND IsPaid = 1)
        BEGIN
            ROLLBACK TRANSACTION;
            THROW 51315, N'Этот счёт уже оплачен.', 1;
        END

        UPDATE dbo.Bill
        SET
            Amount = @Amount,
            IssuedAt = COALESCE(IssuedAt, SYSDATETIME())
        WHERE OrderId = @OrderId;
    END

    COMMIT TRANSACTION;

    SELECT
        @Amount AS Amount,
        CONCAT(N'Счёт пробит на сумму ', FORMAT(@Amount, 'N2', 'ru-RU'), N' руб. Ожидается оплата.') AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_WaiterCloseBill
    @WaiterUserId INT,
    @OrderId INT,
    @PaymentMethod NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PaymentMethod NOT IN (N'Наличные', N'Карта')
        THROW 51316, N'Выберите способ оплаты: «Наличные» или «Карта».', 1;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = 'OPEN'
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51317, N'Сначала откройте смену.', 1;

    DECLARE @OrderShiftId INT;
    DECLARE @TableId INT;
    DECLARE @StatusCode VARCHAR(20);
    DECLARE @BillId INT;
    DECLARE @Amount DECIMAL(12,2);
    DECLARE @BillIssuedAt DATETIME2;
    DECLARE @BillPaid BIT;

    SELECT
        @OrderShiftId = o.WaiterShiftId,
        @TableId = o.TableId,
        @StatusCode = s.StatusCode,
        @BillId = b.BillId,
        @Amount = b.Amount,
        @BillIssuedAt = b.IssuedAt,
        @BillPaid = b.IsPaid
    FROM dbo.CustomerOrder o
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    WHERE o.OrderId = @OrderId;

    IF @StatusCode IS NULL
        THROW 51318, N'Заказ не найден.', 1;

    IF @OrderShiftId <> @ShiftId
        THROW 51319, N'Закрыть счёт может только официант, который выдал заказ клиенту.', 1;

    IF @StatusCode <> 'ISSUED'
        THROW 51320, N'Закрыть можно только счёт по выданному клиенту заказу.', 1;

    IF @BillId IS NULL OR @BillIssuedAt IS NULL
        THROW 51321, N'Сначала пробейте счёт.', 1;

    IF @BillPaid = 1
        THROW 51322, N'Этот счёт уже закрыт.', 1;

    DECLARE @ReceiptNumber NVARCHAR(50) =
        CONCAT(N'WR-', FORMAT(SYSDATETIME(), 'yyyyMMddHHmmss'), N'-', @OrderId);

    BEGIN TRANSACTION;

    UPDATE dbo.Bill
    SET
        IsPaid = 1,
        PaidAt = SYSDATETIME(),
        PaymentMethod = @PaymentMethod,
        ReceiptNumber = @ReceiptNumber
    WHERE BillId = @BillId;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'COMPLETED')
    WHERE OrderId = @OrderId;

    /* Если столик был занят текущей бронью, она завершается вместе с оплачиваемым заказом. */
    UPDATE r
    SET ReservationStatusId =
    (
        SELECT ReservationStatusId
        FROM dbo.ReservationStatus
        WHERE StatusCode = 'COMPLETED'
    )
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE rt.TableId = @TableId
      AND rs.StatusCode = 'ACTIVE'
      AND SYSDATETIME() >= r.StartAt
      AND SYSDATETIME() < r.EndAt;

    COMMIT TRANSACTION;

    SELECT
        @ReceiptNumber AS ReceiptNumber,
        @Amount AS Amount,
        CONCAT(N'Счёт закрыт. Оплата принята: ', @PaymentMethod, N'. Столик освобождён.') AS Message;
END
GO

/* Ручное освобождение отключено: столик освобождает только закрытие оплаченного счёта. */
CREATE OR ALTER PROCEDURE dbo.sp_FreeTable
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    THROW 51323, N'Столик освобождается автоматически только после: выдать заказ → пробить счёт → закрыть счёт.', 1;
END
GO

PRINT N'White Rabbit v2.1: обслуживание, счёт, оплата и автоматическое освобождение столика добавлены.';
GO

/* Нельзя создать второй заказ на столике, пока предыдущий выдан, но ещё не оплачен. */
CREATE OR ALTER PROCEDURE dbo.sp_CreateOrderForWaiter
    @WaiterUserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51324, N'Количество гостей должно быть не меньше одного.', 1;

    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT @TableId = t.TableId, @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @TableId IS NULL
        THROW 51325, N'Столик не найден или отключён.', 1;

    IF @GuestCount > @SeatsCount
        THROW 51326, N'Количество гостей превышает вместимость выбранного столика.', 1;

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
        THROW 51327, N'Сначала откройте запланированную смену. Без открытой смены заказ создать нельзя.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
    )
        THROW 51328, N'У выбранного столика уже есть незавершённый заказ. Столик освободится после закрытия оплаченного счёта.', 1;

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
        THROW 51329, N'Столик забронирован на текущее время.', 1;

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

    SELECT SCOPE_IDENTITY() AS OrderId, N'Заказ создан. Можно добавлять блюда.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateClientAppOrder
    @UserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51330, N'Количество гостей должно быть не меньше одного.', 1;

    DECLARE @ClientId INT = (SELECT ClientId FROM dbo.Client WHERE UserId = @UserId);
    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT @TableId = t.TableId, @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @ClientId IS NULL
        THROW 51331, N'Клиент не найден.', 1;
    IF @TableId IS NULL
        THROW 51332, N'Столик не найден или отключён.', 1;
    IF @GuestCount > @SeatsCount
        THROW 51333, N'Количество гостей превышает вместимость выбранного столика.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
    )
        THROW 51334, N'Этот столик занят до закрытия оплаченного счёта.', 1;

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
        THROW 51335, N'Столик забронирован на текущее время.', 1;

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

    SELECT SCOPE_IDENTITY() AS OrderId, N'Корзина создана. Добавьте блюда и отправьте заказ на кухню.' AS Message;
END
GO

PRINT N'White Rabbit v2.1: защита от нового заказа до оплаты добавлена.';
GO
