
/* ============================================================================
   White Rabbit v3.3 — полное восстановление совместимости текущей базы
   Не удаляет существующие данные.
   Перед запуском убедитесь, что в SSMS выбрана база WhiteRabbitRestaurant.
============================================================================ */
USE WhiteRabbitRestaurant;
GO
SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF DB_NAME() <> N'WhiteRabbitRestaurant'
    THROW 51900, N'Скрипт необходимо выполнять в базе WhiteRabbitRestaurant.', 1;

IF OBJECT_ID(N'dbo.AppUser', N'U') IS NULL
   OR OBJECT_ID(N'dbo.CustomerOrder', N'U') IS NULL
   OR OBJECT_ID(N'dbo.RestaurantTable', N'U') IS NULL
    THROW 51901, N'Базовая структура ресторана не найдена. Для пустого сервера используйте полный установщик WhiteRabbitRestaurant_Complete_Install_v3_3.sql.', 1;
GO

/* ===== 1. Исправление структуры заказов ===== */
IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.CustomerOrder ADD ClientId INT NULL;';

IF COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.CustomerOrder ADD ChannelCode VARCHAR(20) NOT NULL CONSTRAINT DF_CustomerOrder_ChannelCode_v33 DEFAULT (''WAITER'') WITH VALUES;';

IF COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.CustomerOrder ADD GuestCount TINYINT NOT NULL CONSTRAINT DF_CustomerOrder_GuestCount_v33 DEFAULT (1) WITH VALUES;';

/* Заказы из клиентского приложения создаются без смены официанта. */
IF EXISTS
(
    SELECT 1 FROM sys.columns
    WHERE object_id = OBJECT_ID(N'dbo.CustomerOrder')
      AND name = N'WaiterShiftId'
      AND is_nullable = 0
)
    EXEC sys.sp_executesql N'ALTER TABLE dbo.CustomerOrder ALTER COLUMN WaiterShiftId INT NULL;';

/* Снимаем только устаревшее ограничение источника заказа: ReservationId/VisitId.
   Оно несовместимо с заказом из клиентского приложения. */
DECLARE @DropSourceConstraintSql NVARCHAR(MAX) = N'';
SELECT @DropSourceConstraintSql += N'ALTER TABLE dbo.CustomerOrder DROP CONSTRAINT ' + QUOTENAME(name) + N';' + CHAR(10)
FROM sys.check_constraints
WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
  AND definition LIKE N'%ReservationId%'
  AND definition LIKE N'%VisitId%';
IF @DropSourceConstraintSql <> N''
    EXEC sys.sp_executesql @DropSourceConstraintSql;

IF NOT EXISTS
(
    SELECT 1 FROM sys.check_constraints
    WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
      AND name = N'CK_CustomerOrder_Source'
)
    EXEC sys.sp_executesql N'
        ALTER TABLE dbo.CustomerOrder WITH NOCHECK
        ADD CONSTRAINT CK_CustomerOrder_Source CHECK
        (
            (ChannelCode = ''WAITER'' AND WaiterShiftId IS NOT NULL AND ClientId IS NULL)
            OR (ChannelCode = ''CLIENT_APP'' AND ClientId IS NOT NULL)
        );';

IF NOT EXISTS
(
    SELECT 1 FROM sys.foreign_keys
    WHERE parent_object_id = OBJECT_ID(N'dbo.CustomerOrder')
      AND referenced_object_id = OBJECT_ID(N'dbo.Client')
)
    EXEC sys.sp_executesql N'
        ALTER TABLE dbo.CustomerOrder
        ADD CONSTRAINT FK_CustomerOrder_Client_v33
        FOREIGN KEY (ClientId) REFERENCES dbo.Client(ClientId);';
GO

/* ===== 2. Поля, требуемые сменами и оплатой ===== */
IF COL_LENGTH(N'dbo.WaiterShift', N'ActualCloseAt') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.WaiterShift ADD ActualCloseAt DATETIME2 NULL;';
IF COL_LENGTH(N'dbo.WaiterShift', N'CloseReason') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.WaiterShift ADD CloseReason NVARCHAR(500) NULL;';
IF COL_LENGTH(N'dbo.WaiterShift', N'ClosedByUserId') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.WaiterShift ADD ClosedByUserId INT NULL;';
IF COL_LENGTH(N'dbo.WaiterShift', N'WasClosedAutomatically') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.WaiterShift ADD WasClosedAutomatically BIT NOT NULL CONSTRAINT DF_WaiterShift_WasClosedAutomatically_v33 DEFAULT (0) WITH VALUES;';
IF COL_LENGTH(N'dbo.WaiterShift', N'IsWalkInShift') IS NULL
    EXEC sys.sp_executesql N'ALTER TABLE dbo.WaiterShift ADD IsWalkInShift BIT NOT NULL CONSTRAINT DF_WaiterShift_IsWalkInShift_v33 DEFAULT (0) WITH VALUES;';

IF OBJECT_ID(N'dbo.Bill', N'U') IS NOT NULL
BEGIN
    IF COL_LENGTH(N'dbo.Bill', N'IssuedAt') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.Bill ADD IssuedAt DATETIME2 NULL;';
    IF COL_LENGTH(N'dbo.Bill', N'PaidAt') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.Bill ADD PaidAt DATETIME2 NULL;';
    IF COL_LENGTH(N'dbo.Bill', N'PaymentMethod') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.Bill ADD PaymentMethod NVARCHAR(30) NULL;';
    IF COL_LENGTH(N'dbo.Bill', N'ReceiptNumber') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.Bill ADD ReceiptNumber NVARCHAR(50) NULL;';
END
GO

/* ===== 3. Исправление профилей клиентов ===== */
DECLARE @DropClientUserIdUniqueSql NVARCHAR(MAX) = N'';
SELECT @DropClientUserIdUniqueSql += N'ALTER TABLE dbo.Client DROP CONSTRAINT ' + QUOTENAME(kc.name) + N';' + CHAR(10)
FROM sys.key_constraints kc
JOIN sys.index_columns ic ON ic.object_id = kc.parent_object_id AND ic.index_id = kc.unique_index_id
JOIN sys.columns c ON c.object_id = ic.object_id AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID(N'dbo.Client')
  AND kc.type = 'UQ'
GROUP BY kc.name, kc.parent_object_id, kc.unique_index_id
HAVING COUNT(*) = 1 AND MAX(c.name) = N'UserId';
IF @DropClientUserIdUniqueSql <> N''
    EXEC sys.sp_executesql @DropClientUserIdUniqueSql;

IF EXISTS (SELECT 1 FROM sys.indexes WHERE object_id = OBJECT_ID(N'dbo.Client') AND name = N'UX_Client_UserId_NotNull')
    DROP INDEX UX_Client_UserId_NotNull ON dbo.Client;

CREATE UNIQUE INDEX UX_Client_UserId_NotNull
    ON dbo.Client(UserId)
    WHERE UserId IS NOT NULL;
GO

/* ===== 4. Отсутствующие объекты меню и склада ===== */
IF OBJECT_ID(N'dbo.DishStopList', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DishStopList
    (
        DishId INT NOT NULL CONSTRAINT PK_DishStopList PRIMARY KEY,
        IsStopListed BIT NOT NULL CONSTRAINT DF_DishStopList_IsStopListed DEFAULT (0),
        Reason NVARCHAR(300) NULL,
        ChangedByUserId INT NULL,
        ChangedAt DATETIME2(0) NOT NULL CONSTRAINT DF_DishStopList_ChangedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT FK_DishStopList_Dish FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId),
        CONSTRAINT FK_DishStopList_ChangedBy FOREIGN KEY (ChangedByUserId) REFERENCES dbo.AppUser(UserId)
    );
END
ELSE
BEGIN
    IF COL_LENGTH(N'dbo.DishStopList', N'IsStopListed') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.DishStopList ADD IsStopListed BIT NOT NULL CONSTRAINT DF_DishStopList_IsStopListed_v33 DEFAULT (0) WITH VALUES;';
    IF COL_LENGTH(N'dbo.DishStopList', N'Reason') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.DishStopList ADD Reason NVARCHAR(300) NULL;';
    IF COL_LENGTH(N'dbo.DishStopList', N'ChangedByUserId') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.DishStopList ADD ChangedByUserId INT NULL;';
    IF COL_LENGTH(N'dbo.DishStopList', N'ChangedAt') IS NULL
        EXEC sys.sp_executesql N'ALTER TABLE dbo.DishStopList ADD ChangedAt DATETIME2(0) NOT NULL CONSTRAINT DF_DishStopList_ChangedAt_v33 DEFAULT (SYSDATETIME()) WITH VALUES;';
