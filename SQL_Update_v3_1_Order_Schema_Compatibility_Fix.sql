/*
================================================================================
 WHITE RABBIT v3.1 — ИСПРАВЛЕНИЕ СОВМЕСТИМОСТИ СХЕМЫ ЗАКАЗОВ
================================================================================
Запускайте этот файл, если уже выполняли WhiteRabbitRestaurant_Complete_Install_v3_0.sql
и получили ошибки 207: ClientId, ChannelCode или GuestCount.

Скрипт НЕ удаляет базу и НЕ удаляет данные. Он:
  1. Добавляет в dbo.CustomerOrder столбцы ClientId, ChannelCode и GuestCount.
  2. Разрешает NULL для WaiterShiftId у заказа из клиентского приложения.
  3. Пересоздаёт процедуры, которые ранее не были созданы из-за несовпадения схемы.
  4. Добавляет отсутствующую служебную процедуру dbo.sp_CreateUser.
================================================================================
*/
USE WhiteRabbitRestaurant;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'WhiteRabbitRestaurant') IS NULL
    THROW 51500, N'База данных WhiteRabbitRestaurant не найдена.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    IF COL_LENGTH('dbo.CustomerOrder', 'ClientId') IS NULL
        ALTER TABLE dbo.CustomerOrder ADD ClientId INT NULL;

    IF COL_LENGTH('dbo.CustomerOrder', 'ChannelCode') IS NULL
        ALTER TABLE dbo.CustomerOrder
            ADD ChannelCode VARCHAR(20) NOT NULL
                CONSTRAINT DF_CustomerOrder_ChannelCode DEFAULT ('WAITER') WITH VALUES;

    IF COL_LENGTH('dbo.CustomerOrder', 'GuestCount') IS NULL
        ALTER TABLE dbo.CustomerOrder
            ADD GuestCount TINYINT NOT NULL
                CONSTRAINT DF_CustomerOrder_GuestCount DEFAULT (1) WITH VALUES;

    /* Клиентский заказ не получает смену до момента выдачи официантом. */
    ALTER TABLE dbo.CustomerOrder ALTER COLUMN WaiterShiftId INT NULL;

    /* Существующие записи базового сценария считаем заказами официанта. */
    UPDATE dbo.CustomerOrder
    SET ChannelCode = CASE WHEN ClientId IS NOT NULL THEN 'CLIENT_APP' ELSE 'WAITER' END
    WHERE ChannelCode IS NULL OR ChannelCode NOT IN ('WAITER', 'CLIENT_APP');

    UPDATE dbo.CustomerOrder
    SET GuestCount = 1
    WHERE GuestCount IS NULL OR GuestCount < 1 OR GuestCount > 4;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND name = N'CK_CustomerOrder_Source'
    )
        ALTER TABLE dbo.CustomerOrder DROP CONSTRAINT CK_CustomerOrder_Source;

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND name = N'CK_CustomerOrder_GuestCount'
    )
        ALTER TABLE dbo.CustomerOrder DROP CONSTRAINT CK_CustomerOrder_GuestCount;

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.foreign_keys
        WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND name = N'FK_CustomerOrder_Client'
    )
        ALTER TABLE dbo.CustomerOrder
            ADD CONSTRAINT FK_CustomerOrder_Client
                FOREIGN KEY (ClientId) REFERENCES dbo.Client(ClientId);

    ALTER TABLE dbo.CustomerOrder
        ADD CONSTRAINT CK_CustomerOrder_Source CHECK
        (
            (ReservationId IS NULL OR VisitId IS NULL)
            AND
            (
                (ChannelCode = 'WAITER' AND WaiterShiftId IS NOT NULL AND ClientId IS NULL)
                OR
                (ChannelCode = 'CLIENT_APP' AND ClientId IS NOT NULL)
            )
        );

    ALTER TABLE dbo.CustomerOrder
        ADD CONSTRAINT CK_CustomerOrder_GuestCount CHECK (GuestCount BETWEEN 1 AND 4);

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0 ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* Служебное создание сотрудника без result set: используется администратором. */
CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
    @RoleCode VARCHAR(20),
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30) = NULL,
    @UserId INT OUTPUT
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.AppUser WHERE Login = @Login)
        THROW 51011, N'Пользователь с таким логином уже существует.', 1;

    DECLARE @RoleId INT =
    (
        SELECT RoleId
        FROM dbo.AppRole
        WHERE RoleCode = @RoleCode
    );

    IF @RoleId IS NULL
        THROW 51012, N'Указанная роль не существует.', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @PasswordHash VARBINARY(64) =
        HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), @Password) + @Salt);

    INSERT INTO dbo.AppUser
    (
        RoleId, Login, PasswordHash, PasswordSalt,
        LastName, FirstName, Phone
    )
    VALUES
    (
        @RoleId, @Login, @PasswordHash, @Salt,
        @LastName, @FirstName, @Phone
    );

    SET @UserId = CONVERT(INT, SCOPE_IDENTITY());
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetKitchenOrders
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        s.StatusName AS Статус,
        CASE
            WHEN o.ChannelCode = 'CLIENT_APP' THEN N'Клиентское приложение'
            ELSE N'Официант'
        END AS Источник,
        c.FullName AS Клиент,
        SUM(ISNULL(oi.Quantity, 0)) AS Порций
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Client c ON c.ClientId = o.ClientId
    LEFT JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    WHERE s.StatusCode IN ('PLACED', 'PREPARING', 'READY')
    GROUP BY o.OrderId, t.TableNumber, s.StatusName, o.ChannelCode, c.FullName
    ORDER BY o.OrderId DESC;
END;
GO


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


CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateEmployee
    @RoleCode VARCHAR(20),
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @RoleCode NOT IN ('WAITER', 'KITCHEN')
        THROW 51101, N'Администратор может создать только официанта или сотрудника кухни.', 1;

    IF LEN(@Password) < 6
        THROW 51102, N'Пароль должен содержать минимум 6 символов.', 1;

    DECLARE @UserId INT;
    EXEC dbo.sp_CreateUser
        @RoleCode = @RoleCode,
        @Login = @Login,
        @Password = @Password,
        @LastName = @LastName,
        @FirstName = @FirstName,
        @Phone = @Phone,
        @UserId = @UserId OUTPUT;

    IF @RoleCode = 'WAITER'
        INSERT INTO dbo.Waiter (UserId) VALUES (@UserId);

    SELECT
        @UserId AS UserId,
        CONCAT(N'Сотрудник «', @LastName, N' ', @FirstName, N'» успешно добавлен.') AS Message;
END
GO


PRINT N'White Rabbit v3.1: схема заказов и зависимые процедуры успешно исправлены.';
GO
