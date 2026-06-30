/*
 White Rabbit v2.5 — исправление бронирования гостей.

 Причина ошибки:
 В старой схеме на dbo.Client был UNIQUE constraint для UserId.
 SQL Server допускает только одно значение NULL в таком constraint,
 поэтому второе бронирование гостя без учётной записи не создавалось.

 Исправление:
 1) Удаляется старое UNIQUE-ограничение для Client.UserId.
 2) Создаётся FILTERED UNIQUE INDEX: уникальны только заполненные UserId.
    Гости без учётной записи могут иметь UserId = NULL в нескольких строках.
 3) Процедура бронирования использует Client текущего пользователя,
    если бронирует авторизованный клиент; для гостей находит запись по ФИО и телефону.

 Запустите ОДИН РАЗ в SSMS в базе WhiteRabbitRestaurant.
*/
USE WhiteRabbitRestaurant;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Проверка на случай ручного нарушения данных. */
IF EXISTS
(
    SELECT UserId
    FROM dbo.Client
    WHERE UserId IS NOT NULL
    GROUP BY UserId
    HAVING COUNT(*) > 1
)
    THROW 51450, N'Найдены повторяющиеся заполненные UserId в dbo.Client. Исправьте данные перед обновлением.', 1;
GO

/*
 Удаляем только UNIQUE constraint, который состоит из единственного столбца Client.UserId.
 Имя ограничение определяется автоматически, поэтому скрипт работает и при имени вида UQ__Client__....
*/
DECLARE @ConstraintName SYSNAME;
DECLARE @DropSql NVARCHAR(MAX);

SELECT TOP (1) @ConstraintName = kc.name
FROM sys.key_constraints kc
JOIN sys.index_columns ic
    ON ic.object_id = kc.parent_object_id
   AND ic.index_id = kc.unique_index_id
WHERE kc.parent_object_id = OBJECT_ID(N'dbo.Client')
  AND kc.type = 'UQ'
GROUP BY kc.name, kc.parent_object_id, kc.unique_index_id
HAVING COUNT(*) = 1
   AND MAX(COL_NAME(ic.object_id, ic.column_id)) = N'UserId';

IF @ConstraintName IS NOT NULL
BEGIN
    SET @DropSql = N'ALTER TABLE dbo.Client DROP CONSTRAINT ' + QUOTENAME(@ConstraintName) + N';';
    EXEC sys.sp_executesql @DropSql;
END
GO

/* Уникальность сохраняется для зарегистрированных пользователей, но не для NULL. */
IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE object_id = OBJECT_ID(N'dbo.Client')
      AND name = N'UX_Client_UserId_NotNull'
)
BEGIN
    CREATE UNIQUE INDEX UX_Client_UserId_NotNull
        ON dbo.Client(UserId)
        WHERE UserId IS NOT NULL;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateReservationByClientName
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
    DECLARE @NormalizedPhone NVARCHAR(30) = NULLIF(LTRIM(RTRIM(@Phone)), N'');
    DECLARE @FullName NVARCHAR(150);
    DECLARE @ClientId INT;
    DECLARE @ReservationId INT;
    DECLARE @ActiveReservationStatusId INT;

    IF @NormalizedLastName = N'' OR @NormalizedFirstName = N''
        THROW 51451, N'Укажите фамилию и имя гостя.', 1;

    IF @GuestCount < 1
        THROW 51452, N'Количество гостей должно быть не меньше одного.', 1;

    IF @EndAt <= @StartAt
       OR CONVERT(DATE, @StartAt) <> CONVERT(DATE, @EndAt)
       OR CONVERT(TIME, @StartAt) < '09:00'
       OR CONVERT(TIME, @EndAt) > '23:00'
        THROW 51453, N'Бронь возможна в один день с 09:00 до 23:00. Укажите корректный интервал.', 1;

    SET @FullName = CONCAT(@NormalizedLastName, N' ', @NormalizedFirstName);
    SET @NormalizedPhone = COALESCE(@NormalizedPhone, N'Не указан');

    DECLARE @Selected TABLE (TableId INT NOT NULL PRIMARY KEY);

    INSERT INTO @Selected (TableId)
    SELECT DISTINCT t.TableId
    FROM dbo.RestaurantTable t
    JOIN STRING_SPLIT(@TableNumbers, N',') x
      ON LTRIM(RTRIM(x.value)) = CONVERT(NVARCHAR(10), t.TableNumber)
    WHERE t.IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM @Selected)
        THROW 51454, N'Укажите существующий активный столик.', 1;

    IF @GuestCount >
    (
        SELECT SUM(t.SeatsCount)
        FROM dbo.RestaurantTable t
        JOIN @Selected s ON s.TableId = t.TableId
    )
        THROW 51455, N'Недостаточно мест за выбранным столиком.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        JOIN @Selected s ON s.TableId = rt.TableId
        WHERE rs.StatusCode = 'ACTIVE'
          AND @StartAt < r.EndAt
          AND @EndAt > r.StartAt
    )
        THROW 51456, N'Выбранный столик уже забронирован на это время.', 1;

    BEGIN TRANSACTION;

    /* Зарегистрированный клиент: бронирование привязывается к его профилю. */
    IF @UserId IS NOT NULL
    BEGIN
        SELECT @ClientId = c.ClientId
        FROM dbo.Client c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.UserId = @UserId;

        IF @ClientId IS NULL
            THROW 51457, N'Профиль авторизованного клиента не найден. Обратитесь к администратору.', 1;
    END
    ELSE
    BEGIN
        /* Гость без учётной записи: повторно используем запись с теми же ФИО и телефоном. */
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
    WHERE StatusCode = 'ACTIVE';

    IF @ActiveReservationStatusId IS NULL
        THROW 51458, N'Не найден статус ACTIVE для бронирования.', 1;

    INSERT INTO dbo.Reservation
    (
        ClientId,
        ReservationStatusId,
        StartAt,
        EndAt,
        GuestCount
    )
    VALUES
    (
        @ClientId,
        @ActiveReservationStatusId,
        @StartAt,
        @EndAt,
        @GuestCount
    );

    SET @ReservationId = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.ReservationTable (ReservationId, TableId)
    SELECT @ReservationId, TableId
    FROM @Selected;

    COMMIT TRANSACTION;

    SELECT
        @ReservationId AS ReservationId,
        N'Бронь успешно создана.' AS Message;
END
GO

PRINT N'White Rabbit v2.5: ошибка UNIQUE KEY при бронировании гостей исправлена.';
GO