END

IF OBJECT_ID(N'dbo.DishStockMovement', N'U') IS NULL
BEGIN
    CREATE TABLE dbo.DishStockMovement
    (
        StockMovementId INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DishStockMovement PRIMARY KEY,
        DishId INT NOT NULL,
        Quantity INT NOT NULL,
        OperationType VARCHAR(20) NOT NULL CONSTRAINT DF_DishStockMovement_OperationType DEFAULT ('RESTOCK'),
        AdminUserId INT NOT NULL,
        Comment NVARCHAR(250) NULL,
        CreatedAt DATETIME2(0) NOT NULL CONSTRAINT DF_DishStockMovement_CreatedAt DEFAULT (SYSDATETIME()),
        CONSTRAINT CK_DishStockMovement_Quantity CHECK (Quantity > 0),
        CONSTRAINT FK_DishStockMovement_Dish FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId),
        CONSTRAINT FK_DishStockMovement_Admin FOREIGN KEY (AdminUserId) REFERENCES dbo.AppUser(UserId)
    );
END

IF NOT EXISTS
(
    SELECT 1 FROM sys.indexes
    WHERE name = N'IX_DishStockMovement_Dish_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.DishStockMovement')
)
    CREATE INDEX IX_DishStockMovement_Dish_CreatedAt
        ON dbo.DishStockMovement(DishId, CreatedAt DESC);
GO

/* ===== 5. Пересоздание процедур после исправления структуры ===== */


