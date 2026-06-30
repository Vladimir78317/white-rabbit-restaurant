/* ================================================================
   White Rabbit v2.6
   Fixes reservation procedure parameter mismatch and creates client table map.
   Run this file in SQL Server Management Studio before starting v2.6.
   ================================================================ */
USE WhiteRabbitRestaurant;
GO

SET NOCOUNT ON;
GO

/* Remove a legacy UNIQUE constraint/index that incorrectly allows only one NULL Client.UserId. */
DECLARE @sql NVARCHAR(MAX) = N'';

SELECT @sql = @sql + N'ALTER TABLE dbo.Client DROP CONSTRAINT ' + QUOTENAME(kc.name) + N';' + CHAR(10)
FROM sys.key_constraints kc
JOIN sys.index_columns ic
  ON ic.object_id = kc.parent_object_id
 AND ic.index_id = kc.unique_index_id
JOIN sys.columns c
  ON c.object_id = ic.object_id
 AND c.column_id = ic.column_id
WHERE kc.parent_object_id = OBJECT_ID(N'dbo.Client')
  AND kc.type = 'UQ'
GROUP BY kc.name, kc.parent_object_id, kc.unique_index_id
HAVING COUNT(*) = 1 AND MAX(c.name) = N'UserId';

IF @sql <> N'' EXEC sys.sp_executesql @sql;
GO

IF EXISTS
(
    SELECT 1
    FROM sys.indexes i
    WHERE i.object_id = OBJECT_ID(N'dbo.Client')
      AND i.name = N'UX_Client_UserId_NotNull'
)
    DROP INDEX UX_Client_UserId_NotNull ON dbo.Client;
GO

CREATE UNIQUE INDEX UX_Client_UserId_NotNull
    ON dbo.Client(UserId)
    WHERE UserId IS NOT NULL;
GO

/*
  New procedure name prevents parameter mismatches with the legacy
  sp_CreateReservationByClientName procedure from older project versions.
*/
CREATE OR ALTER PROCEDURE dbo.sp_CreateReservationSafe
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
        THROW 51601, N'Укажите фамилию и имя гостя.', 1;

    IF @GuestCount < 1
        THROW 51602, N'Количество гостей должно быть не меньше одного.', 1;

    IF @EndAt <= @StartAt
       OR CONVERT(DATE, @StartAt) <> CONVERT(DATE, @EndAt)
       OR CONVERT(TIME, @StartAt) < '09:00'
       OR CONVERT(TIME, @EndAt) > '23:00'
        THROW 51603, N'Бронь возможна в один день с 09:00 до 23:00. Укажите корректный интервал.', 1;

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
        THROW 51604, N'Выберите существующий активный столик.', 1;

    IF @GuestCount >
    (
        SELECT SUM(t.SeatsCount)
        FROM dbo.RestaurantTable t
        JOIN @Selected s ON s.TableId = t.TableId
    )
        THROW 51605, N'Недостаточно мест за выбранным столиком.', 1;

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
        THROW 51606, N'Выбранный столик уже забронирован на это время.', 1;

    BEGIN TRANSACTION;

    IF @UserId IS NOT NULL
    BEGIN
        SELECT @ClientId = c.ClientId
        FROM dbo.Client c WITH (UPDLOCK, HOLDLOCK)
        WHERE c.UserId = @UserId;

        IF @ClientId IS NULL
            THROW 51607, N'Профиль авторизованного клиента не найден. Обратитесь к администратору.', 1;
    END
    ELSE
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
    WHERE StatusCode = 'ACTIVE';

    IF @ActiveReservationStatusId IS NULL
        THROW 51608, N'Не найден статус ACTIVE для бронирования.', 1;

    INSERT INTO dbo.Reservation (ClientId, ReservationStatusId, StartAt, EndAt, GuestCount)
    VALUES (@ClientId, @ActiveReservationStatusId, @StartAt, @EndAt, @GuestCount);

    SET @ReservationId = CONVERT(INT, SCOPE_IDENTITY());

    INSERT INTO dbo.ReservationTable (ReservationId, TableId)
    SELECT @ReservationId, TableId FROM @Selected;

    COMMIT TRANSACTION;

    SELECT @ReservationId AS ReservationId, N'Бронь успешно создана.' AS Message;
END
GO

/* Available/blocked table map for the reservation screen. */
CREATE OR ALTER PROCEDURE dbo.sp_GetReservationTableMap
    @StartAt DATETIME2,
    @EndAt DATETIME2,
    @GuestCount INT
AS
BEGIN
    SET NOCOUNT ON;

    IF @EndAt <= @StartAt
        THROW 51609, N'Время окончания должно быть больше времени начала.', 1;

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
                  AND rs.StatusCode = 'ACTIVE'
                  AND @StartAt < r.EndAt
                  AND @EndAt > r.StartAt
            ) THEN 0
            ELSE 1
        END AS bit) AS IsAvailable,
        CASE
            WHEN t.SeatsCount < @GuestCount THEN N'Мало мест'
            WHEN EXISTS
            (
                SELECT 1
                FROM dbo.Reservation r
                JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
                JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
                WHERE rt.TableId = t.TableId
                  AND rs.StatusCode = 'ACTIVE'
                  AND @StartAt < r.EndAt
                  AND @EndAt > r.StartAt
            ) THEN N'Забронирован'
            ELSE N'Свободен'
        END AS AvailabilityReason
    FROM dbo.RestaurantTable t
    WHERE t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.6: процедура бронирования и схема столиков созданы.';
GO
