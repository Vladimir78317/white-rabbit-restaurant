/*
================================================================================
 WHITE RABBIT v3.2 — НАДЁЖНОЕ ИСПРАВЛЕНИЕ СХЕМЫ ЗАКАЗОВ
================================================================================
Назначение: исправляет базу WhiteRabbitRestaurant, в которой v3.0/v3.1 вывели
ошибки 207 для ClientId, ChannelCode и GuestCount.

ВАЖНО:
  • Этот файл НЕ удаляет базу и НЕ удаляет данные.
  • Запускайте ТОЛЬКО ЭТОТ файл в SSMS через Execute (F5).
  • Не запускайте повторно SQL_Update_v3_1_Order_Schema_Compatibility_Fix.sql:
    в нём был дефект компиляции пакета SQL Server.

Причина дефекта v3.1:
SQL Server пытается скомпилировать UPDATE и CREATE PROCEDURE до выполнения
ALTER TABLE из того же пакета. Поэтому новые имена столбцов считались
несуществующими. В этом исправлении операции над новыми столбцами выполняются
динамически внутри отдельной транзакции, а процедуры создаются уже ПОСЛЕ неё.
================================================================================
*/
USE WhiteRabbitRestaurant;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_ID(N'WhiteRabbitRestaurant') IS NULL
    THROW 51500, N'База данных WhiteRabbitRestaurant не найдена.', 1;

IF OBJECT_ID(N'dbo.CustomerOrder', N'U') IS NULL
    THROW 51501, N'Таблица dbo.CustomerOrder не найдена.', 1;
GO

BEGIN TRY
    BEGIN TRANSACTION;

    /* Добавление отсутствующих полей. Dynamic SQL исключает ошибку компиляции 207. */
    IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
        EXEC(N'ALTER TABLE dbo.CustomerOrder ADD ClientId INT NULL;');

    IF COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
        EXEC(N'ALTER TABLE dbo.CustomerOrder ADD ChannelCode VARCHAR(20) NULL;');

    IF COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
        EXEC(N'ALTER TABLE dbo.CustomerOrder ADD GuestCount TINYINT NULL;');

    IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
       OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
       OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
        THROW 51502, N'Не удалось добавить обязательные поля в dbo.CustomerOrder.', 1;

    /* Заполняем старые заказы корректными значениями. */
    EXEC(N'
        UPDATE dbo.CustomerOrder
        SET ChannelCode = CASE
                              WHEN ClientId IS NOT NULL THEN ''CLIENT_APP''
                              ELSE ''WAITER''
                          END
        WHERE ChannelCode IS NULL
           OR ChannelCode NOT IN (''WAITER'', ''CLIENT_APP'');
    ');

    EXEC(N'
        UPDATE dbo.CustomerOrder
        SET GuestCount = 1
        WHERE GuestCount IS NULL
           OR GuestCount < 1
           OR GuestCount > 4;
    ');

    /* У заказа, созданного клиентом, официант назначается позже. */
    EXEC(N'ALTER TABLE dbo.CustomerOrder ALTER COLUMN WaiterShiftId INT NULL;');

    /* Добавляем ограничения по умолчанию, только если их ещё нет. */
    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.default_constraints dc
        WHERE dc.parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND dc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.CustomerOrder'), N'ChannelCode', N'ColumnId')
    )
        EXEC(N'ALTER TABLE dbo.CustomerOrder ADD CONSTRAINT DF_CustomerOrder_ChannelCode DEFAULT (''WAITER'') FOR ChannelCode;');

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.default_constraints dc
        WHERE dc.parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND dc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.CustomerOrder'), N'GuestCount', N'ColumnId')
    )
        EXEC(N'ALTER TABLE dbo.CustomerOrder ADD CONSTRAINT DF_CustomerOrder_GuestCount DEFAULT (1) FOR GuestCount;');

    EXEC(N'ALTER TABLE dbo.CustomerOrder ALTER COLUMN ChannelCode VARCHAR(20) NOT NULL;');
    EXEC(N'ALTER TABLE dbo.CustomerOrder ALTER COLUMN GuestCount TINYINT NOT NULL;');

    /* Заменяем старое ограничение источника заказа на совместимое с клиентским приложением. */
    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND name = N'CK_CustomerOrder_Source'
    )
        EXEC(N'ALTER TABLE dbo.CustomerOrder DROP CONSTRAINT CK_CustomerOrder_Source;');

    IF EXISTS
    (
        SELECT 1
        FROM sys.check_constraints
        WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND name = N'CK_CustomerOrder_GuestCount'
    )
        EXEC(N'ALTER TABLE dbo.CustomerOrder DROP CONSTRAINT CK_CustomerOrder_GuestCount;');

    IF NOT EXISTS
    (
        SELECT 1
        FROM sys.foreign_key_columns fkc
        WHERE fkc.parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
          AND fkc.parent_column_id = COLUMNPROPERTY(OBJECT_ID(N'dbo.CustomerOrder'), N'ClientId', N'ColumnId')
    )
        EXEC(N'
            ALTER TABLE dbo.CustomerOrder
            ADD CONSTRAINT FK_CustomerOrder_Client
                FOREIGN KEY (ClientId) REFERENCES dbo.Client(ClientId);
        ');

    EXEC(N'
        ALTER TABLE dbo.CustomerOrder
        ADD CONSTRAINT CK_CustomerOrder_Source CHECK
        (
            (ChannelCode = ''WAITER'' AND WaiterShiftId IS NOT NULL AND ClientId IS NULL)
            OR
            (ChannelCode = ''CLIENT_APP'' AND ClientId IS NOT NULL)
        );
    ');

    EXEC(N'
        ALTER TABLE dbo.CustomerOrder
        ADD CONSTRAINT CK_CustomerOrder_GuestCount CHECK (GuestCount BETWEEN 1 AND 4);
    ');

    COMMIT TRANSACTION;
END TRY
BEGIN CATCH
    IF XACT_STATE() <> 0
        ROLLBACK TRANSACTION;
    THROW;
END CATCH;
GO

/* Проверка схемы в отдельном пакете: дальше SQL Server уже видит новые столбцы. */
IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    THROW 51503, N'Проверка схемы не пройдена: обязательные поля не найдены.', 1;
GO

/* Служебное создание сотрудника. Используется процедурой администратора. */
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
END;
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
END;
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
        CASE WHEN o.ChannelCode = 'CLIENT_APP' THEN N'Клиентское приложение' ELSE N'Официант' END AS [Источник],
        ISNULL(c.FullName, N'Гость') AS [Клиент],
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
END;
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
END;
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
END;
GO

EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetKitchenOrders';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateOrderForWaiter';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_CreateClientAppOrder';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_AdminGetOrderStatuses';
EXEC sys.sp_refreshsqlmodule N'dbo.sp_GetClientOrderStatuses';
GO

PRINT N'White Rabbit v3.2: схема заказов и процедуры исправлены без ошибок компиляции пакета.';
GO