/* sp_AuthenticateUser */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AuthenticateUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @UserId INT;
    DECLARE @SavedHash VARBINARY(64);
    DECLARE @Salt VARBINARY(16);

    SELECT
        @UserId = UserId,
        @SavedHash = PasswordHash,
        @Salt = PasswordSalt
    FROM dbo.AppUser
    WHERE Login = @Login
      AND IsActive = 1;

    IF @UserId IS NULL
        THROW 50055, N''Неверный логин или пароль.'', 1;

    IF HASHBYTES(''SHA2_512'', CONVERT(VARBINARY(MAX), @Password) + @Salt) <> @SavedHash
        THROW 50056, N''Неверный логин или пароль.'', 1;

    SELECT
        u.UserId,
        u.Login,
        CONCAT(u.LastName, N'' '', u.FirstName, N'' '', ISNULL(u.MiddleName, N'''')) AS FullName,
        r.RoleCode,
        r.RoleName,
        N''Авторизация выполнена успешно.'' AS Message
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE u.UserId = @UserId;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_RegisterClient */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_RegisterClient
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF LEN(@Password) < 6
        THROW 51002, N''Пароль должен содержать минимум 6 символов.'', 1;

    DECLARE @CreatedUser TABLE
    (
        UserId INT,
        Message NVARCHAR(250)
    );

    INSERT INTO @CreatedUser (UserId, Message)
    EXEC dbo.sp_RegisterUser
        @Login = @Login,
        @Password = @Password,
        @RoleCode = ''CLIENT'',
        @LastName = @LastName,
        @FirstName = @FirstName,
        @MiddleName = NULL,
        @Phone = @Phone,
        @Email = NULL;

    DECLARE @UserId INT = (SELECT TOP (1) UserId FROM @CreatedUser);

    INSERT INTO dbo.Client (UserId, FullName, Phone)
    VALUES (@UserId, CONCAT(@LastName, N'' '', @FirstName), @Phone);

    SELECT @UserId AS UserId, N''Клиент успешно зарегистрирован.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_RegisterUser */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_RegisterUser
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @RoleCode VARCHAR(30),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @MiddleName NVARCHAR(60) = NULL,
    @Phone NVARCHAR(30) = NULL,
    @Email NVARCHAR(150) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF EXISTS (SELECT 1 FROM dbo.AppUser WHERE Login = @Login)
        THROW 50001, N''Пользователь с таким логином уже существует.'', 1;

    DECLARE @RoleId INT =
    (
        SELECT RoleId
        FROM dbo.AppRole
        WHERE RoleCode = @RoleCode
    );

    IF @RoleId IS NULL
        THROW 50002, N''Указанная роль не существует.'', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @PasswordHash VARBINARY(64) =
        HASHBYTES(''SHA2_512'', CONVERT(VARBINARY(MAX), @Password) + @Salt);

    INSERT INTO dbo.AppUser
    (
        RoleId, Login, PasswordHash, PasswordSalt,
        LastName, FirstName, MiddleName, Phone, Email
    )
    VALUES
    (
        @RoleId, @Login, @PasswordHash, @Salt,
        @LastName, @FirstName, @MiddleName, @Phone, @Email
    );

    SELECT
        SCOPE_IDENTITY() AS UserId,
        N''Пользователь успешно зарегистрирован.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CreateUser */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CreateUser
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
        THROW 51011, N''Пользователь с таким логином уже существует.'', 1;

    DECLARE @RoleId INT =
    (
        SELECT RoleId
        FROM dbo.AppRole
        WHERE RoleCode = @RoleCode
    );

    IF @RoleId IS NULL
        THROW 51012, N''Указанная роль не существует.'', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @PasswordHash VARBINARY(64) =
        HASHBYTES(''SHA2_512'', CONVERT(VARBINARY(MAX), @Password) + @Salt);

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
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminCreateEmployee */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateEmployee
    @RoleCode VARCHAR(20),
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @RoleCode NOT IN (''WAITER'', ''KITCHEN'')
        THROW 51101, N''Администратор может создать только официанта или сотрудника кухни.'', 1;

    IF LEN(@Password) < 6
        THROW 51102, N''Пароль должен содержать минимум 6 символов.'', 1;

    DECLARE @UserId INT;
    EXEC dbo.sp_CreateUser
        @RoleCode = @RoleCode,
        @Login = @Login,
        @Password = @Password,
        @LastName = @LastName,
        @FirstName = @FirstName,
        @Phone = @Phone,
        @UserId = @UserId OUTPUT;

    IF @RoleCode = ''WAITER''
        INSERT INTO dbo.Waiter (UserId) VALUES (@UserId);

    SELECT
        @UserId AS UserId,
        CONCAT(N''Сотрудник «'', @LastName, N'' '', @FirstName, N''» успешно добавлен.'') AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAdminEmployees */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAdminEmployees
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        u.Login AS [Логин],
        CONCAT(u.LastName, N'' '', u.FirstName) AS [Сотрудник],
        r.RoleName AS [Роль],
        ISNULL(u.Phone, N''—'') AS [Телефон]
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE r.RoleCode IN (''WAITER'', ''KITCHEN'')
      AND u.IsActive = 1
    ORDER BY r.RoleName, u.LastName, u.FirstName;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminDeactivateEmployee */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminDeactivateEmployee
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
        @FullName = CONCAT(u.LastName, N'' '', u.FirstName)
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE u.UserId = @UserId
      AND u.IsActive = 1;

    IF @RoleCode IS NULL
        THROW 51213, N''Сотрудник не найден или уже удалён из рабочего списка.'', 1;

    IF @RoleCode NOT IN (''WAITER'', ''KITCHEN'')
        THROW 51214, N''Удалять можно только официанта или сотрудника кухни.'', 1;

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
             AND ss.StatusCode = ''OPEN''
       )
        THROW 51215, N''Нельзя удалить официанта с открытой сменой. Сначала закройте смену.'', 1;

    BEGIN TRANSACTION;

    /* Плановые смены сотрудника больше не участвуют в графике. */
    IF @WaiterId IS NOT NULL
    BEGIN
        UPDATE ws
        SET
            ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''CLOSED''),
            ActualCloseAt = COALESCE(ws.ActualCloseAt, SYSDATETIME())
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode = ''PLANNED'';
    END

    UPDATE dbo.AppUser
    SET IsActive = 0
    WHERE UserId = @UserId;

    COMMIT TRANSACTION;

    SELECT CONCAT(N''Сотрудник «'', @FullName, N''» удалён из рабочего списка.'') AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAdminWaiters */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiters
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        w.WaiterId,
        u.Login AS [Логин],
        CONCAT(u.LastName, N'' '', u.FirstName) AS [Официант]
    FROM dbo.Waiter w
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE u.IsActive = 1
    ORDER BY u.LastName, u.FirstName;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAllRestaurantTables */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAllRestaurantTables
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        t.HallZone
    FROM dbo.RestaurantTable t
    WHERE t.IsActive = 1
    ORDER BY t.TableNumber;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminCreateWaiterShift */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(400) = NULL /* оставлен для совместимости со старым интерфейсом; не используется */
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51518, N''Время окончания смены должно быть позже времени начала.'', 1;
    IF CONVERT(DATE, @PlannedStartAt) <> CONVERT(DATE, @PlannedEndAt)
       OR CONVERT(TIME, @PlannedStartAt) < CONVERT(TIME, ''09:00:00'')
       OR CONVERT(TIME, @PlannedEndAt) > CONVERT(TIME, ''23:00:00'')
       OR DATEDIFF(MINUTE, @PlannedStartAt, @PlannedEndAt) > 840
        THROW 51519, N''Смена должна быть в пределах одного дня, времени работы ресторана 09:00–23:00 и длиться не более 14 часов.'', 1;

    DECLARE @WaiterId INT =
    (
        SELECT w.WaiterId
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE w.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND r.RoleCode = ''WAITER''
    );

    IF @WaiterId IS NULL
        THROW 51520, N''Выбранный пользователь не является активным официантом.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode IN (''PLANNED'', ''OPEN'')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51521, N''У официанта уже есть пересекающаяся смена.'', 1;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId, ShiftStatusId, PlannedStartAt, PlannedEndAt,
        ActualOpenAt, ActualCloseAt, CloseReason, ClosedByUserId,
        WasClosedAutomatically, IsWalkInShift
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''PLANNED''),
        @PlannedStartAt, @PlannedEndAt,
        NULL, NULL, NULL, NULL, 0, 0
    );

    SELECT SCOPE_IDENTITY() AS ShiftId,
           N''Смена запланирована. Столики будут автоматически распределены при её открытии.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminOpenWaiterShift */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminOpenWaiterShift
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
          AND r.RoleCode = ''ADMIN''
    )
        THROW 51506, N''Открывать смены может только администратор.'', 1;

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
        THROW 51507, N''Смена не найдена.'', 1;
    IF @StatusCode <> ''PLANNED''
        THROW 51508, N''Открыть можно только запланированную смену.'', 1;
    IF @Now < @PlannedStartAt OR @Now >= @PlannedEndAt
        THROW 51509, N''Открыть смену можно только в её назначенном временном интервале.'', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''OPEN''),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0,
        IsWalkInShift = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N''Смена официанта открыта администратором. Столики распределены автоматически.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminCloseWaiterShift */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminCloseWaiterShift
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
          AND r.RoleCode = ''ADMIN''
    )
        THROW 51513, N''Закрывать смены может только администратор.'', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT @PlannedEndAt = ws.PlannedEndAt, @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51514, N''Смена не найдена.'', 1;
    IF @StatusCode <> ''OPEN''
        THROW 51515, N''Закрыть можно только открытую смену.'', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'''') IS NULL
        THROW 51516, N''При досрочном закрытии смены обязательно укажите причину.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
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
        THROW 51517, N''Нельзя закрыть смену: у официанта есть незавершённые заказы.'', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''CLOSED''),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''''),
        ClosedByUserId = @AdminUserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N''Смена официанта закрыта администратором. Столики перераспределены автоматически.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AutoCloseExpiredWaiterShifts */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AutoCloseExpiredWaiterShifts
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
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''CLOSED''),
        ActualCloseAt = @Now,
        CloseReason = CASE
            WHEN ss.StatusCode = ''PLANNED'' THEN N''Автоматически закрыта: смена не была открыта до окончания планового времени.''
            ELSE N''Автоматически закрыта по окончании планового времени.''
        END,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 1
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ss.StatusCode IN (''OPEN'', ''PLANNED'')
      AND ws.ActualCloseAt IS NULL
      AND ws.PlannedEndAt <= @Now
      AND
      (
          ss.StatusCode = ''PLANNED''
          OR NOT EXISTS
          (
          SELECT 1
          FROM dbo.CustomerOrder o
          JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
          WHERE os.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
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
                WHEN @ClosedCount = 0 THEN N''Смен для автоматического закрытия нет.''
                ELSE CONCAT(N''Автоматически закрыто смен: '', @ClosedCount, N''.'')
            END AS Message;
    END
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_RebalanceOpenWaiterTables */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_RebalanceOpenWaiterTables
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
             AND r.RoleCode = ''ADMIN''
       )
        THROW 51501, N''Перераспределять столики может только администратор.'', 1;

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
    WHERE ss.StatusCode = ''OPEN''
      AND u.IsActive = 1
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL;

    DECLARE @WaiterCount INT = (SELECT COUNT(*) FROM @OpenShifts);
    DECLARE @TableCount INT = (SELECT COUNT(*) FROM dbo.RestaurantTable WHERE IsActive = 1);

    IF @WaiterCount = 0
    BEGIN
        IF @ReturnResult = 1
            SELECT 0 AS WaiterCount, @TableCount AS TableCount,
                   N''Открытых смен нет: распределение столиков не требуется.'' AS Message;
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
            N''Столики автоматически распределены между открытыми сменами официантов.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_OpenCurrentWaiterShift */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
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
      AND r.RoleCode = ''WAITER'';

    IF @WaiterId IS NULL
        THROW 51502, N''Открыть смену может только активный официант.'', 1;

    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = ''OPEN''
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NOT NULL
    BEGIN
        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N''У вас уже открыта смена. Столики актуализированы автоматически.'' AS Message;
        RETURN;
    END

    /* Сначала открываем подходящую смену, созданную администратором. */
    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = ''PLANNED''
      AND ws.ActualOpenAt IS NULL
      AND ws.PlannedStartAt <= @Now
      AND ws.PlannedEndAt > @Now
    ORDER BY ws.PlannedStartAt, ws.ShiftId;

    IF @ShiftId IS NOT NULL
    BEGIN
        UPDATE dbo.WaiterShift
        SET
            ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''OPEN''),
            ActualOpenAt = @Now,
            ActualCloseAt = NULL,
            CloseReason = NULL,
            ClosedByUserId = NULL,
            WasClosedAutomatically = 0,
            IsWalkInShift = 0
        WHERE ShiftId = @ShiftId;

        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N''Назначенная смена открыта. Столики распределены автоматически.'' AS Message;
        RETURN;
    END

    /* Если графика на текущее время нет, создаётся самостоятельная смена до 23:00. */
    IF CONVERT(TIME, @Now) < CONVERT(TIME, ''09:00:00'')
       OR CONVERT(TIME, @Now) >= CONVERT(TIME, ''23:00:00'')
        THROW 51503, N''Самостоятельную смену можно открыть только в часы работы ресторана: с 09:00 до 23:00.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode = ''PLANNED''
';
SET @ProcedureSql += N'          AND ws.ActualOpenAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
          AND ws.PlannedStartAt > @Now
    )
        THROW 51504, N''На сегодня уже есть назначенная смена. Откройте её в указанное время.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        WHERE ws.WaiterId = @WaiterId
          AND ws.IsWalkInShift = 1
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
    )
        THROW 51505, N''Самостоятельная смена этого официанта уже была создана сегодня.'', 1;

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
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''OPEN''),
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
    SELECT @ShiftId AS ShiftId, N''Самостоятельная смена открыта до 23:00 и отображается у администратора. Столики распределены автоматически.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CloseCurrentWaiterShift */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CloseCurrentWaiterShift
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
      AND ss.StatusCode = ''OPEN''
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NULL
        THROW 51510, N''У вас нет открытой смены.'', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'''') IS NULL
        THROW 51511, N''При досрочном закрытии смены обязательно укажите причину.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
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
        THROW 51512, N''Нельзя закрыть смену: есть незавершённые заказы. Завершите обслуживание и закройте счета.'', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = ''CLOSED''),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''''),
        ClosedByUserId = @UserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables;
    SELECT N''Смена закрыта. Столики перераспределены между оставшимися официантами.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetWaiterAssignedTables */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
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
      AND ss.StatusCode = ''OPEN''
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAvailableTables */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableTables
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
            AND s.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.Reservation r
          JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
          JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
          WHERE rt.TableId = t.TableId
            AND rs.StatusCode = ''ACTIVE''
            AND @Now >= r.StartAt
            AND @Now < r.EndAt
      )
    ORDER BY t.TableNumber;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAvailableMenu */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableMenu
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        d.DishName AS [Блюдо],
        c.CategoryName AS [Категория],
        d.BasePrice AS [Цена, руб.],
        s.AvailablePortions AS [Доступно, порций]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.DishStock s ON s.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    WHERE d.IsActive = 1
      AND ISNULL(sl.IsStopListed, 0) = 0
      AND s.AvailablePortions > 0
    ORDER BY c.CategoryName, d.DishName;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetKitchenDishes */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetKitchenDishes
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        d.DishName AS [Блюдо],
        c.CategoryName AS [Категория],
        d.BasePrice AS [Цена, руб.],
        s.AvailablePortions AS [Остаток, порций],
        CASE WHEN ISNULL(sl.IsStopListed, 0) = 1 THEN N''Да'' ELSE N''Нет'' END AS [Стоп-лист],
        sl.Reason AS [Причина]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.DishStock s ON s.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    ORDER BY c.CategoryName, d.DishName;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_SetDishStopListStatus */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_SetDishStopListStatus
    @DishId INT,
    @IsStopListed BIT,
    @ChangedByUserId INT,
    @Reason NVARCHAR(300) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @ChangedByUserId
          AND u.IsActive = 1
          AND r.RoleCode IN (''KITCHEN'', ''ADMIN'')
    )
        THROW 51010, N''Изменять стоп-лист могут только кухня и администратор.'', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dish WHERE DishId = @DishId)
        THROW 51011, N''Блюдо не найдено.'', 1;

    IF @IsStopListed = 1 AND NULLIF(LTRIM(RTRIM(@Reason)), N'''') IS NULL
        THROW 51012, N''Укажите причину добавления блюда в стоп-лист.'', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.DishStopList WHERE DishId = @DishId)
        INSERT INTO dbo.DishStopList (DishId, IsStopListed, Reason, ChangedByUserId)
        VALUES (@DishId, 0, NULL, NULL);

    UPDATE dbo.DishStopList
    SET
        IsStopListed = @IsStopListed,
        Reason = CASE WHEN @IsStopListed = 1 THEN @Reason ELSE NULL END,
        ChangedByUserId = @ChangedByUserId,
        ChangedAt = SYSDATETIME()
    WHERE DishId = @DishId;

    SELECT
        CASE WHEN @IsStopListed = 1
             THEN N''Блюдо добавлено в стоп-лист.''
             ELSE N''Блюдо убрано из стоп-листа.''
        END AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetOrderItems */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetOrderItems
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        oi.DishId,
        d.DishName AS [Блюдо],
        oi.Quantity AS [Порций],
        oi.UnitPrice AS [Цена, руб.],
        oi.Quantity * oi.UnitPrice AS [Сумма]
    FROM dbo.OrderItem oi
    JOIN dbo.Dish d ON d.DishId = oi.DishId
    WHERE oi.OrderId = @OrderId
    ORDER BY d.DishName;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CreateOrderForWaiter */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CreateOrderForWaiter
    @WaiterUserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51324, N''Количество гостей должно быть не меньше одного.'', 1;

    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT @TableId = t.TableId, @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @TableId IS NULL
        THROW 51325, N''Столик не найден или отключён.'', 1;

    IF @GuestCount > @SeatsCount
        THROW 51326, N''Количество гостей превышает вместимость выбранного столика.'', 1;

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
          AND ss.StatusCode = ''OPEN''
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51327, N''Сначала откройте запланированную смену. Без открытой смены заказ создать нельзя.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
    )
        THROW 51328, N''У выбранного столика уже есть незавершённый заказ. Столик освободится после закрытия оплаченного счёта.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = @TableId
          AND rs.StatusCode = ''ACTIVE''
          AND SYSDATETIME() >= r.StartAt
          AND SYSDATETIME() < r.EndAt
    )
        THROW 51329, N''Столик забронирован на текущее время.'', 1;

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
        (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = ''DRAFT''),
        ''WAITER'',
        @GuestCount
    );

';
SET @ProcedureSql += N'    SELECT SCOPE_IDENTITY() AS OrderId, N''Заказ создан. Можно добавлять блюда.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CreateClientAppOrder */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CreateClientAppOrder
    @UserId INT,
    @TableNumber INT,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @GuestCount < 1
        THROW 51330, N''Количество гостей должно быть не меньше одного.'', 1;

    DECLARE @ClientId INT = (SELECT ClientId FROM dbo.Client WHERE UserId = @UserId);
    DECLARE @TableId INT;
    DECLARE @SeatsCount INT;

    SELECT @TableId = t.TableId, @SeatsCount = t.SeatsCount
    FROM dbo.RestaurantTable t
    WHERE t.TableNumber = @TableNumber
      AND t.IsActive = 1;

    IF @ClientId IS NULL
        THROW 51331, N''Клиент не найден.'', 1;
    IF @TableId IS NULL
        THROW 51332, N''Столик не найден или отключён.'', 1;
    IF @GuestCount > @SeatsCount
        THROW 51333, N''Количество гостей превышает вместимость выбранного столика.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
    )
        THROW 51334, N''Этот столик занят до закрытия оплаченного счёта.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = @TableId
          AND rs.StatusCode = ''ACTIVE''
          AND SYSDATETIME() >= r.StartAt
          AND SYSDATETIME() < r.EndAt
    )
        THROW 51335, N''Столик забронирован на текущее время.'', 1;

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
        (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = ''DRAFT''),
        ''CLIENT_APP'',
        @GuestCount
    );

    SELECT SCOPE_IDENTITY() AS OrderId, N''Корзина создана. Добавьте блюда и отправьте заказ на кухню.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AddDishToOrder */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AddDishToOrder
    @OrderId INT,
    @DishId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 50037, N''Количество порций должно быть больше нуля.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = ''DRAFT''
    )
        THROW 50038, N''Редактировать можно только заказ в статусе «Составление».'', 1;

    DECLARE @DishName NVARCHAR(150);
    DECLARE @AvailablePortions INT;
    DECLARE @UnitPrice DECIMAL(10,2);
    DECLARE @DiscountPercent DECIMAL(5,2);

    BEGIN TRANSACTION;

    SELECT
        @DishName = d.DishName,
        @AvailablePortions = ds.AvailablePortions
    FROM dbo.Dish d
    JOIN dbo.DishStock ds WITH (UPDLOCK, HOLDLOCK) ON ds.DishId = d.DishId
    WHERE d.DishId = @DishId
      AND d.IsActive = 1;

    IF @DishName IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50039, N''Блюдо не найдено или недоступно для заказа.'', 1;
    END

    IF @AvailablePortions < @Quantity
    BEGIN
        ROLLBACK TRANSACTION;

        DECLARE @StockMessage NVARCHAR(400) =
            CONCAT
            (
                N''Невозможно добавить блюдо в запрашиваемом количестве. Сейчас доступно '',
                @AvailablePortions,
                N'' порций.''
            );

        THROW 50040, @StockMessage, 1;
    END

    SELECT
        @UnitPrice = ActualUnitPrice,
        @DiscountPercent = DiscountPercent
    FROM dbo.fn_GetCurrentDishPrice(@DishId, SYSDATETIME());

    IF EXISTS (SELECT 1 FROM dbo.OrderItem WHERE OrderId = @OrderId AND DishId = @DishId)
    BEGIN
        UPDATE dbo.OrderItem
        SET Quantity = Quantity + @Quantity
        WHERE OrderId = @OrderId
          AND DishId = @DishId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.OrderItem
        (
            OrderId, DishId, Quantity, UnitPrice, DiscountPercent
        )
        VALUES
        (
            @OrderId, @DishId, @Quantity, @UnitPrice, @DiscountPercent
        );
    END

    UPDATE dbo.DishStock
    SET
        AvailablePortions = AvailablePortions - @Quantity,
        UpdatedAt = SYSDATETIME()
    WHERE DishId = @DishId;

    COMMIT TRANSACTION;

    SELECT
        CONCAT
        (
            N''Блюдо «'', @DishName, N''» в количестве '', @Quantity,
            N'' порций было успешно добавлено в Заказ №'', @OrderId
        ) AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_RemoveDishFromOrder */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_RemoveDishFromOrder
    @OrderId INT,
    @DishId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 50041, N''Количество порций должно быть больше нуля.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = ''DRAFT''
    )
        THROW 50042, N''Удалять блюда можно только из заказа в статусе «Составление».'', 1;

    DECLARE @DishName NVARCHAR(150);
    DECLARE @CurrentQuantity INT;

    BEGIN TRANSACTION;

    SELECT
        @DishName = d.DishName,
        @CurrentQuantity = oi.Quantity
    FROM dbo.OrderItem oi WITH (UPDLOCK, HOLDLOCK)
    JOIN dbo.Dish d ON d.DishId = oi.DishId
    WHERE oi.OrderId = @OrderId
      AND oi.DishId = @DishId;

    IF @CurrentQuantity IS NULL
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50043, N''Указанное блюдо отсутствует в заказе.'', 1;
    END

    IF @Quantity > @CurrentQuantity
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50044, N''Нельзя удалить больше порций, чем содержится в заказе.'', 1;
    END

    IF @Quantity = @CurrentQuantity
        DELETE FROM dbo.OrderItem
        WHERE OrderId = @OrderId AND DishId = @DishId;
    ELSE
        UPDATE dbo.OrderItem
        SET Quantity = Quantity - @Quantity
        WHERE OrderId = @OrderId AND DishId = @DishId;

    UPDATE dbo.DishStock
    SET
        AvailablePortions = AvailablePortions + @Quantity,
        UpdatedAt = SYSDATETIME()
    WHERE DishId = @DishId;

    COMMIT TRANSACTION;

    SELECT
        CONCAT
        (
            N''Блюдо «'', @DishName, N''» в количестве '', @Quantity,
            N'' порций было успешно удалено из Заказа №'', @OrderId
        ) AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_FinalizeOrder */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_FinalizeOrder
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE OrderId = @OrderId)
        THROW 51301, N''Нельзя отправить на кухню пустой заказ.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND s.StatusCode = ''DRAFT''
    )
        THROW 51302, N''Заказ уже отправлен на кухню или не найден.'', 1;

    UPDATE dbo.CustomerOrder
    SET
        OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = ''PLACED''),
        FinalizedAt = SYSDATETIME()
    WHERE OrderId = @OrderId;

    SELECT N''Заказ отправлен на кухню. Счёт будет пробит официантом после выдачи заказа.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_SetKitchenOrderStatus */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_SetKitchenOrderStatus
    @OrderId INT,
    @NewStatusCode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewStatusCode NOT IN (''PREPARING'', ''READY'', ''ACCEPTED'')
        THROW 50049, N''Кухня может установить только статусы: Готовится, Готов к выдаче, Принят на выдачу.'', 1;

    DECLARE @CurrentStatusCode VARCHAR(30) =
    (
        SELECT os.StatusCode
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
    );

    IF @CurrentStatusCode IS NULL
        THROW 50050, N''Заказ не найден.'', 1;

    IF (@NewStatusCode = ''PREPARING'' AND @CurrentStatusCode <> ''PLACED'')
       OR (@NewStatusCode = ''READY'' AND @CurrentStatusCode <> ''PREPARING'')
       OR (@NewStatusCode = ''ACCEPTED'' AND @CurrentStatusCode <> ''READY'')
        THROW 50051, N''Неверная последовательность изменения статуса заказа.'', 1;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId =
    (
        SELECT OrderStatusId
        FROM dbo.OrderStatus
        WHERE StatusCode = @NewStatusCode
    )
    WHERE OrderId = @OrderId;

    SELECT N''Статус заказа успешно изменен кухней.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetKitchenOrders */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetKitchenOrders
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        s.StatusName AS Статус,
        CASE
            WHEN o.ChannelCode = ''CLIENT_APP'' THEN N''Клиентское приложение''
            ELSE N''Официант''
        END AS Источник,
        c.FullName AS Клиент,
        SUM(ISNULL(oi.Quantity, 0)) AS Порций
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Client c ON c.ClientId = o.ClientId
    LEFT JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    WHERE s.StatusCode IN (''PLACED'', ''PREPARING'', ''READY'')
    GROUP BY o.OrderId, t.TableNumber, s.StatusName, o.ChannelCode, c.FullName
    ORDER BY o.OrderId DESC;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetOrdersForWaiter */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetOrdersForWaiter
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
          AND ss.StatusCode = ''OPEN''
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
            WHEN b.BillId IS NULL THEN N''Не пробит''
            WHEN b.IsPaid = 1 THEN N''Оплачен''
            WHEN b.IssuedAt IS NULL THEN N''Не пробит''
            ELSE N''Ожидает оплаты''
        END AS [Счёт],
        CAST(CASE WHEN b.IssuedAt IS NULL THEN 0 ELSE 1 END AS BIT) AS BillIssued,
        CAST(ISNULL(b.IsPaid, 0) AS BIT) AS BillPaid
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    WHERE s.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
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
';
SET @ProcedureSql += N'END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_WaiterServeOrder */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_WaiterServeOrder
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
          AND ss.StatusCode = ''OPEN''
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51305, N''Сначала откройте смену.'', 1;

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
        THROW 51306, N''Заказ не найден.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterTableAssignment
        WHERE ShiftId = @ShiftId
          AND TableId = @TableId
    )
        THROW 51307, N''Этот столик не закреплён за вами в открытой смене.'', 1;

    IF @OrderShiftId IS NOT NULL AND @OrderShiftId <> @ShiftId
        THROW 51308, N''Этот заказ закреплён за другим официантом.'', 1;

    IF @CurrentStatus <> ''ACCEPTED''
        THROW 51309, N''Принести можно только заказ со статусом «Принят на выдачу».'', 1;

    BEGIN TRANSACTION;

    UPDATE dbo.CustomerOrder
    SET
        WaiterShiftId = @ShiftId,
        OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = ''ISSUED'')
    WHERE OrderId = @OrderId;

    COMMIT TRANSACTION;

    SELECT N''Заказ выдан клиенту. Теперь можно пробить счёт.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_WaiterCreateBill */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_WaiterCreateBill
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
          AND ss.StatusCode = ''OPEN''
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51310, N''Сначала откройте смену.'', 1;

    DECLARE @OrderShiftId INT;
    DECLARE @StatusCode VARCHAR(20);
    SELECT
        @OrderShiftId = o.WaiterShiftId,
        @StatusCode = s.StatusCode
    FROM dbo.CustomerOrder o
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    WHERE o.OrderId = @OrderId;

    IF @StatusCode IS NULL
        THROW 51311, N''Заказ не найден.'', 1;

    IF @OrderShiftId <> @ShiftId
        THROW 51312, N''Пробить счёт может только официант, который выдал заказ клиенту.'', 1;

    IF @StatusCode <> ''ISSUED''
        THROW 51313, N''Счёт можно пробить только после выдачи заказа клиенту.'', 1;

    DECLARE @Amount DECIMAL(12,2) =
    (
        SELECT SUM(oi.Quantity * oi.UnitPrice)
        FROM dbo.OrderItem oi
        WHERE oi.OrderId = @OrderId
    );

    IF @Amount IS NULL OR @Amount <= 0
        THROW 51314, N''В заказе нет блюд для формирования счёта.'', 1;

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
            THROW 51315, N''Этот счёт уже оплачен.'', 1;
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
        CONCAT(N''Счёт пробит на сумму '', FORMAT(@Amount, ''N2'', ''ru-RU''), N'' руб. Ожидается оплата.'') AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_WaiterCloseBill */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_WaiterCloseBill
    @WaiterUserId INT,
    @OrderId INT,
    @PaymentMethod NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PaymentMethod NOT IN (N''Наличные'', N''Карта'')
        THROW 51316, N''Выберите способ оплаты: «Наличные» или «Карта».'', 1;

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @WaiterUserId
          AND ss.StatusCode = ''OPEN''
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC
    );

    IF @ShiftId IS NULL
        THROW 51317, N''Сначала откройте смену.'', 1;

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
        THROW 51318, N''Заказ не найден.'', 1;

    IF @OrderShiftId <> @ShiftId
        THROW 51319, N''Закрыть счёт может только официант, который выдал заказ клиенту.'', 1;

    IF @StatusCode <> ''ISSUED''
        THROW 51320, N''Закрыть можно только счёт по выданному клиенту заказу.'', 1;

    IF @BillId IS NULL OR @BillIssuedAt IS NULL
        THROW 51321, N''Сначала пробейте счёт.'', 1;

    IF @BillPaid = 1
        THROW 51322, N''Этот счёт уже закрыт.'', 1;

    DECLARE @ReceiptNumber NVARCHAR(50) =
        CONCAT(N''WR-'', FORMAT(SYSDATETIME(), ''yyyyMMddHHmmss''), N''-'', @OrderId);

    BEGIN TRANSACTION;

    UPDATE dbo.Bill
    SET
        IsPaid = 1,
        PaidAt = SYSDATETIME(),
        PaymentMethod = @PaymentMethod,
        ReceiptNumber = @ReceiptNumber
    WHERE BillId = @BillId;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = ''COMPLETED'')
    WHERE OrderId = @OrderId;

    /* Если столик был занят текущей бронью, она завершается вместе с оплачиваемым заказом. */
    UPDATE r
    SET ReservationStatusId =
    (
        SELECT ReservationStatusId
        FROM dbo.ReservationStatus
';
SET @ProcedureSql += N'        WHERE StatusCode = ''COMPLETED''
    )
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE rt.TableId = @TableId
      AND rs.StatusCode = ''ACTIVE''
      AND SYSDATETIME() >= r.StartAt
      AND SYSDATETIME() < r.EndAt;

    COMMIT TRANSACTION;

    SELECT
        @ReceiptNumber AS ReceiptNumber,
        @Amount AS Amount,
        CONCAT(N''Счёт закрыт. Оплата принята: '', @PaymentMethod, N''. Столик освобождён.'') AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_FreeTable */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_FreeTable
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    THROW 51323, N''Столик освобождается автоматически только после: выдать заказ → пробить счёт → закрыть счёт.'', 1;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminSalesReport */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminSalesReport
    @DateFrom DATE,
    @DateTo DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @DateTo < @DateFrom
        THROW 51401, N''Дата окончания периода не может быть раньше даты начала.'', 1;

    DECLARE @StartDateTime DATETIME2 = CAST(@DateFrom AS DATETIME2);
    DECLARE @EndDateTime DATETIME2 = DATEADD(DAY, 1, CAST(@DateTo AS DATETIME2));

    SELECT
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        SUM(oi.Quantity) AS [Продано порций],
        COUNT(DISTINCT o.OrderId) AS [Заказов],
        CAST(SUM(oi.Quantity * oi.UnitPrice) AS DECIMAL(12,2)) AS [Выручка, руб.]
    FROM dbo.Bill b
    JOIN dbo.CustomerOrder o ON o.OrderId = b.OrderId
    JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
    JOIN dbo.Dish d ON d.DishId = oi.DishId
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    WHERE b.IsPaid = 1
      AND COALESCE(b.PaidAt, b.IssuedAt, o.FinalizedAt, o.CreatedAt) >= @StartDateTime
      AND COALESCE(b.PaidAt, b.IssuedAt, o.FinalizedAt, o.CreatedAt) < @EndDateTime
    GROUP BY c.CategoryName, d.DishName
    ORDER BY c.CategoryName, d.DishName;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminGetStock */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStock
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        ds.AvailablePortions AS [Остаток, порций],
        CASE WHEN ISNULL(sl.IsStopListed, 0) = 1 THEN N''Да'' ELSE N''Нет'' END AS [Стоп-лист],
        CASE WHEN d.IsActive = 1 THEN N''Да'' ELSE N''Нет'' END AS [Доступно в меню]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    LEFT JOIN dbo.DishStock ds ON ds.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    ORDER BY c.CategoryName, d.DishName;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminGetStockMovements */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStockMovements
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
        m.StockMovementId,
        m.CreatedAt AS [Дата и время],
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        m.Quantity AS [Добавлено порций],
        CONCAT(u.LastName, N'' '', u.FirstName) AS [Администратор],
        m.Comment AS [Комментарий]
    FROM dbo.DishStockMovement m
    JOIN dbo.Dish d ON d.DishId = m.DishId
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.AppUser u ON u.UserId = m.AdminUserId
    ORDER BY m.CreatedAt DESC, m.StockMovementId DESC;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminRestockDish */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminRestockDish
    @AdminUserId INT,
    @DishId INT,
    @Quantity INT,
    @Comment NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 51402, N''Количество порций для пополнения должно быть больше нуля.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @AdminUserId
          AND u.IsActive = 1
          AND r.RoleCode = ''ADMIN''
    )
        THROW 51403, N''Пополнять склад может только активный администратор.'', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dish WHERE DishId = @DishId)
        THROW 51404, N''Блюдо не найдено.'', 1;

    DECLARE @DishName NVARCHAR(150);
    DECLARE @NewStock INT;

    BEGIN TRANSACTION;

    SELECT @DishName = DishName
    FROM dbo.Dish
    WHERE DishId = @DishId;

    IF EXISTS (SELECT 1 FROM dbo.DishStock WITH (UPDLOCK, HOLDLOCK) WHERE DishId = @DishId)
    BEGIN
        UPDATE dbo.DishStock
        SET AvailablePortions = AvailablePortions + @Quantity
        WHERE DishId = @DishId;
    END
    ELSE
    BEGIN
        INSERT INTO dbo.DishStock(DishId, AvailablePortions)
        VALUES(@DishId, @Quantity);
    END

    SELECT @NewStock = AvailablePortions
    FROM dbo.DishStock
    WHERE DishId = @DishId;

    INSERT INTO dbo.DishStockMovement(DishId, Quantity, OperationType, AdminUserId, Comment)
    VALUES(@DishId, @Quantity, ''RESTOCK'', @AdminUserId, @Comment);

    COMMIT TRANSACTION;

    SELECT
        CONCAT(N''Склад пополнен: «'', @DishName, N''» +'', @Quantity, N'' порц. Текущий остаток: '', @NewStock, N'' порц.'') AS Message,
        @NewStock AS AvailablePortions;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_AdminGetOrderStatuses */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_AdminGetOrderStatuses
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        os.StatusName AS [Статус заказа],
        CASE WHEN o.ChannelCode = ''CLIENT_APP'' THEN N''Клиентское приложение'' ELSE N''Официант'' END AS [Источник],
        ISNULL(c.FullName, N''Гость'') AS [Клиент],
        CONCAT(ISNULL(wu.LastName, N''Не назначен''), N'' '', ISNULL(wu.FirstName, N'''')) AS [Официант],
        o.CreatedAt AS [Создан],
        o.FinalizedAt AS [Отправлен на кухню],
        CASE
            WHEN b.BillId IS NULL THEN N''Не пробит''
            WHEN b.IsPaid = 1 THEN N''Оплачен''
            WHEN b.IssuedAt IS NOT NULL THEN N''Ожидает оплаты''
            ELSE N''Не пробит''
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
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetClientOrderStatuses */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetClientOrderStatuses
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @ClientId INT = (SELECT ClientId FROM dbo.Client WHERE UserId = @UserId);

    IF @ClientId IS NULL
        THROW 51421, N''Клиент не найден.'', 1;

    SELECT
        o.OrderId,
        o.OrderId AS [№ заказа],
        t.TableNumber AS [№ столика],
        os.StatusName AS [Статус заказа],
        o.CreatedAt AS [Создан],
        o.FinalizedAt AS [Отправлен на кухню],
        CASE
            WHEN b.BillId IS NULL THEN N''Не пробит''
            WHEN b.IsPaid = 1 THEN N''Оплачен''
            WHEN b.IssuedAt IS NOT NULL THEN N''Ожидает оплаты''
            ELSE N''Не пробит''
        END AS [Счёт]
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
    LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
    WHERE o.ClientId = @ClientId
    ORDER BY o.CreatedAt DESC, o.OrderId DESC;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CreateReservationSafe */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CreateReservationSafe
    @UserId INT = NULL,
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30) = NULL,
    @StartAt DATETIME2,
    @EndAt DATETIME2,
    @GuestCount INT,
    @TableNumbers NVARCHAR(100)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @NormalizedLastName NVARCHAR(60) = LTRIM(RTRIM(@LastName));
    DECLARE @NormalizedFirstName NVARCHAR(60) = LTRIM(RTRIM(@FirstName));
    DECLARE @NormalizedPhone NVARCHAR(30) = NULLIF(LTRIM(RTRIM(@Phone)), N'''');
    DECLARE @FullName NVARCHAR(150);
    DECLARE @ClientId INT;
    DECLARE @ReservationId INT;
    DECLARE @ActiveReservationStatusId INT;

    IF @NormalizedLastName = N'''' OR @NormalizedFirstName = N''''
        THROW 51601, N''Укажите фамилию и имя гостя.'', 1;

    IF @GuestCount < 1
        THROW 51602, N''Количество гостей должно быть не меньше одного.'', 1;

    IF @EndAt <= @StartAt
       OR CONVERT(DATE, @StartAt) <> CONVERT(DATE, @EndAt)
       OR CONVERT(TIME, @StartAt) < ''09:00''
       OR CONVERT(TIME, @EndAt) > ''23:00''
        THROW 51603, N''Бронь возможна в один день с 09:00 до 23:00. Укажите корректный интервал.'', 1;

    SET @FullName = CONCAT(@NormalizedLastName, N'' '', @NormalizedFirstName);
    SET @NormalizedPhone = COALESCE(@NormalizedPhone, N''Не указан'');

    DECLARE @Selected TABLE (TableId INT NOT NULL PRIMARY KEY);

    INSERT INTO @Selected (TableId)
    SELECT DISTINCT t.TableId
    FROM dbo.RestaurantTable t
    JOIN STRING_SPLIT(@TableNumbers, N'','') x
      ON LTRIM(RTRIM(x.value)) = CONVERT(NVARCHAR(10), t.TableNumber)
    WHERE t.IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM @Selected)
        THROW 51604, N''Выберите существующий активный столик.'', 1;

    IF @GuestCount >
    (
        SELECT SUM(t.SeatsCount)
        FROM dbo.RestaurantTable t
        JOIN @Selected s ON s.TableId = t.TableId
    )
        THROW 51605, N''Недостаточно мест за выбранным столиком.'', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        JOIN @Selected s ON s.TableId = rt.TableId
        WHERE rs.StatusCode = ''ACTIVE''
          AND @StartAt < r.EndAt
          AND @EndAt > r.StartAt
    )
        THROW 51606, N''Выбранный столик уже забронирован на это время.'', 1;

    BEGIN TRANSACTION;

    IF @UserId IS NOT NULL
    BEGIN
        SELECT @ClientId = c.ClientId
        FROM dbo.Client c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.UserId = @UserId;

        IF @ClientId IS NULL
            THROW 51607, N''Профиль авторизованного клиента не найден. Обратитесь к администратору.'', 1;
    END
';
SET @ProcedureSql += N'    ELSE
    BEGIN
        SELECT TOP (1) @ClientId = c.ClientId
        FROM dbo.Client c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.UserId IS NULL
          AND c.FullName = @FullName
          AND c.Phone = @NormalizedPhone
        ORDER BY c.ClientId;

        IF @ClientId IS NULL
        BEGIN
            INSERT INTO dbo.Client (UserId, FullName, Phone)
            VALUES (NULL, @FullName, @NormalizedPhone);
            SET @ClientId = CONVERT(INT, SCOPE_IDENTITY());
        END
    END

    SELECT @ActiveReservationStatusId = ReservationStatusId
    FROM dbo.ReservationStatus
    WHERE StatusCode = ''ACTIVE'';

    IF @ActiveReservationStatusId IS NULL
        THROW 51608, N''Не найден статус ACTIVE для бронирования.'', 1;

    INSERT INTO dbo.Reservation (ClientId, ReservationStatusId, StartAt, EndAt, GuestCount)
    VALUES (@ClientId, @ActiveReservationStatusId, @StartAt, @EndAt, @GuestCount);

    SET @ReservationId = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.ReservationTable (ReservationId, TableId)
    SELECT @ReservationId, TableId FROM @Selected;

    COMMIT TRANSACTION;

    SELECT @ReservationId AS ReservationId, N''Бронь успешно создана.'' AS Message;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetReservationTableMap */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetReservationTableMap
    @StartAt DATETIME2,
    @EndAt DATETIME2,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @EndAt <= @StartAt
        THROW 51609, N''Время окончания должно быть больше времени начала.'', 1;

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        CAST(CASE
            WHEN t.SeatsCount < @GuestCount THEN 0
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.Reservation r
                JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
                JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
                WHERE rt.TableId = t.TableId
                  AND rs.StatusCode = ''ACTIVE''
                  AND @StartAt < r.EndAt
                  AND @EndAt > r.StartAt
            ) THEN 0
            ELSE 1
        END AS bit) AS IsAvailable,
        CASE
            WHEN t.SeatsCount < @GuestCount THEN N''Мало мест''
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.Reservation r
                JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
                JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
                WHERE rt.TableId = t.TableId
                  AND rs.StatusCode = ''ACTIVE''
                  AND @StartAt < r.EndAt
                  AND @EndAt > r.StartAt
            ) THEN N''Забронирован''
            ELSE N''Свободен''
        END AS AvailabilityReason
    FROM dbo.RestaurantTable t
    WHERE t.IsActive = 1
    ORDER BY t.TableNumber;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetReservationDayTableMap */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetReservationDayTableMap
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
                  AND os.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
            ) THEN N''Занят заказом''
            WHEN ISNULL(dayReservations.ReservationCount, 0) > 0 THEN N''Есть брони''
            ELSE N''Свободен''
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
          AND rs.StatusCode = ''ACTIVE''
          AND r.StartAt < @DayEnd
          AND r.EndAt > @DayStart
    ) dayReservations
    WHERE t.IsActive = 1
    ORDER BY t.TableNumber;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetReservationsByTableAndDate */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetReservationsByTableAndDate
    @ReservationDate DATE,
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.RestaurantTable WHERE TableId = @TableId AND IsActive = 1)
        THROW 51701, N''Выбранный столик не найден или отключён.'', 1;

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
      AND rs.StatusCode = ''ACTIVE''
      AND r.StartAt < @DayEnd
      AND r.EndAt > @DayStart
    ORDER BY r.StartAt, r.ReservationId;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetClientReservations */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetClientReservations
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
          AND role.RoleCode = ''CLIENT''
    )
        THROW 51801, N''Просматривать личные брони может только активный клиент.'', 1;

    SELECT
        r.ReservationId,
        r.StartAt AS [Начало],
        r.EndAt AS [Конец],
        r.GuestCount AS [Гостей],
        rs.StatusName AS [Статус],
        STRING_AGG(CONVERT(NVARCHAR(10), t.TableNumber), N'', '') AS [Столики]
    FROM dbo.Reservation r
    JOIN dbo.Client c ON c.ClientId = r.ClientId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
    WHERE c.UserId = @UserId
      AND rs.StatusCode = ''ACTIVE''
    GROUP BY
        r.ReservationId,
        r.StartAt,
        r.EndAt,
        r.GuestCount,
        rs.StatusName
    ORDER BY r.StartAt DESC, r.ReservationId DESC;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_CancelReservation */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_CancelReservation
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
        THROW 51802, N''Пользователь не найден или его учетная запись отключена.'', 1;

    IF @RoleCode NOT IN (''CLIENT'', ''ADMIN'')
        THROW 51803, N''Отменять бронирования могут только клиент-владелец или администратор.'', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE r.ReservationId = @ReservationId
          AND rs.StatusCode = ''ACTIVE''
    )
        THROW 51804, N''Активная бронь с указанным номером не найдена.'', 1;

    IF @RoleCode = ''CLIENT''
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.Reservation r
           JOIN dbo.Client c ON c.ClientId = r.ClientId
           WHERE r.ReservationId = @ReservationId
             AND c.UserId = @RequesterUserId
       )
        THROW 51805, N''Клиент может отменить только собственную бронь.'', 1;

    UPDATE dbo.Reservation
    SET ReservationStatusId =
    (
        SELECT ReservationStatusId
        FROM dbo.ReservationStatus
        WHERE StatusCode = ''CANCELLED''
    )
    WHERE ReservationId = @ReservationId;

    SELECT N''Бронь успешно отменена.'' AS Message;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetWaiterReservationDayTableMap */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterReservationDayTableMap
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
          AND role.RoleCode = ''WAITER''
    )
        THROW 51806, N''Пользователь не является активным официантом.'', 1;

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
          AND ss.StatusCode = ''OPEN''
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
                  AND orderStatus.StatusCode IN (''DRAFT'', ''PLACED'', ''PREPARING'', ''READY'', ''ACCEPTED'', ''ISSUED'')
            ) THEN N''Занят заказом''
            WHEN ISNULL(dayReservations.ReservationCount, 0) > 0 THEN N''Есть брони''
            ELSE N''Свободен''
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
          AND rs.StatusCode = ''ACTIVE''
          AND r.StartAt < @DayEnd
          AND r.EndAt > @DayStart
    ) dayReservations
    ORDER BY assigned.TableNumber;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetWaiterReservationsByTableAndDate */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterReservationsByTableAndDate
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
          AND ss.StatusCode = ''OPEN''
          AND ws.ActualOpenAt IS NOT NULL
          AND ws.ActualCloseAt IS NULL
          AND t.TableId = @TableId
          AND t.IsActive = 1
    )
        THROW 51807, N''Выбранный столик не назначен текущему официанту.'', 1;

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
      AND rs.StatusCode = ''ACTIVE''
      AND r.StartAt < @DayEnd
      AND r.EndAt > @DayStart
    ORDER BY r.StartAt, r.ReservationId;
END;';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAdminWaiterShiftsFiltered */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShiftsFiltered
    @ShiftDate DATE = NULL,
    @WaiterUserId INT = NULL,
    @StatusCode VARCHAR(20) = NULL,
    @ShiftType VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    IF @StatusCode IS NOT NULL AND @StatusCode NOT IN (''PLANNED'', ''OPEN'', ''CLOSED'')
        THROW 51702, N''Указан неизвестный статус смены.'', 1;

    IF @ShiftType IS NOT NULL AND @ShiftType NOT IN (''SCHEDULED'', ''WALKIN'')
        THROW 51703, N''Указан неизвестный тип смены.'', 1;

    SELECT
        ws.ShiftId,
        u.UserId AS WaiterUserId,
        CONCAT(u.LastName, N'' '', u.FirstName) AS [Официант],
        CASE WHEN ws.IsWalkInShift = 1 THEN N''Самостоятельная'' ELSE N''По графику'' END AS [Тип смены],
        CASE WHEN ws.IsWalkInShift = 1 THEN ''WALKIN'' ELSE ''SCHEDULED'' END AS ShiftTypeCode,
        ws.PlannedStartAt AS [Начало по графику],
        ws.PlannedEndAt AS [Конец по графику],
        ws.ActualOpenAt AS [Фактическое открытие],
        ws.ActualCloseAt AS [Фактическое закрытие],
        ss.StatusName AS [Статус],
        ss.StatusCode,
        ISNULL(ws.CloseReason, N''—'') AS [Причина закрытия],
        CASE WHEN ws.WasClosedAutomatically = 1 THEN N''Да'' ELSE N''Нет'' END AS [Автозакрытие],
        ISNULL(STRING_AGG(CONCAT(N''№'', t.TableNumber), N'', ''), N''—'') AS [Столики]
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
           OR (@ShiftType = ''WALKIN'' AND ws.IsWalkInShift = 1)
           OR (@ShiftType = ''SCHEDULED'' AND ws.IsWalkInShift = 0))
    GROUP BY
        ws.ShiftId, u.UserId, u.LastName, u.FirstName, ws.IsWalkInShift,
        ws.PlannedStartAt, ws.PlannedEndAt, ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ss.StatusCode, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY COALESCE(ws.ActualOpenAt, ws.PlannedStartAt) DESC, ws.ShiftId DESC;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* sp_GetAdminWaiterShifts */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_GetAdminWaiterShiftsFiltered;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO


/* Совместимость с ранней сборкой программы, которая использовала это имя. */
DECLARE @ProcedureSql NVARCHAR(MAX) = N'';
SET @ProcedureSql += N'CREATE OR ALTER PROCEDURE dbo.sp_GetAdminShiftsFiltered
    @ShiftDate DATE = NULL,
    @WaiterUserId INT = NULL,
    @StatusCode VARCHAR(20) = NULL,
    @ShiftType VARCHAR(20) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_GetAdminWaiterShiftsFiltered
        @ShiftDate = @ShiftDate,
        @WaiterUserId = @WaiterUserId,
        @StatusCode = @StatusCode,
        @ShiftType = @ShiftType;
END';
EXEC sys.sp_executesql @ProcedureSql;
GO

/* ===== 6. Контроль результата ===== */
DECLARE @RequiredObjects TABLE (ObjectName SYSNAME NOT NULL, ObjectType CHAR(2) NOT NULL);
INSERT INTO @RequiredObjects (ObjectName, ObjectType)
VALUES
    (N'DishStopList', N'U'),
    (N'sp_GetAvailableMenu', N'P'),
    (N'sp_GetKitchenDishes', N'P'),
    (N'sp_SetDishStopListStatus', N'P'),
    (N'sp_GetReservationDayTableMap', N'P'),
    (N'sp_GetReservationsByTableAndDate', N'P'),
    (N'sp_GetAdminWaiterShiftsFiltered', N'P'),
    (N'sp_GetAdminShiftsFiltered', N'P'),
    (N'sp_GetClientReservations', N'P'),
    (N'sp_GetWaiterReservationDayTableMap', N'P'),
    (N'sp_GetWaiterReservationsByTableAndDate', N'P'),
    (N'sp_GetKitchenOrders', N'P'),
    (N'sp_CreateOrderForWaiter', N'P'),
    (N'sp_CreateClientAppOrder', N'P'),
    (N'sp_AdminGetOrderStatuses', N'P'),
    (N'sp_GetClientOrderStatuses', N'P');

/*
   Совместимый с SQL Server синтаксис: в THROW нельзя передавать выражение
   CONCAT(...). Сначала формируем текст в переменной, затем передаём переменную.
   STRING_AGG также заменён на FOR XML PATH, чтобы финальная проверка не
   зависела от уровня совместимости базы.
*/
DECLARE @Missing NVARCHAR(MAX);

SELECT @Missing = STUFF
(
    (
        SELECT N', ' + required.ObjectName
        FROM @RequiredObjects AS required
        WHERE OBJECT_ID(N'dbo.' + required.ObjectName, required.ObjectType) IS NULL
        ORDER BY required.ObjectName
        FOR XML PATH(N''), TYPE
    ).value(N'.', N'nvarchar(max)'),
    1,
    2,
    N''
);

IF NULLIF(@Missing, N'') IS NOT NULL
BEGIN
    DECLARE @RepairErrorMessage NVARCHAR(2048);
    SET @RepairErrorMessage = N'Восстановление завершилось не полностью. Отсутствуют: ' + @Missing;
    THROW 51902, @RepairErrorMessage, 1;
END;

IF COL_LENGTH(N'dbo.CustomerOrder', N'ClientId') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'ChannelCode') IS NULL
   OR COL_LENGTH(N'dbo.CustomerOrder', N'GuestCount') IS NULL
    THROW 51903, N'Не удалось восстановить поля ClientId, ChannelCode и GuestCount в CustomerOrder.', 1;

SELECT
    CAST(SERVERPROPERTY(N'ServerName') AS NVARCHAR(256)) AS [SQL Server],
    DB_NAME() AS [База данных],
    N'White Rabbit v3.4: все объекты для приложения восстановлены, финальная проверка выполнена.' AS [Результат];
GO
