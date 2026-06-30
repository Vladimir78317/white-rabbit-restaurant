/*
================================================================================
 WHITE RABBIT — ЕДИНЫЙ СКРИПТ УСТАНОВКИ БАЗЫ ДАННЫХ v3.0
================================================================================
 Совместим с Microsoft SQL Server 2019/2022 и SSMS.

 ВНИМАНИЕ: скрипт удаляет существующую базу WhiteRabbitRestaurant
 вместе со всеми её данными и создаёт базу заново.

 Скрипт включает:
 - базовую структуру White Rabbit;
 - функции приложения v1.2 и администрирование v1.8;
 - все обновления v2.0, v2.1, v2.3, v2.4, v2.5, v2.6, v2.7, v2.8, v2.9 и v3.0;
 - исправления бронирования, смен, визуальных схем столиков и защиты личных броней.

 Тестовые учётные записи после выполнения:
   admin    / admin123
   waiter1  / waiter123
   waiter2  / waiter123
   kitchen1 / kitchen123
   client1  / client123

 Запуск: откройте файл в SQL Server Management Studio и нажмите Execute (F5).
================================================================================
*/
GO

/* ================== 1. БАЗОВАЯ СТРУКТУРА WHITE RABBIT ================== */
/*
================================================================================
  БАЗА ДАННЫХ ДЛЯ ПРИЛОЖЕНИЯ «WHITE RABBIT»
  Совместимо с Microsoft SQL Server 2019/2022 и SQL Server Management Studio.

  ВАЖНО:
  Скрипт удаляет существующую БД WhiteRabbitRestaurant и создаёт её заново.
  Запускайте его целиком через кнопку Execute (F5) в SSMS.

  Тестовые учётные записи:
    admin    / admin123
    waiter1  / waiter123
    waiter2  / waiter123
    kitchen1 / kitchen123
    client1  / client123
================================================================================
*/

USE master;
GO

IF DB_ID(N'WhiteRabbitRestaurant') IS NOT NULL
BEGIN
    ALTER DATABASE WhiteRabbitRestaurant SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE WhiteRabbitRestaurant;
END
GO

CREATE DATABASE WhiteRabbitRestaurant;
GO

USE WhiteRabbitRestaurant;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* Профиль ресторана White Rabbit */
CREATE TABLE dbo.RestaurantProfile
(
    RestaurantId INT NOT NULL CONSTRAINT PK_RestaurantProfile PRIMARY KEY,
    RestaurantName NVARCHAR(150) NOT NULL,
    Address NVARCHAR(250) NULL,
    OpenTime TIME NOT NULL,
    CloseTime TIME NOT NULL,
    CONSTRAINT CK_RestaurantProfile_Id CHECK (RestaurantId = 1),
    CONSTRAINT CK_RestaurantProfile_WorkTime CHECK (OpenTime < CloseTime)
);
GO

INSERT INTO dbo.RestaurantProfile (RestaurantId, RestaurantName, Address, OpenTime, CloseTime)
VALUES (1, N'White Rabbit', N'Адрес указывается администратором', '09:00', '23:00');
GO


/* ============================================================================
   1. СПРАВОЧНИКИ И ПОЛЬЗОВАТЕЛИ
============================================================================ */

CREATE TABLE dbo.AppRole
(
    RoleId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppRole PRIMARY KEY,
    RoleCode    VARCHAR(30) NOT NULL CONSTRAINT UQ_AppRole_RoleCode UNIQUE,
    RoleName    NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.AppUser
(
    UserId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_AppUser PRIMARY KEY,
    RoleId          INT NOT NULL,
    Login           NVARCHAR(50) NOT NULL CONSTRAINT UQ_AppUser_Login UNIQUE,
    PasswordHash    VARBINARY(64) NOT NULL,
    PasswordSalt    VARBINARY(16) NOT NULL,
    LastName        NVARCHAR(60) NOT NULL,
    FirstName       NVARCHAR(60) NOT NULL,
    MiddleName      NVARCHAR(60) NULL,
    Phone           NVARCHAR(30) NULL,
    Email           NVARCHAR(150) NULL,
    IsActive        BIT NOT NULL CONSTRAINT DF_AppUser_IsActive DEFAULT (1),
    CreatedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_AppUser_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT FK_AppUser_AppRole
        FOREIGN KEY (RoleId) REFERENCES dbo.AppRole(RoleId)
);
GO

CREATE TABLE dbo.Waiter
(
    WaiterId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Waiter PRIMARY KEY,
    UserId      INT NOT NULL CONSTRAINT UQ_Waiter_UserId UNIQUE,
    HireDate    DATE NOT NULL CONSTRAINT DF_Waiter_HireDate DEFAULT (CONVERT(DATE, GETDATE())),
    IsActive    BIT NOT NULL CONSTRAINT DF_Waiter_IsActive DEFAULT (1),

    CONSTRAINT FK_Waiter_AppUser
        FOREIGN KEY (UserId) REFERENCES dbo.AppUser(UserId)
);
GO

CREATE TABLE dbo.Client
(
    ClientId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Client PRIMARY KEY,
    UserId      INT NULL CONSTRAINT UQ_Client_UserId UNIQUE,
    FullName    NVARCHAR(150) NOT NULL,
    Phone       NVARCHAR(30) NOT NULL,
    Email       NVARCHAR(150) NULL,
    CreatedAt   DATETIME2(0) NOT NULL CONSTRAINT DF_Client_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT FK_Client_AppUser
        FOREIGN KEY (UserId) REFERENCES dbo.AppUser(UserId)
);
GO

CREATE TABLE dbo.TableStatus
(
    TableStatusId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TableStatus PRIMARY KEY,
    StatusCode      VARCHAR(30) NOT NULL CONSTRAINT UQ_TableStatus_StatusCode UNIQUE,
    StatusName      NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.RestaurantTable
(
    TableId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_RestaurantTable PRIMARY KEY,
    TableNumber     INT NOT NULL CONSTRAINT UQ_RestaurantTable_TableNumber UNIQUE,
    SeatsCount      TINYINT NOT NULL,
    HallZone        NVARCHAR(100) NULL,
    TableStatusId   INT NOT NULL,
    IsActive        BIT NOT NULL CONSTRAINT DF_RestaurantTable_IsActive DEFAULT (1),

    CONSTRAINT CK_RestaurantTable_SeatsCount CHECK (SeatsCount BETWEEN 1 AND 4),
    CONSTRAINT FK_RestaurantTable_TableStatus
        FOREIGN KEY (TableStatusId) REFERENCES dbo.TableStatus(TableStatusId)
);
GO

CREATE TABLE dbo.ReservationStatus
(
    ReservationStatusId  INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ReservationStatus PRIMARY KEY,
    StatusCode           VARCHAR(30) NOT NULL CONSTRAINT UQ_ReservationStatus_StatusCode UNIQUE,
    StatusName           NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.Reservation
(
    ReservationId        INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Reservation PRIMARY KEY,
    ClientId             INT NOT NULL,
    ReservationStatusId  INT NOT NULL,
    StartAt              DATETIME2(0) NOT NULL,
    EndAt                DATETIME2(0) NOT NULL,
    GuestCount           TINYINT NOT NULL,
    Comment              NVARCHAR(500) NULL,
    CreatedAt            DATETIME2(0) NOT NULL CONSTRAINT DF_Reservation_CreatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT CK_Reservation_GuestCount CHECK (GuestCount BETWEEN 1 AND 50),
    CONSTRAINT CK_Reservation_Dates CHECK (EndAt > StartAt),
    CONSTRAINT FK_Reservation_Client
        FOREIGN KEY (ClientId) REFERENCES dbo.Client(ClientId),
    CONSTRAINT FK_Reservation_ReservationStatus
        FOREIGN KEY (ReservationStatusId) REFERENCES dbo.ReservationStatus(ReservationStatusId)
);
GO

CREATE TABLE dbo.ReservationTable
(
    ReservationId    INT NOT NULL,
    TableId          INT NOT NULL,

    CONSTRAINT PK_ReservationTable PRIMARY KEY (ReservationId, TableId),
    CONSTRAINT FK_ReservationTable_Reservation
        FOREIGN KEY (ReservationId) REFERENCES dbo.Reservation(ReservationId),
    CONSTRAINT FK_ReservationTable_RestaurantTable
        FOREIGN KEY (TableId) REFERENCES dbo.RestaurantTable(TableId)
);
GO

/* ============================================================================
   2. СМЕНЫ, РАСПИСАНИЕ И РАССАДКА ОФИЦИАНТОВ
============================================================================ */

CREATE TABLE dbo.ShiftStatus
(
    ShiftStatusId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_ShiftStatus PRIMARY KEY,
    StatusCode      VARCHAR(30) NOT NULL CONSTRAINT UQ_ShiftStatus_StatusCode UNIQUE,
    StatusName      NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.WaiterShift
(
    ShiftId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_WaiterShift PRIMARY KEY,
    WaiterId        INT NOT NULL,
    ShiftStatusId   INT NOT NULL,
    PlannedStartAt  DATETIME2(0) NOT NULL,
    PlannedEndAt    DATETIME2(0) NOT NULL,
    ActualOpenAt    DATETIME2(0) NULL,
    ActualCloseAt   DATETIME2(0) NULL,

    CONSTRAINT CK_WaiterShift_PlannedDates CHECK (PlannedEndAt > PlannedStartAt),
    CONSTRAINT CK_WaiterShift_ActualDates CHECK (ActualCloseAt IS NULL OR ActualCloseAt >= ActualOpenAt),
    CONSTRAINT FK_WaiterShift_Waiter
        FOREIGN KEY (WaiterId) REFERENCES dbo.Waiter(WaiterId),
    CONSTRAINT FK_WaiterShift_ShiftStatus
        FOREIGN KEY (ShiftStatusId) REFERENCES dbo.ShiftStatus(ShiftStatusId)
);
GO

CREATE TABLE dbo.WaiterTableAssignment
(
    ShiftId     INT NOT NULL,
    TableId     INT NOT NULL,

    CONSTRAINT PK_WaiterTableAssignment PRIMARY KEY (ShiftId, TableId),
    CONSTRAINT FK_WaiterTableAssignment_WaiterShift
        FOREIGN KEY (ShiftId) REFERENCES dbo.WaiterShift(ShiftId),
    CONSTRAINT FK_WaiterTableAssignment_RestaurantTable
        FOREIGN KEY (TableId) REFERENCES dbo.RestaurantTable(TableId)
);
GO

/* ============================================================================
   3. ПОСЕЩЕНИЯ, МЕНЮ, ОСТАТКИ И АКЦИИ
============================================================================ */

CREATE TABLE dbo.VisitStatus
(
    VisitStatusId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_VisitStatus PRIMARY KEY,
    StatusCode      VARCHAR(30) NOT NULL CONSTRAINT UQ_VisitStatus_StatusCode UNIQUE,
    StatusName      NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.TableVisit
(
    VisitId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_TableVisit PRIMARY KEY,
    TableId         INT NOT NULL,
    WaiterShiftId   INT NOT NULL,
    VisitStatusId   INT NOT NULL,
    GuestCount      TINYINT NOT NULL,
    StartedAt       DATETIME2(0) NOT NULL CONSTRAINT DF_TableVisit_StartedAt DEFAULT (SYSDATETIME()),
    EndedAt         DATETIME2(0) NULL,

    CONSTRAINT CK_TableVisit_GuestCount CHECK (GuestCount BETWEEN 1 AND 4),
    CONSTRAINT CK_TableVisit_Dates CHECK (EndedAt IS NULL OR EndedAt > StartedAt),
    CONSTRAINT FK_TableVisit_RestaurantTable
        FOREIGN KEY (TableId) REFERENCES dbo.RestaurantTable(TableId),
    CONSTRAINT FK_TableVisit_WaiterShift
        FOREIGN KEY (WaiterShiftId) REFERENCES dbo.WaiterShift(ShiftId),
    CONSTRAINT FK_TableVisit_VisitStatus
        FOREIGN KEY (VisitStatusId) REFERENCES dbo.VisitStatus(VisitStatusId)
);
GO

CREATE TABLE dbo.DishCategory
(
    CategoryId      INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_DishCategory PRIMARY KEY,
    CategoryName    NVARCHAR(100) NOT NULL CONSTRAINT UQ_DishCategory_CategoryName UNIQUE,
    IsActive        BIT NOT NULL CONSTRAINT DF_DishCategory_IsActive DEFAULT (1)
);
GO

CREATE TABLE dbo.Dish
(
    DishId          INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Dish PRIMARY KEY,
    CategoryId      INT NOT NULL,
    DishName        NVARCHAR(150) NOT NULL,
    Description     NVARCHAR(500) NULL,
    BasePrice       DECIMAL(10,2) NOT NULL,
    IsActive        BIT NOT NULL CONSTRAINT DF_Dish_IsActive DEFAULT (1),

    CONSTRAINT UQ_Dish_Category_Name UNIQUE (CategoryId, DishName),
    CONSTRAINT CK_Dish_BasePrice CHECK (BasePrice > 0),
    CONSTRAINT FK_Dish_DishCategory
        FOREIGN KEY (CategoryId) REFERENCES dbo.DishCategory(CategoryId)
);
GO

CREATE TABLE dbo.DishStock
(
    DishId              INT NOT NULL CONSTRAINT PK_DishStock PRIMARY KEY,
    AvailablePortions   INT NOT NULL,
    UpdatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_DishStock_UpdatedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT CK_DishStock_AvailablePortions CHECK (AvailablePortions >= 0),
    CONSTRAINT FK_DishStock_Dish
        FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId)
);
GO

CREATE TABLE dbo.Promotion
(
    PromotionId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Promotion PRIMARY KEY,
    PromotionName       NVARCHAR(150) NOT NULL,
    DiscountPercent     DECIMAL(5,2) NOT NULL,
    StartAt             DATETIME2(0) NOT NULL,
    EndAt               DATETIME2(0) NOT NULL,
    IsActive            BIT NOT NULL CONSTRAINT DF_Promotion_IsActive DEFAULT (1),

    CONSTRAINT CK_Promotion_DiscountPercent CHECK (DiscountPercent > 0 AND DiscountPercent <= 100),
    CONSTRAINT CK_Promotion_Dates CHECK (EndAt > StartAt)
);
GO

CREATE TABLE dbo.PromotionDish
(
    PromotionId     INT NOT NULL,
    DishId          INT NOT NULL,

    CONSTRAINT PK_PromotionDish PRIMARY KEY (PromotionId, DishId),
    CONSTRAINT FK_PromotionDish_Promotion
        FOREIGN KEY (PromotionId) REFERENCES dbo.Promotion(PromotionId),
    CONSTRAINT FK_PromotionDish_Dish
        FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId)
);
GO

CREATE TABLE dbo.PromotionCategory
(
    PromotionId     INT NOT NULL,
    CategoryId      INT NOT NULL,

    CONSTRAINT PK_PromotionCategory PRIMARY KEY (PromotionId, CategoryId),
    CONSTRAINT FK_PromotionCategory_Promotion
        FOREIGN KEY (PromotionId) REFERENCES dbo.Promotion(PromotionId),
    CONSTRAINT FK_PromotionCategory_DishCategory
        FOREIGN KEY (CategoryId) REFERENCES dbo.DishCategory(CategoryId)
);
GO

/* ============================================================================
   4. ЗАКАЗЫ, СЧЕТА, ОПЛАТА И ЧЕКИ
============================================================================ */

CREATE TABLE dbo.OrderStatus
(
    OrderStatusId   INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatus PRIMARY KEY,
    StatusCode      VARCHAR(30) NOT NULL CONSTRAINT UQ_OrderStatus_StatusCode UNIQUE,
    StatusName      NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.CustomerOrder
(
    OrderId             INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_CustomerOrder PRIMARY KEY,
    ReservationId       INT NULL,
    VisitId             INT NULL,
    TableId             INT NOT NULL,
    WaiterShiftId       INT NOT NULL,
    OrderStatusId       INT NOT NULL,
    CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_CustomerOrder_CreatedAt DEFAULT (SYSDATETIME()),
    FinalizedAt         DATETIME2(0) NULL,
    Comment             NVARCHAR(500) NULL,

    CONSTRAINT CK_CustomerOrder_Source CHECK (ReservationId IS NOT NULL OR VisitId IS NOT NULL),
    CONSTRAINT FK_CustomerOrder_Reservation
        FOREIGN KEY (ReservationId) REFERENCES dbo.Reservation(ReservationId),
    CONSTRAINT FK_CustomerOrder_TableVisit
        FOREIGN KEY (VisitId) REFERENCES dbo.TableVisit(VisitId),
    CONSTRAINT FK_CustomerOrder_RestaurantTable
        FOREIGN KEY (TableId) REFERENCES dbo.RestaurantTable(TableId),
    CONSTRAINT FK_CustomerOrder_WaiterShift
        FOREIGN KEY (WaiterShiftId) REFERENCES dbo.WaiterShift(ShiftId),
    CONSTRAINT FK_CustomerOrder_OrderStatus
        FOREIGN KEY (OrderStatusId) REFERENCES dbo.OrderStatus(OrderStatusId)
);
GO

CREATE TABLE dbo.OrderItem
(
    OrderItemId         INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderItem PRIMARY KEY,
    OrderId             INT NOT NULL,
    DishId              INT NOT NULL,
    Quantity            INT NOT NULL,
    UnitPrice           DECIMAL(10,2) NOT NULL,
    DiscountPercent     DECIMAL(5,2) NOT NULL CONSTRAINT DF_OrderItem_DiscountPercent DEFAULT (0),

    CONSTRAINT UQ_OrderItem_Order_Dish UNIQUE (OrderId, DishId),
    CONSTRAINT CK_OrderItem_Quantity CHECK (Quantity > 0),
    CONSTRAINT CK_OrderItem_UnitPrice CHECK (UnitPrice >= 0),
    CONSTRAINT CK_OrderItem_DiscountPercent CHECK (DiscountPercent BETWEEN 0 AND 100),
    CONSTRAINT FK_OrderItem_CustomerOrder
        FOREIGN KEY (OrderId) REFERENCES dbo.CustomerOrder(OrderId),
    CONSTRAINT FK_OrderItem_Dish
        FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId)
);
GO

CREATE TABLE dbo.OrderStatusHistory
(
    OrderStatusHistoryId    INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_OrderStatusHistory PRIMARY KEY,
    OrderId                 INT NOT NULL,
    OrderStatusId           INT NOT NULL,
    ChangedAt               DATETIME2(0) NOT NULL CONSTRAINT DF_OrderStatusHistory_ChangedAt DEFAULT (SYSDATETIME()),
    Comment                 NVARCHAR(500) NULL,

    CONSTRAINT FK_OrderStatusHistory_CustomerOrder
        FOREIGN KEY (OrderId) REFERENCES dbo.CustomerOrder(OrderId),
    CONSTRAINT FK_OrderStatusHistory_OrderStatus
        FOREIGN KEY (OrderStatusId) REFERENCES dbo.OrderStatus(OrderStatusId)
);
GO

CREATE TABLE dbo.Bill
(
    BillId              INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Bill PRIMARY KEY,
    OrderId             INT NOT NULL CONSTRAINT UQ_Bill_OrderId UNIQUE,
    Amount              DECIMAL(12,2) NOT NULL,
    CreatedAt           DATETIME2(0) NOT NULL CONSTRAINT DF_Bill_CreatedAt DEFAULT (SYSDATETIME()),
    IsPaid              BIT NOT NULL CONSTRAINT DF_Bill_IsPaid DEFAULT (0),
    PaidAt              DATETIME2(0) NULL,

    CONSTRAINT CK_Bill_Amount CHECK (Amount >= 0),
    CONSTRAINT FK_Bill_CustomerOrder
        FOREIGN KEY (OrderId) REFERENCES dbo.CustomerOrder(OrderId)
);
GO

CREATE TABLE dbo.PaymentMethod
(
    PaymentMethodId     INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_PaymentMethod PRIMARY KEY,
    MethodCode          VARCHAR(30) NOT NULL CONSTRAINT UQ_PaymentMethod_MethodCode UNIQUE,
    MethodName          NVARCHAR(100) NOT NULL
);
GO

CREATE TABLE dbo.Payment
(
    PaymentId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Payment PRIMARY KEY,
    BillId              INT NOT NULL CONSTRAINT UQ_Payment_BillId UNIQUE,
    PaymentMethodId     INT NOT NULL,
    PaidAmount          DECIMAL(12,2) NOT NULL,
    PaidAt              DATETIME2(0) NOT NULL CONSTRAINT DF_Payment_PaidAt DEFAULT (SYSDATETIME()),

    CONSTRAINT CK_Payment_PaidAmount CHECK (PaidAmount >= 0),
    CONSTRAINT FK_Payment_Bill
        FOREIGN KEY (BillId) REFERENCES dbo.Bill(BillId),
    CONSTRAINT FK_Payment_PaymentMethod
        FOREIGN KEY (PaymentMethodId) REFERENCES dbo.PaymentMethod(PaymentMethodId)
);
GO

CREATE TABLE dbo.Receipt
(
    ReceiptId           INT IDENTITY(1,1) NOT NULL CONSTRAINT PK_Receipt PRIMARY KEY,
    PaymentId           INT NOT NULL CONSTRAINT UQ_Receipt_PaymentId UNIQUE,
    ReceiptNumber       NVARCHAR(50) NOT NULL CONSTRAINT UQ_Receipt_ReceiptNumber UNIQUE,
    IssuedAt            DATETIME2(0) NOT NULL CONSTRAINT DF_Receipt_IssuedAt DEFAULT (SYSDATETIME()),

    CONSTRAINT FK_Receipt_Payment
        FOREIGN KEY (PaymentId) REFERENCES dbo.Payment(PaymentId)
);
GO

/* ============================================================================
   5. ИНДЕКСЫ
============================================================================ */

CREATE INDEX IX_Reservation_StartEnd_Status
    ON dbo.Reservation (StartAt, EndAt, ReservationStatusId);
GO

CREATE INDEX IX_ReservationTable_Table
    ON dbo.ReservationTable (TableId, ReservationId);
GO

CREATE INDEX IX_WaiterShift_Waiter_Dates
    ON dbo.WaiterShift (WaiterId, PlannedStartAt, PlannedEndAt);
GO

CREATE INDEX IX_TableVisit_Table_Dates
    ON dbo.TableVisit (TableId, StartedAt, EndedAt);
GO

CREATE INDEX IX_CustomerOrder_Table_CreatedAt
    ON dbo.CustomerOrder (TableId, CreatedAt);
GO

CREATE INDEX IX_CustomerOrder_WaiterShift_FinalizedAt
    ON dbo.CustomerOrder (WaiterShiftId, FinalizedAt);
GO

CREATE INDEX IX_OrderItem_Dish
    ON dbo.OrderItem (DishId, OrderId);
GO

/* ============================================================================
   6. НАЧАЛЬНЫЕ ДАННЫЕ СПРАВОЧНИКОВ
============================================================================ */

INSERT INTO dbo.AppRole (RoleCode, RoleName)
VALUES
('ADMIN',   N'Администратор'),
('CLIENT',  N'Клиент'),
('WAITER',  N'Официант'),
('KITCHEN', N'Кухня');
GO

INSERT INTO dbo.TableStatus (StatusCode, StatusName)
VALUES
('FREE',           N'Свободен'),
('RESERVED',       N'Забронирован'),
('OCCUPIED',       N'Занят'),
('OUT_OF_SERVICE', N'Не обслуживается');
GO

INSERT INTO dbo.ReservationStatus (StatusCode, StatusName)
VALUES
('ACTIVE',    N'Активна'),
('CANCELLED', N'Отменена'),
('COMPLETED', N'Завершена');
GO

INSERT INTO dbo.ShiftStatus (StatusCode, StatusName)
VALUES
('PLANNED', N'Запланирована'),
('OPEN',    N'Открыта'),
('CLOSED',  N'Закрыта');
GO

INSERT INTO dbo.VisitStatus (StatusCode, StatusName)
VALUES
('OPEN',   N'Открыто'),
('CLOSED', N'Закрыто');
GO

INSERT INTO dbo.OrderStatus (StatusCode, StatusName)
VALUES
('DRAFT',       N'Составление'),
('PLACED',      N'Оформлен'),
('CANCELLED',   N'Отменен'),
('PREPARING',   N'Готовится'),
('READY',       N'Готов к выдаче'),
('ACCEPTED',    N'Принят на выдачу'),
('ISSUED',      N'Выдан клиенту');
GO

INSERT INTO dbo.PaymentMethod (MethodCode, MethodName)
VALUES
('CASH', N'Наличные'),
('CARD', N'Банковская карта');
GO

INSERT INTO dbo.RestaurantTable (TableNumber, SeatsCount, HallZone, TableStatusId)
SELECT v.TableNumber, v.SeatsCount, v.HallZone, ts.TableStatusId
FROM
(
    VALUES
    (1, 2, N'Основной зал'),
    (2, 2, N'Основной зал'),
    (3, 4, N'Основной зал'),
    (4, 4, N'Основной зал'),
    (5, 4, N'У окна'),
    (6, 2, N'У окна'),
    (7, 4, N'Терраса'),
    (8, 4, N'Терраса')
) AS v(TableNumber, SeatsCount, HallZone)
CROSS JOIN dbo.TableStatus ts
WHERE ts.StatusCode = 'FREE';
GO

INSERT INTO dbo.DishCategory (CategoryName)
VALUES
(N'Салаты'),
(N'Супы'),
(N'Горячие блюда'),
(N'Пицца'),
(N'Напитки'),
(N'Десерты');
GO

INSERT INTO dbo.Dish (CategoryId, DishName, Description, BasePrice)
SELECT c.CategoryId, v.DishName, v.Description, v.BasePrice
FROM
(
    VALUES
    (N'Салаты',        N'Цезарь с курицей', N'Салат с курицей, сыром и соусом', 520.00),
    (N'Салаты',        N'Греческий салат',  N'Овощной салат с сыром фета',     420.00),
    (N'Супы',          N'Борщ',             N'Классический борщ со сметаной', 350.00),
    (N'Супы',          N'Том ям',           N'Острый суп с креветками',       690.00),
    (N'Горячие блюда', N'Стейк из говядины',N'Стейк средней прожарки',        1190.00),
    (N'Горячие блюда', N'Паста Карбонара',  N'Паста с беконом и соусом',      590.00),
    (N'Пицца',         N'Пицца Маргарита',  N'Томатный соус, моцарелла',      650.00),
    (N'Пицца',         N'Пицца Пепперони',  N'Пепперони, сыр, томаты',        740.00),
    (N'Напитки',       N'Морс ягодный',     N'Домашний ягодный морс',         220.00),
    (N'Напитки',       N'Капучино',         N'Кофе с молоком',               250.00),
    (N'Десерты',       N'Чизкейк',          N'Классический чизкейк',         330.00),
    (N'Десерты',       N'Тирамису',         N'Итальянский десерт',           390.00)
) AS v(CategoryName, DishName, Description, BasePrice)
JOIN dbo.DishCategory c ON c.CategoryName = v.CategoryName;
GO

INSERT INTO dbo.DishStock (DishId, AvailablePortions)
SELECT DishId, 20
FROM dbo.Dish;
GO

/* ============================================================================
   7. ТИПЫ ДАННЫХ И ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
============================================================================ */

CREATE TYPE dbo.TableIdList AS TABLE
(
    TableId INT NOT NULL PRIMARY KEY
);
GO

CREATE OR ALTER FUNCTION dbo.fn_GetCurrentDishPrice
(
    @DishId INT,
    @AtTime DATETIME2(0)
)
RETURNS TABLE
AS
RETURN
(
    SELECT
        d.DishId,
        d.BasePrice,
        CAST(ISNULL
        (
            (
                SELECT MAX(p.DiscountPercent)
                FROM dbo.Promotion p
                LEFT JOIN dbo.PromotionDish pd
                    ON pd.PromotionId = p.PromotionId
                LEFT JOIN dbo.PromotionCategory pc
                    ON pc.PromotionId = p.PromotionId
                WHERE p.IsActive = 1
                  AND p.StartAt <= @AtTime
                  AND p.EndAt > @AtTime
                  AND (pd.DishId = d.DishId OR pc.CategoryId = d.CategoryId)
            ),
            0
        ) AS DECIMAL(5,2)) AS DiscountPercent,
        CAST
        (
            ROUND
            (
                d.BasePrice *
                (
                    1 -
                    ISNULL
                    (
                        (
                            SELECT MAX(p.DiscountPercent)
                            FROM dbo.Promotion p
                            LEFT JOIN dbo.PromotionDish pd
                                ON pd.PromotionId = p.PromotionId
                            LEFT JOIN dbo.PromotionCategory pc
                                ON pc.PromotionId = p.PromotionId
                            WHERE p.IsActive = 1
                              AND p.StartAt <= @AtTime
                              AND p.EndAt > @AtTime
                              AND (pd.DishId = d.DishId OR pc.CategoryId = d.CategoryId)
                        ),
                        0
                    ) / 100.0
                ),
                2
            )
            AS DECIMAL(10,2)
        ) AS ActualUnitPrice
    FROM dbo.Dish d
    WHERE d.DishId = @DishId
);
GO

/* ============================================================================
   8. ТРИГГЕР ДЛЯ ИСТОРИИ СТАТУСОВ ЗАКАЗА
============================================================================ */

CREATE OR ALTER TRIGGER dbo.trg_CustomerOrder_StatusHistory
ON dbo.CustomerOrder
AFTER INSERT, UPDATE
AS
BEGIN
    SET NOCOUNT ON;

    INSERT INTO dbo.OrderStatusHistory (OrderId, OrderStatusId, ChangedAt, Comment)
    SELECT
        i.OrderId,
        i.OrderStatusId,
        SYSDATETIME(),
        N'Статус установлен автоматически при создании или изменении заказа.'
    FROM inserted i
    LEFT JOIN deleted d
        ON d.OrderId = i.OrderId
    WHERE d.OrderId IS NULL
       OR d.OrderStatusId <> i.OrderStatusId;
END;
GO

/* ============================================================================
   9. ПРОЦЕДУРЫ: РЕГИСТРАЦИЯ И СМЕНЫ
============================================================================ */


CREATE OR ALTER PROCEDURE dbo.sp_AuthenticateUser
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
        THROW 50055, N'Неверный логин или пароль.', 1;

    IF HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), @Password) + @Salt) <> @SavedHash
        THROW 50056, N'Неверный логин или пароль.', 1;

    SELECT
        u.UserId,
        u.Login,
        CONCAT(u.LastName, N' ', u.FirstName, N' ', ISNULL(u.MiddleName, N'')) AS FullName,
        r.RoleCode,
        r.RoleName,
        N'Авторизация выполнена успешно.' AS Message
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE u.UserId = @UserId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_SetRestaurantTableStatus
    @TableId INT,
    @StatusCode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @TableStatusId INT =
    (
        SELECT TableStatusId
        FROM dbo.TableStatus
        WHERE StatusCode = @StatusCode
    );

    IF @TableStatusId IS NULL
        THROW 50057, N'Указанный статус столика не существует.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.RestaurantTable WHERE TableId = @TableId)
        THROW 50058, N'Столик не найден.', 1;

    IF @StatusCode = 'OUT_OF_SERVICE'
       AND EXISTS
       (
           SELECT 1
           FROM dbo.TableVisit tv
           JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
           WHERE tv.TableId = @TableId
             AND vs.StatusCode = 'OPEN'
       )
        THROW 50059, N'Нельзя вывести из обслуживания занятый столик.', 1;

    UPDATE dbo.RestaurantTable
    SET TableStatusId = @TableStatusId
    WHERE TableId = @TableId;

    SELECT N'Статус столика успешно изменен.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RegisterUser
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
        THROW 50001, N'Пользователь с таким логином уже существует.', 1;

    DECLARE @RoleId INT =
    (
        SELECT RoleId
        FROM dbo.AppRole
        WHERE RoleCode = @RoleCode
    );

    IF @RoleId IS NULL
        THROW 50002, N'Указанная роль не существует.', 1;

    DECLARE @Salt VARBINARY(16) = CRYPT_GEN_RANDOM(16);
    DECLARE @PasswordHash VARBINARY(64) =
        HASHBYTES('SHA2_512', CONVERT(VARBINARY(MAX), @Password) + @Salt);

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
        N'Пользователь успешно зарегистрирован.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_PlanWaiterShift
    @WaiterId INT,
    @PlannedStartAt DATETIME2(0),
    @PlannedEndAt DATETIME2(0)
AS
BEGIN
    SET NOCOUNT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 50003, N'Время окончания смены должно быть позже времени начала.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        WHERE ws.WaiterId = @WaiterId
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
          AND ws.ShiftStatusId <> (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED')
    )
        THROW 50004, N'У официанта уже есть пересекающаяся смена.', 1;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId, ShiftStatusId, PlannedStartAt, PlannedEndAt
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt,
        @PlannedEndAt
    );

    SELECT
        SCOPE_IDENTITY() AS ShiftId,
        N'Смена официанта успешно добавлена в график.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AssignWaiterToTable
    @ShiftId INT,
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.WaiterShift WHERE ShiftId = @ShiftId)
        THROW 50005, N'Смена не найдена.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.RestaurantTable WHERE TableId = @TableId AND IsActive = 1)
        THROW 50006, N'Столик не найден или отключен.', 1;

    IF EXISTS (SELECT 1 FROM dbo.WaiterTableAssignment WHERE ShiftId = @ShiftId AND TableId = @TableId)
        THROW 50007, N'Этот столик уже закреплен за официантом в указанной смене.', 1;

    INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
    VALUES (@ShiftId, @TableId);

    SELECT N'Официант успешно прикреплен к столику в рамках смены.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_OpenWaiterShift
    @ShiftId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.ShiftId = @ShiftId
          AND ss.StatusCode = 'PLANNED'
    )
        THROW 50008, N'Открыть можно только запланированную смену.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = SYSDATETIME()
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена успешно открыта.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CloseWaiterShift
    @ShiftId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.ShiftId = @ShiftId
          AND ss.StatusCode = 'OPEN'
    )
        THROW 50009, N'Закрыть можно только открытую смену.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = SYSDATETIME()
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена успешно закрыта.' AS Message;
END;
GO

/* ============================================================================
   10. ПРОЦЕДУРЫ: БРОНИРОВАНИЕ И СВОБОДНЫЕ СТОЛИКИ
============================================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableTables
    @AtTime DATETIME2(0) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    SET @AtTime = ISNULL(@AtTime, SYSDATETIME());

    SELECT
        t.TableId,
        t.TableNumber,
        t.SeatsCount,
        t.HallZone,
        N'Свободен' AS Availability
    FROM dbo.RestaurantTable t
    JOIN dbo.TableStatus ts ON ts.TableStatusId = t.TableStatusId
    WHERE t.IsActive = 1
      AND ts.StatusCode <> 'OUT_OF_SERVICE'
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.Reservation r
          JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
          JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
          WHERE rt.TableId = t.TableId
            AND rs.StatusCode = 'ACTIVE'
            AND @AtTime >= r.StartAt
            AND @AtTime < r.EndAt
      )
      AND NOT EXISTS
      (
          SELECT 1
          FROM dbo.TableVisit tv
          JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
          WHERE tv.TableId = t.TableId
            AND vs.StatusCode = 'OPEN'
            AND @AtTime >= tv.StartedAt
            AND (tv.EndedAt IS NULL OR @AtTime < tv.EndedAt)
      )
    ORDER BY t.TableNumber;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CreateReservation
    @ClientId INT,
    @StartAt DATETIME2(0),
    @EndAt DATETIME2(0),
    @GuestCount TINYINT,
    @Comment NVARCHAR(500) = NULL,
    @TableIds dbo.TableIdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.Client WHERE ClientId = @ClientId)
        THROW 50010, N'Клиент не найден.', 1;

    IF @GuestCount < 1
        THROW 50011, N'Количество гостей должно быть больше нуля.', 1;

    IF @EndAt <= @StartAt
        THROW 50012, N'Дата и время окончания должны быть позже даты и времени начала.', 1;

    IF CONVERT(DATE, @StartAt) <> CONVERT(DATE, @EndAt)
       OR CONVERT(TIME, @StartAt) < '09:00'
       OR CONVERT(TIME, @EndAt) > '23:00'
        THROW 50013, N'Бронь должна быть в пределах одного дня и рабочего времени ресторана: с 09:00 до 23:00.', 1;

    IF NOT EXISTS (SELECT 1 FROM @TableIds)
        THROW 50014, N'Для брони необходимо выбрать хотя бы один столик.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM @TableIds x
        LEFT JOIN dbo.RestaurantTable t ON t.TableId = x.TableId
        WHERE t.TableId IS NULL OR t.IsActive = 0
    )
        THROW 50015, N'Один или несколько выбранных столиков не существуют или неактивны.', 1;

    DECLARE @TotalSeats INT =
    (
        SELECT SUM(t.SeatsCount)
        FROM dbo.RestaurantTable t
        JOIN @TableIds x ON x.TableId = t.TableId
    );

    IF @GuestCount > @TotalSeats
        THROW 50016, N'Количество гостей превышает суммарное число мест у выбранных столиков.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        JOIN @TableIds x ON x.TableId = rt.TableId
        WHERE rs.StatusCode = 'ACTIVE'
          AND @StartAt < r.EndAt
          AND @EndAt > r.StartAt
    )
        THROW 50017, N'Один или несколько столиков уже заняты другой бронью в указанное время.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.TableVisit tv
        JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
        JOIN @TableIds x ON x.TableId = tv.TableId
        WHERE vs.StatusCode = 'OPEN'
          AND @StartAt < ISNULL(tv.EndedAt, DATEADD(HOUR, 24, @StartAt))
          AND @EndAt > tv.StartedAt
    )
        THROW 50018, N'Один или несколько столиков заняты текущими посетителями.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.Reservation
    (
        ClientId, ReservationStatusId, StartAt, EndAt, GuestCount, Comment
    )
    VALUES
    (
        @ClientId,
        (SELECT ReservationStatusId FROM dbo.ReservationStatus WHERE StatusCode = 'ACTIVE'),
        @StartAt, @EndAt, @GuestCount, @Comment
    );

    DECLARE @ReservationId INT = SCOPE_IDENTITY();

    INSERT INTO dbo.ReservationTable (ReservationId, TableId)
    SELECT @ReservationId, TableId
    FROM @TableIds;

    COMMIT TRANSACTION;

    SELECT
        @ReservationId AS ReservationId,
        N'Бронь успешно создана.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CancelReservation
    @ReservationId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE r.ReservationId = @ReservationId
          AND rs.StatusCode = 'ACTIVE'
    )
        THROW 50019, N'Активная бронь с указанным номером не найдена.', 1;

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

CREATE OR ALTER PROCEDURE dbo.sp_UpdateReservation
    @ReservationId INT,
    @StartAt DATETIME2(0),
    @EndAt DATETIME2(0),
    @GuestCount TINYINT,
    @Comment NVARCHAR(500) = NULL,
    @TableIds dbo.TableIdList READONLY
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE r.ReservationId = @ReservationId
          AND rs.StatusCode = 'ACTIVE'
    )
        THROW 50020, N'Редактировать можно только активную бронь.', 1;

    IF @EndAt <= @StartAt
        THROW 50021, N'Дата и время окончания должны быть позже даты и времени начала.', 1;

    IF CONVERT(DATE, @StartAt) <> CONVERT(DATE, @EndAt)
       OR CONVERT(TIME, @StartAt) < '09:00'
       OR CONVERT(TIME, @EndAt) > '23:00'
        THROW 50022, N'Бронь должна быть в пределах одного дня и рабочего времени ресторана.', 1;

    IF NOT EXISTS (SELECT 1 FROM @TableIds)
        THROW 50023, N'Для брони необходимо выбрать хотя бы один столик.', 1;

    DECLARE @TotalSeats INT =
    (
        SELECT SUM(t.SeatsCount)
        FROM dbo.RestaurantTable t
        JOIN @TableIds x ON x.TableId = t.TableId
        WHERE t.IsActive = 1
    );

    IF @TotalSeats IS NULL OR @GuestCount > @TotalSeats
        THROW 50024, N'Недостаточно свободных мест у выбранных столиков.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        JOIN @TableIds x ON x.TableId = rt.TableId
        WHERE r.ReservationId <> @ReservationId
          AND rs.StatusCode = 'ACTIVE'
          AND @StartAt < r.EndAt
          AND @EndAt > r.StartAt
    )
        THROW 50025, N'Нельзя изменить бронь: выбранный столик занят другой бронью.', 1;

    BEGIN TRANSACTION;

    UPDATE dbo.Reservation
    SET
        StartAt = @StartAt,
        EndAt = @EndAt,
        GuestCount = @GuestCount,
        Comment = @Comment
    WHERE ReservationId = @ReservationId;

    DELETE FROM dbo.ReservationTable
    WHERE ReservationId = @ReservationId;

    INSERT INTO dbo.ReservationTable (ReservationId, TableId)
    SELECT @ReservationId, TableId
    FROM @TableIds;

    COMMIT TRANSACTION;

    SELECT N'Данные брони успешно изменены.' AS Message;
END;
GO

/* ============================================================================
   11. ПРОЦЕДУРЫ: ПОСЕЩЕНИЯ БЕЗ БРОНИ
============================================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_OpenTableVisit
    @TableId INT,
    @WaiterShiftId INT,
    @GuestCount TINYINT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @SeatsCount TINYINT;

    SELECT @SeatsCount = SeatsCount
    FROM dbo.RestaurantTable
    WHERE TableId = @TableId
      AND IsActive = 1;

    IF @SeatsCount IS NULL
        THROW 50026, N'Столик не найден или отключен.', 1;

    IF @GuestCount > @SeatsCount OR @GuestCount < 1
        THROW 50027, N'Количество гостей не соответствует вместимости столика.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment wta ON wta.ShiftId = ws.ShiftId
        WHERE ws.ShiftId = @WaiterShiftId
          AND wta.TableId = @TableId
          AND ss.StatusCode = 'OPEN'
    )
        THROW 50028, N'Указанный столик не закреплен за официантом в открытой смене.', 1;

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
        THROW 50029, N'Столик занят активной бронью.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.TableVisit tv
        JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
        WHERE tv.TableId = @TableId
          AND vs.StatusCode = 'OPEN'
    )
        THROW 50030, N'За этим столиком уже есть открытое посещение.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.TableVisit
    (
        TableId, WaiterShiftId, VisitStatusId, GuestCount
    )
    VALUES
    (
        @TableId,
        @WaiterShiftId,
        (SELECT VisitStatusId FROM dbo.VisitStatus WHERE StatusCode = 'OPEN'),
        @GuestCount
    );

    DECLARE @VisitId INT = SCOPE_IDENTITY();

    UPDATE dbo.RestaurantTable
    SET TableStatusId = (SELECT TableStatusId FROM dbo.TableStatus WHERE StatusCode = 'OCCUPIED')
    WHERE TableId = @TableId;

    COMMIT TRANSACTION;

    SELECT
        @VisitId AS VisitId,
        N'Посещение открыто. Столик отмечен как занятый.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CloseTableVisit
    @VisitId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @TableId INT;

    SELECT @TableId = tv.TableId
    FROM dbo.TableVisit tv
    JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
    WHERE tv.VisitId = @VisitId
      AND vs.StatusCode = 'OPEN';

    IF @TableId IS NULL
        THROW 50031, N'Открытое посещение не найдено.', 1;

    BEGIN TRANSACTION;

    UPDATE dbo.TableVisit
    SET
        VisitStatusId = (SELECT VisitStatusId FROM dbo.VisitStatus WHERE StatusCode = 'CLOSED'),
        EndedAt = SYSDATETIME()
    WHERE VisitId = @VisitId;

    UPDATE dbo.RestaurantTable
    SET TableStatusId = (SELECT TableStatusId FROM dbo.TableStatus WHERE StatusCode = 'FREE')
    WHERE TableId = @TableId;

    COMMIT TRANSACTION;

    SELECT N'Посещение закрыто. Столик освобожден.' AS Message;
END;
GO

/* ============================================================================
   12. ПРОЦЕДУРЫ: ЗАКАЗЫ И СКЛАД
============================================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_CreateOrder
    @TableId INT,
    @WaiterShiftId INT,
    @ReservationId INT = NULL,
    @VisitId INT = NULL,
    @Comment NVARCHAR(500) = NULL
AS
BEGIN
    SET NOCOUNT ON;

    IF @ReservationId IS NULL AND @VisitId IS NULL
        THROW 50032, N'Заказ должен быть связан с бронью или посещением.', 1;

    IF @ReservationId IS NOT NULL AND @VisitId IS NOT NULL
        THROW 50033, N'Заказ может быть связан только с одной бронью или одним посещением.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment wta ON wta.ShiftId = ws.ShiftId
        WHERE ws.ShiftId = @WaiterShiftId
          AND wta.TableId = @TableId
          AND ss.StatusCode = 'OPEN'
    )
        THROW 50034, N'Официант не назначен на этот столик или смена не открыта.', 1;

    IF @ReservationId IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.ReservationTable
           WHERE ReservationId = @ReservationId
             AND TableId = @TableId
       )
        THROW 50035, N'Указанный столик не относится к выбранной брони.', 1;

    IF @VisitId IS NOT NULL
       AND NOT EXISTS
       (
           SELECT 1
           FROM dbo.TableVisit
           WHERE VisitId = @VisitId
             AND TableId = @TableId
       )
        THROW 50036, N'Указанный столик не относится к выбранному посещению.', 1;

    INSERT INTO dbo.CustomerOrder
    (
        ReservationId, VisitId, TableId, WaiterShiftId, OrderStatusId, Comment
    )
    VALUES
    (
        @ReservationId,
        @VisitId,
        @TableId,
        @WaiterShiftId,
        (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'DRAFT'),
        @Comment
    );

    SELECT
        SCOPE_IDENTITY() AS OrderId,
        N'Создан новый заказ в статусе «Составление».' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_AddDishToOrder
    @OrderId INT,
    @DishId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 50037, N'Количество порций должно быть больше нуля.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = 'DRAFT'
    )
        THROW 50038, N'Редактировать можно только заказ в статусе «Составление».', 1;

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
        THROW 50039, N'Блюдо не найдено или недоступно для заказа.', 1;
    END

    IF @AvailablePortions < @Quantity
    BEGIN
        ROLLBACK TRANSACTION;

        DECLARE @StockMessage NVARCHAR(400) =
            CONCAT
            (
                N'Невозможно добавить блюдо в запрашиваемом количестве. Сейчас доступно ',
                @AvailablePortions,
                N' порций.'
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
            N'Блюдо «', @DishName, N'» в количестве ', @Quantity,
            N' порций было успешно добавлено в Заказ №', @OrderId
        ) AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_RemoveDishFromOrder
    @OrderId INT,
    @DishId INT,
    @Quantity INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 50041, N'Количество порций должно быть больше нуля.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = 'DRAFT'
    )
        THROW 50042, N'Удалять блюда можно только из заказа в статусе «Составление».', 1;

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
        THROW 50043, N'Указанное блюдо отсутствует в заказе.', 1;
    END

    IF @Quantity > @CurrentQuantity
    BEGIN
        ROLLBACK TRANSACTION;
        THROW 50044, N'Нельзя удалить больше порций, чем содержится в заказе.', 1;
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
            N'Блюдо «', @DishName, N'» в количестве ', @Quantity,
            N' порций было успешно удалено из Заказа №', @OrderId
        ) AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_FinalizeOrder
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = 'DRAFT'
    )
        THROW 50045, N'Оформить можно только заказ в статусе «Составление».', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.OrderItem WHERE OrderId = @OrderId)
        THROW 50046, N'Нельзя оформить пустой заказ.', 1;

    DECLARE @TotalAmount DECIMAL(12,2) =
    (
        SELECT SUM(Quantity * UnitPrice)
        FROM dbo.OrderItem
        WHERE OrderId = @OrderId
    );

    BEGIN TRANSACTION;

    UPDATE dbo.CustomerOrder
    SET
        OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'PLACED'),
        FinalizedAt = SYSDATETIME()
    WHERE OrderId = @OrderId;

    INSERT INTO dbo.Bill (OrderId, Amount)
    VALUES (@OrderId, @TotalAmount);

    COMMIT TRANSACTION;

    SELECT
        CONCAT
        (
            N'Заказ №', o.OrderId,
            N' успешно оформлен для стола №', t.TableNumber,
            N'. Дата и время заказа: ',
            CONVERT(NVARCHAR(19), o.FinalizedAt, 120),
            N'. Принял: ', u.LastName, N' ', LEFT(u.FirstName, 1), N'. ',
            LEFT(ISNULL(u.MiddleName, N''), 1), N'.',
            N'. Количество блюд: ', x.TotalPortions,
            N'. Сумма заказа: ', b.Amount, N' руб.'
        ) AS Message,
        o.OrderId,
        o.ReservationId,
        t.TableNumber,
        o.FinalizedAt,
        CONCAT(u.LastName, N' ', u.FirstName, N' ', ISNULL(u.MiddleName, N'')) AS WaiterFullName,
        x.TotalPortions,
        b.Amount AS OrderAmount,
        ISNULL
        (
            (
                SELECT SUM(b2.Amount)
                FROM dbo.Bill b2
                JOIN dbo.CustomerOrder o2 ON o2.OrderId = b2.OrderId
                WHERE o2.ReservationId = o.ReservationId
                  AND b2.IsPaid IN (0, 1)
            ),
            b.Amount
        ) AS ReservationOrdersTotal
    FROM dbo.CustomerOrder o
    JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
    JOIN dbo.WaiterShift ws ON ws.ShiftId = o.WaiterShiftId
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.Bill b ON b.OrderId = o.OrderId
    CROSS APPLY
    (
        SELECT SUM(Quantity) AS TotalPortions
        FROM dbo.OrderItem
        WHERE OrderId = o.OrderId
    ) x
    WHERE o.OrderId = @OrderId;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_CancelOrder
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @CurrentStatusCode VARCHAR(30) =
    (
        SELECT os.StatusCode
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
    );

    IF @CurrentStatusCode IS NULL
        THROW 50047, N'Заказ не найден.', 1;

    IF @CurrentStatusCode IN ('PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
        THROW 50048, N'Заказ уже принят кухней или выдан. Его отменить нельзя.', 1;

    IF @CurrentStatusCode NOT IN ('DRAFT', 'PLACED')
        THROW 50049, N'Этот заказ нельзя отменить в текущем статусе.', 1;

    BEGIN TRANSACTION;

    UPDATE ds
    SET
        ds.AvailablePortions = ds.AvailablePortions + oi.Quantity,
        ds.UpdatedAt = SYSDATETIME()
    FROM dbo.DishStock ds
    JOIN dbo.OrderItem oi ON oi.DishId = ds.DishId
    WHERE oi.OrderId = @OrderId;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'CANCELLED')
    WHERE OrderId = @OrderId;

    DELETE FROM dbo.Bill
    WHERE OrderId = @OrderId
      AND IsPaid = 0;

    COMMIT TRANSACTION;

    SELECT N'Заказ отменен. Зарезервированные на складе порции возвращены.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_SetKitchenOrderStatus
    @OrderId INT,
    @NewStatusCode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF @NewStatusCode NOT IN ('PREPARING', 'READY', 'ACCEPTED')
        THROW 50049, N'Кухня может установить только статусы: Готовится, Готов к выдаче, Принят на выдачу.', 1;

    DECLARE @CurrentStatusCode VARCHAR(30) =
    (
        SELECT os.StatusCode
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
    );

    IF @CurrentStatusCode IS NULL
        THROW 50050, N'Заказ не найден.', 1;

    IF (@NewStatusCode = 'PREPARING' AND @CurrentStatusCode <> 'PLACED')
       OR (@NewStatusCode = 'READY' AND @CurrentStatusCode <> 'PREPARING')
       OR (@NewStatusCode = 'ACCEPTED' AND @CurrentStatusCode <> 'READY')
        THROW 50051, N'Неверная последовательность изменения статуса заказа.', 1;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId =
    (
        SELECT OrderStatusId
        FROM dbo.OrderStatus
        WHERE StatusCode = @NewStatusCode
    )
    WHERE OrderId = @OrderId;

    SELECT N'Статус заказа успешно изменен кухней.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_IssueOrderToClient
    @OrderId INT
AS
BEGIN
    SET NOCOUNT ON;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE o.OrderId = @OrderId
          AND os.StatusCode = 'ACCEPTED'
    )
        THROW 50052, N'Выдать клиенту можно только заказ в статусе «Принят на выдачу».', 1;

    UPDATE dbo.CustomerOrder
    SET OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'ISSUED')
    WHERE OrderId = @OrderId;

    SELECT N'Заказ выдан клиенту.' AS Message;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_PayOrder
    @OrderId INT,
    @PaymentMethodCode VARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    DECLARE @BillId INT;
    DECLARE @Amount DECIMAL(12,2);
    DECLARE @PaymentMethodId INT;

    SELECT
        @BillId = b.BillId,
        @Amount = b.Amount
    FROM dbo.Bill b
    WHERE b.OrderId = @OrderId
      AND b.IsPaid = 0;

    IF @BillId IS NULL
        THROW 50053, N'Неоплаченный счет для указанного заказа не найден.', 1;

    SELECT @PaymentMethodId = PaymentMethodId
    FROM dbo.PaymentMethod
    WHERE MethodCode = @PaymentMethodCode;

    IF @PaymentMethodId IS NULL
        THROW 50054, N'Указанный способ оплаты не найден.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.Payment (BillId, PaymentMethodId, PaidAmount)
    VALUES (@BillId, @PaymentMethodId, @Amount);

    DECLARE @PaymentId INT = SCOPE_IDENTITY();
    DECLARE @ReceiptNumber NVARCHAR(50) =
        CONCAT(N'R-', FORMAT(SYSDATETIME(), 'yyyyMMddHHmmss'), N'-', @PaymentId);

    INSERT INTO dbo.Receipt (PaymentId, ReceiptNumber)
    VALUES (@PaymentId, @ReceiptNumber);

    UPDATE dbo.Bill
    SET
        IsPaid = 1,
        PaidAt = SYSDATETIME()
    WHERE BillId = @BillId;

    COMMIT TRANSACTION;

    SELECT
        @ReceiptNumber AS ReceiptNumber,
        @Amount AS PaidAmount,
        N'Оплата принята. Чек сформирован.' AS Message;
END;
GO

/* ============================================================================
   13. ПРЕДСТАВЛЕНИЯ ДЛЯ ИНТЕРФЕЙСА И ОТЧЁТОВ
============================================================================ */

CREATE OR ALTER VIEW dbo.vw_OrderTotals
AS
SELECT
    o.OrderId,
    o.ReservationId,
    o.VisitId,
    t.TableNumber,
    o.CreatedAt,
    o.FinalizedAt,
    os.StatusName AS OrderStatus,
    CONCAT(u.LastName, N' ', u.FirstName, N' ', ISNULL(u.MiddleName, N'')) AS WaiterFullName,
    SUM(oi.Quantity) AS TotalPortions,
    CAST(SUM(oi.Quantity * oi.UnitPrice) AS DECIMAL(12,2)) AS TotalAmount
FROM dbo.CustomerOrder o
JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
JOIN dbo.WaiterShift ws ON ws.ShiftId = o.WaiterShiftId
JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
JOIN dbo.AppUser u ON u.UserId = w.UserId
LEFT JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
GROUP BY
    o.OrderId, o.ReservationId, o.VisitId, t.TableNumber,
    o.CreatedAt, o.FinalizedAt, os.StatusName,
    u.LastName, u.FirstName, u.MiddleName;
GO

CREATE OR ALTER VIEW dbo.vw_TableScheme
AS
SELECT
    t.TableId,
    t.TableNumber,
    t.SeatsCount,
    t.HallZone,
    ts.StatusName AS CurrentStatus,
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM dbo.TableVisit tv
            JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
            WHERE tv.TableId = t.TableId
              AND vs.StatusCode = 'OPEN'
        ) THEN N'Занят'
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
    END AS AvailabilityNow
FROM dbo.RestaurantTable t
JOIN dbo.TableStatus ts ON ts.TableStatusId = t.TableStatusId
WHERE t.IsActive = 1;
GO

/* ============================================================================
   14. ПРОЦЕДУРЫ СТАТИСТИКИ
============================================================================ */

CREATE OR ALTER PROCEDURE dbo.sp_GetDishSalesComparison
    @Year INT,
    @Month INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentMonthStart DATE = DATEFROMPARTS(@Year, @Month, 1);
    DECLARE @NextMonthStart DATE = DATEADD(MONTH, 1, @CurrentMonthStart);
    DECLARE @PreviousMonthStart DATE = DATEADD(MONTH, -1, @CurrentMonthStart);

    ;WITH Sales AS
    (
        SELECT
            DATEFROMPARTS(YEAR(p.PaidAt), MONTH(p.PaidAt), 1) AS MonthStart,
            c.CategoryName,
            d.DishName,
            SUM(oi.Quantity) AS QuantitySold
        FROM dbo.Payment p
        JOIN dbo.Bill b ON b.BillId = p.BillId
        JOIN dbo.CustomerOrder o ON o.OrderId = b.OrderId
        JOIN dbo.OrderItem oi ON oi.OrderId = o.OrderId
        JOIN dbo.Dish d ON d.DishId = oi.DishId
        JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
        WHERE p.PaidAt >= @PreviousMonthStart
          AND p.PaidAt < @NextMonthStart
        GROUP BY
            DATEFROMPARTS(YEAR(p.PaidAt), MONTH(p.PaidAt), 1),
            c.CategoryName,
            d.DishName
    ),
    AllDishes AS
    (
        SELECT CategoryName, DishName FROM Sales
    )
    SELECT
        YEAR(@PreviousMonthStart) AS PreviousYear,
        MONTH(@PreviousMonthStart) AS PreviousMonth,
        YEAR(@CurrentMonthStart) AS CurrentYear,
        MONTH(@CurrentMonthStart) AS CurrentMonth,
        a.CategoryName,
        a.DishName,
        ISNULL(prev.QuantitySold, 0) AS PreviousMonthQuantity,
        ISNULL(curr.QuantitySold, 0) AS CurrentMonthQuantity,
        ISNULL(curr.QuantitySold, 0) - ISNULL(prev.QuantitySold, 0) AS SalesDifference
    FROM AllDishes a
    LEFT JOIN Sales prev
        ON prev.CategoryName = a.CategoryName
       AND prev.DishName = a.DishName
       AND prev.MonthStart = @PreviousMonthStart
    LEFT JOIN Sales curr
        ON curr.CategoryName = a.CategoryName
       AND curr.DishName = a.DishName
       AND curr.MonthStart = @CurrentMonthStart
    ORDER BY a.CategoryName, a.DishName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetReservationStatistics
    @Year INT,
    @Month INT
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        YEAR(r.StartAt) AS [Year],
        MONTH(r.StartAt) AS [Month],
        t.TableNumber,
        COUNT(*) AS ReservationsCount
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE YEAR(r.StartAt) = @Year
      AND MONTH(r.StartAt) = @Month
      AND rs.StatusCode <> 'CANCELLED'
    GROUP BY YEAR(r.StartAt), MONTH(r.StartAt), t.TableNumber
    ORDER BY t.TableNumber, ReservationsCount DESC;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterWorkComparison
    @Year INT,
    @Month INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @CurrentMonthStart DATE = DATEFROMPARTS(@Year, @Month, 1);
    DECLARE @NextMonthStart DATE = DATEADD(MONTH, 1, @CurrentMonthStart);
    DECLARE @PreviousMonthStart DATE = DATEADD(MONTH, -1, @CurrentMonthStart);

    ;WITH WaiterMonths AS
    (
        SELECT
            DATEFROMPARTS(YEAR(o.FinalizedAt), MONTH(o.FinalizedAt), 1) AS MonthStart,
            w.WaiterId,
            u.LastName,
            u.FirstName,
            u.MiddleName,
            COUNT(DISTINCT o.OrderId) AS AcceptedOrdersCount,
            COUNT(DISTINCT p.PaymentId) AS PaidReceiptsCount,
            CAST(ISNULL(SUM(p.PaidAmount), 0) AS DECIMAL(12,2)) AS PaidAmount
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        LEFT JOIN dbo.WaiterShift ws ON ws.WaiterId = w.WaiterId
        LEFT JOIN dbo.CustomerOrder o
            ON o.WaiterShiftId = ws.ShiftId
           AND o.FinalizedAt >= @PreviousMonthStart
           AND o.FinalizedAt < @NextMonthStart
        LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
        LEFT JOIN dbo.Payment p ON p.BillId = b.BillId
        WHERE o.FinalizedAt IS NOT NULL
        GROUP BY
            DATEFROMPARTS(YEAR(o.FinalizedAt), MONTH(o.FinalizedAt), 1),
            w.WaiterId, u.LastName, u.FirstName, u.MiddleName
    ),
    AllWaiters AS
    (
        SELECT DISTINCT WaiterId, LastName, FirstName, MiddleName
        FROM WaiterMonths
    )
    SELECT
        a.LastName,
        a.FirstName,
        a.MiddleName,
        ISNULL(prev.AcceptedOrdersCount, 0) AS PreviousMonthAcceptedOrders,
        ISNULL(curr.AcceptedOrdersCount, 0) AS CurrentMonthAcceptedOrders,
        ISNULL(curr.AcceptedOrdersCount, 0) - ISNULL(prev.AcceptedOrdersCount, 0) AS AcceptedOrdersDifference,
        ISNULL(prev.PaidReceiptsCount, 0) AS PreviousMonthPaidReceipts,
        ISNULL(curr.PaidReceiptsCount, 0) AS CurrentMonthPaidReceipts,
        ISNULL(curr.PaidReceiptsCount, 0) - ISNULL(prev.PaidReceiptsCount, 0) AS PaidReceiptsDifference,
        ISNULL(prev.PaidAmount, 0) AS PreviousMonthPaidAmount,
        ISNULL(curr.PaidAmount, 0) AS CurrentMonthPaidAmount,
        ISNULL(curr.PaidAmount, 0) - ISNULL(prev.PaidAmount, 0) AS PaidAmountDifference
    FROM AllWaiters a
    LEFT JOIN WaiterMonths prev
        ON prev.WaiterId = a.WaiterId
       AND prev.MonthStart = @PreviousMonthStart
    LEFT JOIN WaiterMonths curr
        ON curr.WaiterId = a.WaiterId
       AND curr.MonthStart = @CurrentMonthStart
    ORDER BY a.LastName, a.FirstName, a.MiddleName;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetTableDaySchedule
    @ScheduleDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Occupancy AS
    (
        SELECT
            t.TableNumber,
            r.StartAt,
            r.EndAt,
            CONCAT(N'Бронь №', r.ReservationId) AS OccupancyType
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE CONVERT(DATE, r.StartAt) = @ScheduleDate
          AND rs.StatusCode = 'ACTIVE'

        UNION ALL

        SELECT
            t.TableNumber,
            tv.StartedAt,
            ISNULL(tv.EndedAt, DATEADD(HOUR, 23, CAST(@ScheduleDate AS DATETIME2))),
            N'Занят без брони' AS OccupancyType
        FROM dbo.TableVisit tv
        JOIN dbo.RestaurantTable t ON t.TableId = tv.TableId
        JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
        WHERE CONVERT(DATE, tv.StartedAt) = @ScheduleDate
          AND vs.StatusCode IN ('OPEN', 'CLOSED')
    )
    SELECT
        @ScheduleDate AS ScheduleDate,
        t.TableNumber,
        o.StartAt,
        o.EndAt,
        ISNULL(o.OccupancyType, N'Свободен') AS Occupancy
    FROM dbo.RestaurantTable t
    LEFT JOIN Occupancy o ON o.TableNumber = t.TableNumber
    ORDER BY t.TableNumber, o.StartAt;
END;
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetHourlyTableOccupancy
    @ScheduleDate DATE
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH Hours AS
    (
        SELECT *
        FROM (VALUES
            (9,  N'09:00'), (10, N'10:00'), (11, N'11:00'), (12, N'12:00'),
            (13, N'13:00'), (14, N'14:00'), (15, N'15:00'), (16, N'16:00'),
            (17, N'17:00'), (18, N'18:00'), (19, N'19:00'), (20, N'20:00'),
            (21, N'21:00'), (22, N'22:00')
        ) AS h(HourNumber, HourLabel)
    ),
    SourceData AS
    (
        SELECT
            t.TableNumber,
            h.HourLabel,
            CASE
                WHEN EXISTS
                (
                    SELECT 1
                    FROM dbo.Reservation r
                    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
                    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
                    WHERE rt.TableId = t.TableId
                      AND rs.StatusCode = 'ACTIVE'
                      AND DATEADD(HOUR, h.HourNumber, CAST(@ScheduleDate AS DATETIME2)) < r.EndAt
                      AND DATEADD(HOUR, h.HourNumber + 1, CAST(@ScheduleDate AS DATETIME2)) > r.StartAt
                )
                OR EXISTS
                (
                    SELECT 1
                    FROM dbo.TableVisit tv
                    JOIN dbo.VisitStatus vs ON vs.VisitStatusId = tv.VisitStatusId
                    WHERE tv.TableId = t.TableId
                      AND vs.StatusCode IN ('OPEN', 'CLOSED')
                      AND DATEADD(HOUR, h.HourNumber, CAST(@ScheduleDate AS DATETIME2)) < ISNULL(tv.EndedAt, DATEADD(HOUR, 23, CAST(@ScheduleDate AS DATETIME2)))
                      AND DATEADD(HOUR, h.HourNumber + 1, CAST(@ScheduleDate AS DATETIME2)) > tv.StartedAt
                )
                THEN N'Бронь'
                ELSE N''
            END AS Occupancy
        FROM dbo.RestaurantTable t
        CROSS JOIN Hours h
        WHERE t.IsActive = 1
    )
    SELECT
        TableNumber,
        MAX(CASE WHEN HourLabel = N'09:00' THEN Occupancy END) AS [09:00],
        MAX(CASE WHEN HourLabel = N'10:00' THEN Occupancy END) AS [10:00],
        MAX(CASE WHEN HourLabel = N'11:00' THEN Occupancy END) AS [11:00],
        MAX(CASE WHEN HourLabel = N'12:00' THEN Occupancy END) AS [12:00],
        MAX(CASE WHEN HourLabel = N'13:00' THEN Occupancy END) AS [13:00],
        MAX(CASE WHEN HourLabel = N'14:00' THEN Occupancy END) AS [14:00],
        MAX(CASE WHEN HourLabel = N'15:00' THEN Occupancy END) AS [15:00],
        MAX(CASE WHEN HourLabel = N'16:00' THEN Occupancy END) AS [16:00],
        MAX(CASE WHEN HourLabel = N'17:00' THEN Occupancy END) AS [17:00],
        MAX(CASE WHEN HourLabel = N'18:00' THEN Occupancy END) AS [18:00],
        MAX(CASE WHEN HourLabel = N'19:00' THEN Occupancy END) AS [19:00],
        MAX(CASE WHEN HourLabel = N'20:00' THEN Occupancy END) AS [20:00],
        MAX(CASE WHEN HourLabel = N'21:00' THEN Occupancy END) AS [21:00],
        MAX(CASE WHEN HourLabel = N'22:00' THEN Occupancy END) AS [22:00]
    FROM SourceData
    GROUP BY TableNumber
    ORDER BY TableNumber;
END;
GO

/* ============================================================================
   15. ТЕСТОВЫЕ ПОЛЬЗОВАТЕЛИ, КЛИЕНТЫ И ОФИЦИАНТЫ
============================================================================ */

EXEC dbo.sp_RegisterUser
    @Login = N'admin',
    @Password = N'admin123',
    @RoleCode = 'ADMIN',
    @LastName = N'Иванов',
    @FirstName = N'Иван',
    @MiddleName = N'Иванович',
    @Phone = N'+7 900 000-00-01',
    @Email = N'admin@restaurant.local';
GO

EXEC dbo.sp_RegisterUser
    @Login = N'waiter1',
    @Password = N'waiter123',
    @RoleCode = 'WAITER',
    @LastName = N'Петров',
    @FirstName = N'Алексей',
    @MiddleName = N'Сергеевич',
    @Phone = N'+7 900 000-00-02',
    @Email = N'waiter1@restaurant.local';
GO

EXEC dbo.sp_RegisterUser
    @Login = N'waiter2',
    @Password = N'waiter123',
    @RoleCode = 'WAITER',
    @LastName = N'Сидорова',
    @FirstName = N'Мария',
    @MiddleName = N'Игоревна',
    @Phone = N'+7 900 000-00-03',
    @Email = N'waiter2@restaurant.local';
GO

EXEC dbo.sp_RegisterUser
    @Login = N'kitchen1',
    @Password = N'kitchen123',
    @RoleCode = 'KITCHEN',
    @LastName = N'Кузнецов',
    @FirstName = N'Дмитрий',
    @MiddleName = N'Олегович',
    @Phone = N'+7 900 000-00-04',
    @Email = N'kitchen1@restaurant.local';
GO

EXEC dbo.sp_RegisterUser
    @Login = N'client1',
    @Password = N'client123',
    @RoleCode = 'CLIENT',
    @LastName = N'Смирнов',
    @FirstName = N'Антон',
    @MiddleName = N'Павлович',
    @Phone = N'+7 900 000-00-05',
    @Email = N'client1@restaurant.local';
GO

INSERT INTO dbo.Waiter (UserId)
SELECT UserId
FROM dbo.AppUser
WHERE Login IN (N'waiter1', N'waiter2');
GO

INSERT INTO dbo.Client (UserId, FullName, Phone, Email)
SELECT
    UserId,
    CONCAT(LastName, N' ', FirstName, N' ', MiddleName),
    Phone,
    Email
FROM dbo.AppUser
WHERE Login = N'client1';
GO

/* ============================================================================
   16. ПРИМЕР ПЛАНИРОВАНИЯ СМЕНЫ И НАЗНАЧЕНИЯ СТОЛИКОВ
============================================================================ */

DECLARE @Today DATE = CONVERT(DATE, GETDATE());
DECLARE @Waiter1 INT = (SELECT w.WaiterId FROM dbo.Waiter w JOIN dbo.AppUser u ON u.UserId = w.UserId WHERE u.Login = N'waiter1');
DECLARE @Waiter2 INT = (SELECT w.WaiterId FROM dbo.Waiter w JOIN dbo.AppUser u ON u.UserId = w.UserId WHERE u.Login = N'waiter2');

INSERT INTO dbo.WaiterShift (WaiterId, ShiftStatusId, PlannedStartAt, PlannedEndAt)
VALUES
(
    @Waiter1,
    (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
    DATEADD(HOUR, 9, CAST(@Today AS DATETIME2)),
    DATEADD(HOUR, 23, CAST(@Today AS DATETIME2))
),
(
    @Waiter2,
    (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
    DATEADD(HOUR, 9, CAST(@Today AS DATETIME2)),
    DATEADD(HOUR, 23, CAST(@Today AS DATETIME2))
);

DECLARE @Shift1 INT =
(
    SELECT MIN(ShiftId)
    FROM dbo.WaiterShift
    WHERE WaiterId = @Waiter1
      AND PlannedStartAt = DATEADD(HOUR, 9, CAST(@Today AS DATETIME2))
);

DECLARE @Shift2 INT =
(
    SELECT MIN(ShiftId)
    FROM dbo.WaiterShift
    WHERE WaiterId = @Waiter2
      AND PlannedStartAt = DATEADD(HOUR, 9, CAST(@Today AS DATETIME2))
);

INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
SELECT @Shift1, TableId
FROM dbo.RestaurantTable
WHERE TableNumber IN (1, 2, 3, 4);

INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
SELECT @Shift2, TableId
FROM dbo.RestaurantTable
WHERE TableNumber IN (5, 6, 7, 8);
GO

/* ============================================================================
   17. ПРИМЕРЫ ЗАПРОСОВ ДЛЯ ПРОВЕРКИ В SSMS
   Раскомментируйте нужный блок и выполните отдельно.

-- 0. Проверить авторизацию:
EXEC dbo.sp_AuthenticateUser @Login = N'admin', @Password = N'admin123';

-- 1. Открыть смену первого официанта:
DECLARE @ShiftId INT =
(
    SELECT TOP (1) ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE u.Login = N'waiter1'
    ORDER BY ws.ShiftId DESC
);
EXEC dbo.sp_OpenWaiterShift @ShiftId = @ShiftId;

-- 2. Создать бронь:
DECLARE @Tables dbo.TableIdList;
INSERT INTO @Tables (TableId)
SELECT TableId FROM dbo.RestaurantTable WHERE TableNumber = 3;

DECLARE @ClientId INT = (SELECT ClientId FROM dbo.Client WHERE Phone = N'+7 900 000-00-05');

EXEC dbo.sp_CreateReservation
    @ClientId = @ClientId,
    @StartAt = DATEADD(HOUR, 12, CAST(DATEADD(DAY, 1, CONVERT(DATE, GETDATE())) AS DATETIME2)),
    @EndAt = DATEADD(HOUR, 14, CAST(DATEADD(DAY, 1, CONVERT(DATE, GETDATE())) AS DATETIME2)),
    @GuestCount = 4,
    @Comment = N'Тестовая бронь',
    @TableIds = @Tables;

-- 3. Показать свободные столики на текущее время:
EXEC dbo.sp_GetAvailableTables @AtTime = NULL;

-- 4. Открыть посещение без брони и создать заказ:
DECLARE @ShiftId INT =
(
    SELECT TOP (1) ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE u.Login = N'waiter1'
    ORDER BY ws.ShiftId DESC
);
DECLARE @TableId INT = (SELECT TableId FROM dbo.RestaurantTable WHERE TableNumber = 1);

EXEC dbo.sp_OpenTableVisit
    @TableId = @TableId,
    @WaiterShiftId = @ShiftId,
    @GuestCount = 2;

DECLARE @VisitId INT = (SELECT MAX(VisitId) FROM dbo.TableVisit WHERE TableId = @TableId);

EXEC dbo.sp_CreateOrder
    @TableId = @TableId,
    @WaiterShiftId = @ShiftId,
    @VisitId = @VisitId;

DECLARE @OrderId INT = (SELECT MAX(OrderId) FROM dbo.CustomerOrder);

EXEC dbo.sp_AddDishToOrder @OrderId = @OrderId, @DishId = 1, @Quantity = 2;
EXEC dbo.sp_AddDishToOrder @OrderId = @OrderId, @DishId = 9, @Quantity = 2;
EXEC dbo.sp_FinalizeOrder @OrderId = @OrderId;
EXEC dbo.sp_SetKitchenOrderStatus @OrderId = @OrderId, @NewStatusCode = 'PREPARING';
EXEC dbo.sp_SetKitchenOrderStatus @OrderId = @OrderId, @NewStatusCode = 'READY';
EXEC dbo.sp_SetKitchenOrderStatus @OrderId = @OrderId, @NewStatusCode = 'ACCEPTED';
EXEC dbo.sp_PayOrder @OrderId = @OrderId, @PaymentMethodCode = 'CARD';
EXEC dbo.sp_IssueOrderToClient @OrderId = @OrderId;

-- 5. Статистика:
EXEC dbo.sp_GetDishSalesComparison @Year = YEAR(GETDATE()), @Month = MONTH(GETDATE());
EXEC dbo.sp_GetReservationStatistics @Year = YEAR(GETDATE()), @Month = MONTH(GETDATE());
EXEC dbo.sp_GetWaiterWorkComparison @Year = YEAR(GETDATE()), @Month = MONTH(GETDATE());
EXEC dbo.sp_GetTableDaySchedule @ScheduleDate = CONVERT(DATE, GETDATE());
EXEC dbo.sp_GetHourlyTableOccupancy @ScheduleDate = CONVERT(DATE, GETDATE());

-- 6. Данные для схемы столиков в интерфейсе:
SELECT * FROM dbo.vw_TableScheme ORDER BY TableNumber;
SELECT * FROM dbo.vw_OrderTotals ORDER BY OrderId DESC;
============================================================================ */
GO

PRINT N'База данных WhiteRabbitRestaurant для ресторана White Rabbit успешно создана.';
GO

/* ================== 2. ФУНКЦИИ ИНТЕРФЕЙСА v1.8 ================== */
/*
  White Rabbit — единое обновление v1.8
  Выполните этот файл один раз в SSMS после создания базы WhiteRabbitRestaurant.
  Включает логику v1.7 и v1.8.
*/

/*
  White Rabbit — обновление списков v1.7
  Запускается один раз в SSMS после создания базы WhiteRabbitRestaurant.

  Результат:
  1. После статуса «Принят на выдачу» заказ исчезает из очереди кухни.
  2. После отмены бронь исчезает из списка активных бронирований.
  История записей остаётся в таблицах базы данных.
*/
USE WhiteRabbitRestaurant;
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

CREATE OR ALTER VIEW dbo.vw_Reservations
AS
SELECT
    r.ReservationId,
    c.FullName AS Клиент,
    c.Phone AS Телефон,
    r.StartAt AS Начало,
    r.EndAt AS Конец,
    r.GuestCount AS Гостей,
    rs.StatusName AS Статус,
    STRING_AGG(CONVERT(NVARCHAR(10), t.TableNumber), N', ') AS Столики
FROM dbo.Reservation r
JOIN dbo.Client c ON c.ClientId = r.ClientId
JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
JOIN dbo.RestaurantTable t ON t.TableId = rt.TableId
WHERE rs.StatusCode = 'ACTIVE'
GROUP BY
    r.ReservationId,
    c.FullName,
    c.Phone,
    r.StartAt,
    r.EndAt,
    r.GuestCount,
    rs.StatusName;
GO

PRINT N'Обновление v1.7 успешно применено.';
GO


/*
  White Rabbit — обновление v1.8
  Запустите этот файл ОДИН РАЗ в SQL Server Management Studio
  после базового скрипта WhiteRabbitRestaurant и обновления v1.7.

  Добавляет:
  - создание официантов и сотрудников кухни администратором;
  - планирование смен официантов с назначением столиков;
  - открытие и закрытие смены официантом;
  - освобождение столика после ухода гостей.
*/
USE WhiteRabbitRestaurant;
GO

IF COL_LENGTH('dbo.WaiterShift', 'ActualCloseAt') IS NULL
BEGIN
    ALTER TABLE dbo.WaiterShift ADD ActualCloseAt DATETIME2 NULL;
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

CREATE OR ALTER PROCEDURE dbo.sp_GetAdminEmployees
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        u.Login AS [Логин],
        CONCAT(u.LastName, N' ', u.FirstName) AS [Сотрудник],
        r.RoleName AS [Роль],
        ISNULL(u.Phone, N'—') AS [Телефон],
        CASE WHEN u.IsActive = 1 THEN N'Да' ELSE N'Нет' END AS [Активен]
    FROM dbo.AppUser u
    JOIN dbo.AppRole r ON r.RoleId = u.RoleId
    WHERE r.RoleCode IN ('WAITER', 'KITCHEN')
    ORDER BY r.RoleName, u.LastName, u.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiters
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        u.UserId,
        w.WaiterId,
        u.Login AS [Логин],
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант]
    FROM dbo.Waiter w
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE u.IsActive = 1
    ORDER BY u.LastName, u.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetAllRestaurantTables
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
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(200)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51103, N'Время окончания смены должно быть позже времени начала.', 1;

    DECLARE @WaiterId INT =
    (
        SELECT w.WaiterId
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        WHERE u.UserId = @WaiterUserId
          AND u.IsActive = 1
    );

    IF @WaiterId IS NULL
        THROW 51104, N'Официант не найден или отключён.', 1;

    DECLARE @RequestedNumbers TABLE (TableNumber INT NOT NULL PRIMARY KEY);
    INSERT INTO @RequestedNumbers (TableNumber)
    SELECT DISTINCT TRY_CONVERT(INT, LTRIM(RTRIM(value)))
    FROM STRING_SPLIT(@TableNumbers, N',')
    WHERE TRY_CONVERT(INT, LTRIM(RTRIM(value))) IS NOT NULL;

    IF NOT EXISTS (SELECT 1 FROM @RequestedNumbers)
        THROW 51105, N'Необходимо указать хотя бы один столик.', 1;

    DECLARE @Tables TABLE (TableId INT NOT NULL PRIMARY KEY);
    INSERT INTO @Tables (TableId)
    SELECT t.TableId
    FROM dbo.RestaurantTable t
    JOIN @RequestedNumbers n ON n.TableNumber = t.TableNumber
    WHERE t.IsActive = 1;

    IF (SELECT COUNT(*) FROM @Tables) <> (SELECT COUNT(*) FROM @RequestedNumbers)
        THROW 51106, N'Один или несколько выбранных столиков не существуют или отключены.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51107, N'У этого официанта уже есть пересекающаяся смена.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
        JOIN @Tables t ON t.TableId = a.TableId
        WHERE ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51108, N'Один или несколько столиков уже закреплены за другим официантом на это время.', 1;

    BEGIN TRANSACTION;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId,
        ShiftStatusId,
        PlannedStartAt,
        PlannedEndAt
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt,
        @PlannedEndAt
    );

    DECLARE @ShiftId INT = SCOPE_IDENTITY();

    INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
    SELECT @ShiftId, TableId
    FROM @Tables;

    COMMIT TRANSACTION;

    SELECT
        @ShiftId AS ShiftId,
        N'Смена создана, столики закреплены за официантом.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        ws.ShiftId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        ws.PlannedStartAt AS [Начало смены],
        ws.PlannedEndAt AS [Конец смены],
        ss.StatusName AS [Статус],
        COALESCE(STRING_AGG(CONVERT(NVARCHAR(10), t.TableNumber), N', '), N'—') AS [Столики]
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    LEFT JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    LEFT JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    GROUP BY
        ws.ShiftId,
        u.LastName,
        u.FirstName,
        ws.PlannedStartAt,
        ws.PlannedEndAt,
        ss.StatusName
    ORDER BY ws.PlannedStartAt DESC, u.LastName, u.FirstName;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;

    DECLARE @OpenShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @UserId
          AND ss.StatusCode = 'OPEN'
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.PlannedStartAt DESC
    );

    IF @OpenShiftId IS NOT NULL
    BEGIN
        SELECT @OpenShiftId AS ShiftId, N'Смена уже открыта.' AS Message;
        RETURN;
    END

    DECLARE @ShiftId INT =
    (
        SELECT TOP (1) ws.ShiftId
        FROM dbo.WaiterShift ws
        JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE w.UserId = @UserId
          AND ss.StatusCode = 'PLANNED'
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.PlannedStartAt
    );

    IF @ShiftId IS NULL
        THROW 51109, N'На сегодня нет запланированной смены.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = COALESCE(ActualOpenAt, SYSDATETIME())
    WHERE ShiftId = @ShiftId;

    SELECT @ShiftId AS ShiftId, N'Смена открыта. Закреплённые столики доступны для работы.' AS Message;
END
GO

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
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, GETDATE())
        ORDER BY ws.PlannedStartAt DESC
    );

    IF @ShiftId IS NULL
        THROW 51110, N'У вас нет открытой смены на сегодня.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.WaiterShiftId = @ShiftId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED')
    )
        THROW 51111, N'Нельзя закрыть смену: есть активные заказы. Освободите столики после ухода гостей.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = SYSDATETIME()
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена закрыта.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_FreeTable
    @TableId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF NOT EXISTS (SELECT 1 FROM dbo.RestaurantTable WHERE TableId = @TableId AND IsActive = 1)
        THROW 51112, N'Столик не найден или отключён.', 1;

    DECLARE @ActiveOrders INT =
    (
        SELECT COUNT(*)
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
        WHERE o.TableId = @TableId
          AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED')
    );

    DECLARE @ActiveReservations INT =
    (
        SELECT COUNT(*)
        FROM dbo.Reservation r
        JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
        JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
        WHERE rt.TableId = @TableId
          AND rs.StatusCode = 'ACTIVE'
          AND SYSDATETIME() >= r.StartAt
          AND SYSDATETIME() < r.EndAt
    );

    IF @ActiveOrders = 0 AND @ActiveReservations = 0
        THROW 51113, N'Этот столик уже свободен.', 1;

    BEGIN TRANSACTION;

    UPDATE o
    SET OrderStatusId = (SELECT OrderStatusId FROM dbo.OrderStatus WHERE StatusCode = 'COMPLETED')
    FROM dbo.CustomerOrder o
    JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
    WHERE o.TableId = @TableId
      AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED');

    UPDATE r
    SET ReservationStatusId = (SELECT ReservationStatusId FROM dbo.ReservationStatus WHERE StatusCode = 'COMPLETED')
    FROM dbo.Reservation r
    JOIN dbo.ReservationTable rt ON rt.ReservationId = r.ReservationId
    JOIN dbo.ReservationStatus rs ON rs.ReservationStatusId = r.ReservationStatusId
    WHERE rt.TableId = @TableId
      AND rs.StatusCode = 'ACTIVE'
      AND SYSDATETIME() >= r.StartAt
      AND SYSDATETIME() < r.EndAt;

    COMMIT TRANSACTION;

    SELECT N'Столик освобождён. Активный заказ и текущая бронь завершены.' AS Message;
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
              AND s.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED')
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
    END AS [Доступность]
FROM dbo.RestaurantTable t
WHERE t.IsActive = 1;
GO

PRINT N'Обновление White Rabbit v1.8 успешно применено.';
GO

/* ================== SQL_Update_v2_0_Logic_Fixes.sql ================== */
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

/* ================== SQL_Update_v2_1_Service_Bill_Payment.sql ================== */
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

/* ================== SQL_Update_v2_3_Reports_And_Stock.sql ================== */
/*
  White Rabbit v2.3 — отчёт по продажам и пополнение склада.
  Выполните ОДИН РАЗ в SSMS после SQL-обновлений v2.0 и v2.1.
*/
USE WhiteRabbitRestaurant;
GO

/* История пополнений склада. Создаётся один раз и не влияет на старые данные. */
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
        CreatedAt DATETIME2 NOT NULL CONSTRAINT DF_DishStockMovement_CreatedAt DEFAULT (SYSDATETIME()),

        CONSTRAINT CK_DishStockMovement_Quantity CHECK (Quantity > 0),
        CONSTRAINT FK_DishStockMovement_Dish FOREIGN KEY (DishId) REFERENCES dbo.Dish(DishId),
        CONSTRAINT FK_DishStockMovement_Admin FOREIGN KEY (AdminUserId) REFERENCES dbo.AppUser(UserId)
    );
END
GO

IF NOT EXISTS
(
    SELECT 1
    FROM sys.indexes
    WHERE name = N'IX_DishStockMovement_Dish_CreatedAt'
      AND object_id = OBJECT_ID(N'dbo.DishStockMovement')
)
BEGIN
    CREATE INDEX IX_DishStockMovement_Dish_CreatedAt
        ON dbo.DishStockMovement(DishId, CreatedAt DESC);
END
GO

/* Детальный отчёт по фактически оплаченным продажам за выбранный период. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminSalesReport
    @DateFrom DATE,
    @DateTo DATE
AS
BEGIN
    SET NOCOUNT ON;

    IF @DateTo < @DateFrom
        THROW 51401, N'Дата окончания периода не может быть раньше даты начала.', 1;

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
END
GO

/* Остатки блюд и их доступность для администратора. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStock
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        ds.AvailablePortions AS [Остаток, порций],
        CASE WHEN ISNULL(sl.IsStopListed, 0) = 1 THEN N'Да' ELSE N'Нет' END AS [Стоп-лист],
        CASE WHEN d.IsActive = 1 THEN N'Да' ELSE N'Нет' END AS [Доступно в меню]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    LEFT JOIN dbo.DishStock ds ON ds.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    ORDER BY c.CategoryName, d.DishName;
END
GO

/* История последних пополнений склада. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminGetStockMovements
AS
BEGIN
    SET NOCOUNT ON;

    SELECT TOP (100)
        m.StockMovementId,
        m.CreatedAt AS [Дата и время],
        c.CategoryName AS [Категория],
        d.DishName AS [Блюдо],
        m.Quantity AS [Добавлено порций],
        CONCAT(u.LastName, N' ', u.FirstName) AS [Администратор],
        m.Comment AS [Комментарий]
    FROM dbo.DishStockMovement m
    JOIN dbo.Dish d ON d.DishId = m.DishId
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.AppUser u ON u.UserId = m.AdminUserId
    ORDER BY m.CreatedAt DESC, m.StockMovementId DESC;
END
GO

/* Пополнение остатков. Доступно только активному администратору. */
CREATE OR ALTER PROCEDURE dbo.sp_AdminRestockDish
    @AdminUserId INT,
    @DishId INT,
    @Quantity INT,
    @Comment NVARCHAR(250) = NULL
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @Quantity <= 0
        THROW 51402, N'Количество порций для пополнения должно быть больше нуля.', 1;

    IF NOT EXISTS
    (
        SELECT 1
        FROM dbo.AppUser u
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE u.UserId = @AdminUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51403, N'Пополнять склад может только активный администратор.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dish WHERE DishId = @DishId)
        THROW 51404, N'Блюдо не найдено.', 1;

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
    VALUES(@DishId, @Quantity, 'RESTOCK', @AdminUserId, @Comment);

    COMMIT TRANSACTION;

    SELECT
        CONCAT(N'Склад пополнен: «', @DishName, N'» +', @Quantity, N' порц. Текущий остаток: ', @NewStock, N' порц.') AS Message,
        @NewStock AS AvailablePortions;
END
GO

/* ================== SQL_Update_v2_4_Order_Status_And_Shifts.sql ================== */
/*
 White Rabbit v2.4 — статусы заказов и полный контроль смен.
 Выполните ОДИН РАЗ в SSMS после обновлений v2.0, v2.1 и v2.3.

 Добавлено:
 1) Просмотр статусов заказов: администратор — все заказы, клиент — свои заказы.
 2) Администратор может открыть и закрыть выбранную смену официанта.
 3) Смена автоматически закрывается по PlannedEndAt, если по ней нет незавершённых заказов.
 4) При раннем закрытии смены причина обязательна.
 5) Официант открывает только назначенную смену в её плановом временном интервале.
 6) Смену нельзя назначить «на год»: только в пределах одного дня, с 09:00 до 23:00,
    длительностью не более 14 часов.
*/
USE WhiteRabbitRestaurant;
GO

/* ====== 1. Поля аудита закрытия смены ====== */
IF COL_LENGTH('dbo.WaiterShift', 'CloseReason') IS NULL
    ALTER TABLE dbo.WaiterShift ADD CloseReason NVARCHAR(500) NULL;
GO

IF COL_LENGTH('dbo.WaiterShift', 'ClosedByUserId') IS NULL
    ALTER TABLE dbo.WaiterShift ADD ClosedByUserId INT NULL;
GO

IF COL_LENGTH('dbo.WaiterShift', 'WasClosedAutomatically') IS NULL
    ALTER TABLE dbo.WaiterShift
        ADD WasClosedAutomatically BIT NOT NULL
            CONSTRAINT DF_WaiterShift_WasClosedAutomatically DEFAULT (0) WITH VALUES;
GO

/* ====== 2. Автоматическое закрытие по окончании планового времени ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AutoCloseExpiredWaiterShifts
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
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = CASE
            WHEN ss.StatusCode = 'PLANNED' THEN N'Автоматически закрыта: смена не была открыта до окончания планового времени.'
            ELSE N'Автоматически закрыта по окончании планового времени.'
        END,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 1
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ss.StatusCode IN ('OPEN', 'PLANNED')
      AND ws.ActualCloseAt IS NULL
      AND ws.PlannedEndAt <= @Now
      AND
      (
          ss.StatusCode = 'PLANNED'
          OR NOT EXISTS
          (
          SELECT 1
          FROM dbo.CustomerOrder o
          JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
          WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
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
                WHEN @ClosedCount = 0 THEN N'Смен для автоматического закрытия нет.'
                ELSE CONCAT(N'Автоматически закрыто смен: ', @ClosedCount, N'.')
            END AS Message;
    END
END
GO

/* ====== 3. Открытие смены официантом только в назначенное время ====== */
CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @ShiftId INT;

    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE w.UserId = @UserId
      AND u.IsActive = 1
      AND ss.StatusCode = 'PLANNED'
      AND ws.ActualOpenAt IS NULL
      AND ws.PlannedStartAt <= @Now
      AND ws.PlannedEndAt > @Now
    ORDER BY ws.PlannedStartAt, ws.ShiftId;

    IF @ShiftId IS NULL
    BEGIN
        IF EXISTS
        (
            SELECT 1
            FROM dbo.WaiterShift ws
            JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
            JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
            WHERE w.UserId = @UserId
              AND ss.StatusCode = 'PLANNED'
              AND ws.ActualOpenAt IS NULL
              AND @Now < ws.PlannedStartAt
        )
            THROW 51401, N'Смену нельзя открыть раньше назначенного времени.', 1;

        THROW 51402, N'Нет доступной запланированной смены на текущее время. Открыть смену на произвольный срок нельзя.', 1;
    END

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT @ShiftId AS ShiftId, N'Смена успешно открыта.' AS Message;
END
GO

/* ====== 4. Закрытие смены официантом ====== */
CREATE OR ALTER PROCEDURE dbo.sp_CloseCurrentWaiterShift
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
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NULL
        THROW 51403, N'У вас нет открытой смены.', 1;

    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51404, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
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
        THROW 51405, N'Нельзя закрыть смену: есть незавершённые заказы. Завершите обслуживание и закройте счета.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @UserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена закрыта.' AS Message;
END
GO

/* ====== 5. Управление сменами администратором ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminOpenWaiterShift
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
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51406, N'Открывать смены может только администратор.', 1;

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
        THROW 51407, N'Смена не найдена.', 1;

    IF @StatusCode <> 'PLANNED'
        THROW 51408, N'Открыть можно только запланированную смену.', 1;

    IF @Now < @PlannedStartAt OR @Now >= @PlannedEndAt
        THROW 51409, N'Открыть смену можно только в её назначенном временном интервале.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена официанта открыта администратором.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AdminCloseWaiterShift
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
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51410, N'Закрывать смены может только администратор.', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT
        @PlannedEndAt = ws.PlannedEndAt,
        @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51411, N'Смена не найдена.', 1;

    IF @StatusCode <> 'OPEN'
        THROW 51412, N'Закрыть можно только открытую смену.', 1;

    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51413, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
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
        THROW 51414, N'Нельзя закрыть смену: у официанта есть незавершённые заказы.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @AdminUserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    SELECT N'Смена официанта закрыта администратором.' AS Message;
END
GO

/* ====== 6. Планирование смен: защита от смен «на год» ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(400)
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51415, N'Время окончания смены должно быть позже времени начала.', 1;

    IF CONVERT(DATE, @PlannedStartAt) <> CONVERT(DATE, @PlannedEndAt)
       OR CONVERT(TIME, @PlannedStartAt) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @PlannedEndAt) > CONVERT(TIME, '23:00:00')
       OR DATEDIFF(MINUTE, @PlannedStartAt, @PlannedEndAt) > 840
        THROW 51416, N'Смена должна быть в пределах одного дня, времени работы ресторана 09:00–23:00 и длиться не более 14 часов.', 1;

    DECLARE @WaiterId INT =
    (
        SELECT w.WaiterId
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE w.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'WAITER'
    );

    IF @WaiterId IS NULL
        THROW 51417, N'Выбранный пользователь не является активным официантом.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51418, N'У официанта уже есть пересекающаяся смена.', 1;

    DECLARE @Tables TABLE (TableId INT NOT NULL PRIMARY KEY);

    INSERT INTO @Tables (TableId)
    SELECT DISTINCT t.TableId
    FROM STRING_SPLIT(@TableNumbers, ',') value_list
    JOIN dbo.RestaurantTable t
      ON t.TableNumber = TRY_CONVERT(INT, LTRIM(RTRIM(value_list.value)))
     AND t.IsActive = 1;

    IF NOT EXISTS (SELECT 1 FROM @Tables)
        THROW 51419, N'Укажите хотя бы один действующий столик.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
        JOIN @Tables nt ON nt.TableId = a.TableId
        WHERE ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51420, N'Один из выбранных столиков уже закреплён за другим официантом в пересекающуюся смену.', 1;

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
        WasClosedAutomatically
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt,
        @PlannedEndAt,
        NULL,
        NULL,
        NULL,
        NULL,
        0
    );

    DECLARE @ShiftId INT = SCOPE_IDENTITY();

    INSERT INTO dbo.WaiterTableAssignment (ShiftId, TableId)
    SELECT @ShiftId, TableId
    FROM @Tables;

    COMMIT TRANSACTION;

    SELECT @ShiftId AS ShiftId, N'Смена создана, столики закреплены.' AS Message;
END
GO

/* ====== 7. Вывод графика и статусов заказов ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    SELECT
        ws.ShiftId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        ws.PlannedStartAt AS [Начало по графику],
        ws.PlannedEndAt AS [Конец по графику],
        ws.ActualOpenAt AS [Фактическое открытие],
        ws.ActualCloseAt AS [Фактическое закрытие],
        ss.StatusName AS [Статус],
        ISNULL(ws.CloseReason, N'—') AS [Причина закрытия],
        CASE WHEN ws.WasClosedAutomatically = 1 THEN N'Да' ELSE N'Нет' END AS [Автозакрытие],
        ISNULL(STRING_AGG(CONCAT(N'№', t.TableNumber), N', '), N'—') AS [Столики]
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    LEFT JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    LEFT JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    GROUP BY
        ws.ShiftId, u.LastName, u.FirstName,
        ws.PlannedStartAt, ws.PlannedEndAt,
        ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY ws.PlannedStartAt DESC, ws.ShiftId DESC;
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

/* После окончания времени смены столики официанту больше не выдаются для новых заказов. */
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();

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
      AND @Now >= ws.PlannedStartAt
      AND @Now < ws.PlannedEndAt
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.4: статусы заказов и безопасное управление сменами добавлены.';
GO

/* ================== SQL_Update_v2_5_Reservation_Guest_Client_Fix.sql ================== */
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

/* ================== SQL_Update_v2_6_Reservation_Procedure_And_Table_Map.sql ================== */
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

/* ================== SQL_Update_v2_7_Flexible_Shifts_And_Auto_Table_Distribution.sql ================== */
/*
 White Rabbit v2.7 — гибкие смены и автоматическое распределение столиков.
 Выполните ОДИН РАЗ после обновления v2.6.

 Что изменено:
 1) Администратор по-прежнему может планировать смену официанту.
 2) Официант может открыть самостоятельную смену по приходу, если на это время
    у него нет назначенной смены. Такая смена действует до 23:00 текущего дня.
 3) Все открытые смены отображаются администратору.
 4) Столики автоматически распределяются по кругу между всеми официантами
    с открытой сменой. При открытии или закрытии смены распределение пересчитывается.
*/
USE WhiteRabbitRestaurant;
GO

IF COL_LENGTH('dbo.WaiterShift', 'IsWalkInShift') IS NULL
    ALTER TABLE dbo.WaiterShift
        ADD IsWalkInShift BIT NOT NULL
            CONSTRAINT DF_WaiterShift_IsWalkInShift DEFAULT (0) WITH VALUES;
GO

/* ====== 1. Автоматическое равномерное распределение активных столиков ====== */
CREATE OR ALTER PROCEDURE dbo.sp_RebalanceOpenWaiterTables
    @AdminUserId INT = NULL
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
             AND r.RoleCode = 'ADMIN'
       )
        THROW 51501, N'Перераспределять столики может только администратор.', 1;

    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @OpenShifts TABLE
    (
        ShiftId INT NOT NULL PRIMARY KEY,
        ShiftRank INT NOT NULL
    );

    INSERT INTO @OpenShifts (ShiftId, ShiftRank)
    SELECT
        ws.ShiftId,
        ROW_NUMBER() OVER (ORDER BY ws.ActualOpenAt, ws.ShiftId)
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    WHERE ss.StatusCode = 'OPEN'
      AND u.IsActive = 1
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
      AND @Now < ws.PlannedEndAt;

    DECLARE @WaiterCount INT = (SELECT COUNT(*) FROM @OpenShifts);

    IF @WaiterCount = 0
    BEGIN
        SELECT 0 AS WaiterCount, 0 AS TableCount, N'Открытых смен нет: распределение столиков не требуется.' AS Message;
        RETURN;
    END

    BEGIN TRANSACTION;

    /* Меняются только назначения открытых смен. История закрытых и будущих смен сохраняется. */
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

    DECLARE @TableCount INT = (SELECT COUNT(*) FROM dbo.RestaurantTable WHERE IsActive = 1);

    COMMIT TRANSACTION;

    SELECT
        @WaiterCount AS WaiterCount,
        @TableCount AS TableCount,
        N'Столики автоматически распределены между открытыми сменами официантов.' AS Message;
END
GO

/* ====== 2. Открытие смены официантом: плановая или самостоятельная ====== */
CREATE OR ALTER PROCEDURE dbo.sp_OpenCurrentWaiterShift
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
      AND r.RoleCode = 'WAITER';

    IF @WaiterId IS NULL
        THROW 51502, N'Открыть смену может только активный официант.', 1;

    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NOT NULL
    BEGIN
        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N'У вас уже открыта смена. Столики актуализированы автоматически.' AS Message;
        RETURN;
    END

    /* Сначала открываем подходящую смену, созданную администратором. */
    SELECT TOP (1) @ShiftId = ws.ShiftId
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.WaiterId = @WaiterId
      AND ss.StatusCode = 'PLANNED'
      AND ws.ActualOpenAt IS NULL
      AND ws.PlannedStartAt <= @Now
      AND ws.PlannedEndAt > @Now
    ORDER BY ws.PlannedStartAt, ws.ShiftId;

    IF @ShiftId IS NOT NULL
    BEGIN
        UPDATE dbo.WaiterShift
        SET
            ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
            ActualOpenAt = @Now,
            ActualCloseAt = NULL,
            CloseReason = NULL,
            ClosedByUserId = NULL,
            WasClosedAutomatically = 0,
            IsWalkInShift = 0
        WHERE ShiftId = @ShiftId;

        EXEC dbo.sp_RebalanceOpenWaiterTables;
        SELECT @ShiftId AS ShiftId, N'Назначенная смена открыта. Столики распределены автоматически.' AS Message;
        RETURN;
    END

    /* Если графика на текущее время нет, создаётся самостоятельная смена до 23:00. */
    IF CONVERT(TIME, @Now) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @Now) >= CONVERT(TIME, '23:00:00')
        THROW 51503, N'Самостоятельную смену можно открыть только в часы работы ресторана: с 09:00 до 23:00.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode = 'PLANNED'
          AND ws.ActualOpenAt IS NULL
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
          AND ws.PlannedStartAt > @Now
    )
        THROW 51504, N'На сегодня уже есть назначенная смена. Откройте её в указанное время.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        WHERE ws.WaiterId = @WaiterId
          AND ws.IsWalkInShift = 1
          AND CONVERT(DATE, ws.PlannedStartAt) = CONVERT(DATE, @Now)
    )
        THROW 51505, N'Самостоятельная смена этого официанта уже была создана сегодня.', 1;

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
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
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
    SELECT @ShiftId AS ShiftId, N'Самостоятельная смена открыта до 23:00 и отображается у администратора. Столики распределены автоматически.' AS Message;
END
GO

/* ====== 3. Открытие плановой смены администратором ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminOpenWaiterShift
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
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51506, N'Открывать смены может только администратор.', 1;

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
        THROW 51507, N'Смена не найдена.', 1;
    IF @StatusCode <> 'PLANNED'
        THROW 51508, N'Открыть можно только запланированную смену.', 1;
    IF @Now < @PlannedStartAt OR @Now >= @PlannedEndAt
        THROW 51509, N'Открыть смену можно только в её назначенном временном интервале.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'OPEN'),
        ActualOpenAt = @Now,
        ActualCloseAt = NULL,
        CloseReason = NULL,
        ClosedByUserId = NULL,
        WasClosedAutomatically = 0,
        IsWalkInShift = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N'Смена официанта открыта администратором. Столики распределены автоматически.' AS Message;
END
GO

/* ====== 4. Закрытие смен: после закрытия распределение обновляется ====== */
CREATE OR ALTER PROCEDURE dbo.sp_CloseCurrentWaiterShift
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
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
    ORDER BY ws.ActualOpenAt DESC, ws.ShiftId DESC;

    IF @ShiftId IS NULL
        THROW 51510, N'У вас нет открытой смены.', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51511, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
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
        THROW 51512, N'Нельзя закрыть смену: есть незавершённые заказы. Завершите обслуживание и закройте счета.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @UserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables;
    SELECT N'Смена закрыта. Столики перераспределены между оставшимися официантами.' AS Message;
END
GO

CREATE OR ALTER PROCEDURE dbo.sp_AdminCloseWaiterShift
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
          AND r.RoleCode = 'ADMIN'
    )
        THROW 51513, N'Закрывать смены может только администратор.', 1;

    DECLARE @Now DATETIME2 = SYSDATETIME();
    DECLARE @PlannedEndAt DATETIME2;
    DECLARE @StatusCode VARCHAR(30);

    SELECT @PlannedEndAt = ws.PlannedEndAt, @StatusCode = ss.StatusCode
    FROM dbo.WaiterShift ws
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    WHERE ws.ShiftId = @ShiftId;

    IF @StatusCode IS NULL
        THROW 51514, N'Смена не найдена.', 1;
    IF @StatusCode <> 'OPEN'
        THROW 51515, N'Закрыть можно только открытую смену.', 1;
    IF @Now < @PlannedEndAt AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51516, N'При досрочном закрытии смены обязательно укажите причину.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.CustomerOrder o
        JOIN dbo.OrderStatus os ON os.OrderStatusId = o.OrderStatusId
        WHERE os.StatusCode IN ('DRAFT', 'PLACED', 'PREPARING', 'READY', 'ACCEPTED', 'ISSUED')
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
        THROW 51517, N'Нельзя закрыть смену: у официанта есть незавершённые заказы.', 1;

    UPDATE dbo.WaiterShift
    SET
        ShiftStatusId = (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'CLOSED'),
        ActualCloseAt = @Now,
        CloseReason = NULLIF(LTRIM(RTRIM(@Reason)), N''),
        ClosedByUserId = @AdminUserId,
        WasClosedAutomatically = 0
    WHERE ShiftId = @ShiftId;

    EXEC dbo.sp_RebalanceOpenWaiterTables @AdminUserId = @AdminUserId;
    SELECT N'Смена официанта закрыта администратором. Столики перераспределены автоматически.' AS Message;
END
GO

/* ====== 5. Планирование смен администратором без ручного назначения столиков ====== */
CREATE OR ALTER PROCEDURE dbo.sp_AdminCreateWaiterShift
    @WaiterUserId INT,
    @PlannedStartAt DATETIME2,
    @PlannedEndAt DATETIME2,
    @TableNumbers NVARCHAR(400) = NULL /* оставлен для совместимости со старым интерфейсом; не используется */
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;

    IF @PlannedEndAt <= @PlannedStartAt
        THROW 51518, N'Время окончания смены должно быть позже времени начала.', 1;
    IF CONVERT(DATE, @PlannedStartAt) <> CONVERT(DATE, @PlannedEndAt)
       OR CONVERT(TIME, @PlannedStartAt) < CONVERT(TIME, '09:00:00')
       OR CONVERT(TIME, @PlannedEndAt) > CONVERT(TIME, '23:00:00')
       OR DATEDIFF(MINUTE, @PlannedStartAt, @PlannedEndAt) > 840
        THROW 51519, N'Смена должна быть в пределах одного дня, времени работы ресторана 09:00–23:00 и длиться не более 14 часов.', 1;

    DECLARE @WaiterId INT =
    (
        SELECT w.WaiterId
        FROM dbo.Waiter w
        JOIN dbo.AppUser u ON u.UserId = w.UserId
        JOIN dbo.AppRole r ON r.RoleId = u.RoleId
        WHERE w.UserId = @WaiterUserId
          AND u.IsActive = 1
          AND r.RoleCode = 'WAITER'
    );

    IF @WaiterId IS NULL
        THROW 51520, N'Выбранный пользователь не является активным официантом.', 1;

    IF EXISTS
    (
        SELECT 1
        FROM dbo.WaiterShift ws
        JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
        WHERE ws.WaiterId = @WaiterId
          AND ss.StatusCode IN ('PLANNED', 'OPEN')
          AND @PlannedStartAt < ws.PlannedEndAt
          AND @PlannedEndAt > ws.PlannedStartAt
    )
        THROW 51521, N'У официанта уже есть пересекающаяся смена.', 1;

    INSERT INTO dbo.WaiterShift
    (
        WaiterId, ShiftStatusId, PlannedStartAt, PlannedEndAt,
        ActualOpenAt, ActualCloseAt, CloseReason, ClosedByUserId,
        WasClosedAutomatically, IsWalkInShift
    )
    VALUES
    (
        @WaiterId,
        (SELECT ShiftStatusId FROM dbo.ShiftStatus WHERE StatusCode = 'PLANNED'),
        @PlannedStartAt, @PlannedEndAt,
        NULL, NULL, NULL, NULL, 0, 0
    );

    SELECT SCOPE_IDENTITY() AS ShiftId,
           N'Смена запланирована. Столики будут автоматически распределены при её открытии.' AS Message;
END
GO

/* ====== 6. Отображение смен: виден тип и автоматические столики ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetAdminWaiterShifts
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_AutoCloseExpiredWaiterShifts @ReturnResult = 0;

    SELECT
        ws.ShiftId,
        CONCAT(u.LastName, N' ', u.FirstName) AS [Официант],
        CASE WHEN ws.IsWalkInShift = 1 THEN N'Самостоятельная' ELSE N'По графику' END AS [Тип смены],
        ws.PlannedStartAt AS [Начало по графику],
        ws.PlannedEndAt AS [Конец по графику],
        ws.ActualOpenAt AS [Фактическое открытие],
        ws.ActualCloseAt AS [Фактическое закрытие],
        ss.StatusName AS [Статус],
        ISNULL(ws.CloseReason, N'—') AS [Причина закрытия],
        CASE WHEN ws.WasClosedAutomatically = 1 THEN N'Да' ELSE N'Нет' END AS [Автозакрытие],
        ISNULL(STRING_AGG(CONCAT(N'№', t.TableNumber), N', '), N'—') AS [Столики]
    FROM dbo.WaiterShift ws
    JOIN dbo.Waiter w ON w.WaiterId = ws.WaiterId
    JOIN dbo.AppUser u ON u.UserId = w.UserId
    JOIN dbo.ShiftStatus ss ON ss.ShiftStatusId = ws.ShiftStatusId
    LEFT JOIN dbo.WaiterTableAssignment a ON a.ShiftId = ws.ShiftId
    LEFT JOIN dbo.RestaurantTable t ON t.TableId = a.TableId
    GROUP BY
        ws.ShiftId, u.LastName, u.FirstName, ws.IsWalkInShift,
        ws.PlannedStartAt, ws.PlannedEndAt, ws.ActualOpenAt, ws.ActualCloseAt,
        ss.StatusName, ws.CloseReason, ws.WasClosedAutomatically
    ORDER BY ws.PlannedStartAt DESC, ws.ShiftId DESC;
END
GO

/* ====== 7. Получение столиков официанта: всегда с актуальным распределением ====== */
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
    @UserId INT
AS
BEGIN
    SET NOCOUNT ON;
    EXEC dbo.sp_RebalanceOpenWaiterTables;

    DECLARE @Now DATETIME2 = SYSDATETIME();

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
      AND @Now < ws.PlannedEndAt
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.7: самостоятельные смены и автоматическое распределение столиков добавлены.';
GO

/* ================== SQL_Update_v2_8_Waiter_Table_Assignment_Fix.sql ================== */
/*
 White Rabbit v2.8 — исправление отображения столиков у официанта.
 Выполните ОДИН РАЗ после SQL_Update_v2_7_Flexible_Shifts_And_Auto_Table_Distribution.sql.

 Причина исправления:
 sp_GetWaiterAssignedTables вызывала процедуру перераспределения, которая
 возвращала служебную таблицу первой. Приложение читало именно её вместо
 списка столиков, поэтому ComboBox «Столик» оставался пустым.
*/
USE WhiteRabbitRestaurant;
GO

/*
 @ReturnResult = 0 по умолчанию: при внутренних вызовах процедура не должна
 возвращать дополнительный result set и мешать следующему SELECT.
*/
CREATE OR ALTER PROCEDURE dbo.sp_RebalanceOpenWaiterTables
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
             AND r.RoleCode = 'ADMIN'
       )
        THROW 51501, N'Перераспределять столики может только администратор.', 1;

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
    WHERE ss.StatusCode = 'OPEN'
      AND u.IsActive = 1
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL;

    DECLARE @WaiterCount INT = (SELECT COUNT(*) FROM @OpenShifts);
    DECLARE @TableCount INT = (SELECT COUNT(*) FROM dbo.RestaurantTable WHERE IsActive = 1);

    IF @WaiterCount = 0
    BEGIN
        IF @ReturnResult = 1
            SELECT 0 AS WaiterCount, @TableCount AS TableCount,
                   N'Открытых смен нет: распределение столиков не требуется.' AS Message;
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
            N'Столики автоматически распределены между открытыми сменами официантов.' AS Message;
END
GO

/*
 Возвращает только список столиков, без служебных result set.
*/
CREATE OR ALTER PROCEDURE dbo.sp_GetWaiterAssignedTables
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
      AND ss.StatusCode = 'OPEN'
      AND ws.ActualOpenAt IS NOT NULL
      AND ws.ActualCloseAt IS NULL
      AND t.IsActive = 1
    ORDER BY t.TableNumber;
END
GO

PRINT N'White Rabbit v2.8: исправлено получение и отображение автоматически назначенных столиков.';
GO

/* ============================================================================
   ДОПОЛНИТЕЛЬНЫЕ ПРОЦЕДУРЫ ДЛЯ ПОЛНОЙ СОВМЕСТИМОСТИ С ИНТЕРФЕЙСОМ v2.8
============================================================================ */
USE WhiteRabbitRestaurant;
GO

/* Регистрация клиента из формы регистрации приложения. */
CREATE OR ALTER PROCEDURE dbo.sp_RegisterClient
    @Login NVARCHAR(50),
    @Password NVARCHAR(128),
    @LastName NVARCHAR(60),
    @FirstName NVARCHAR(60),
    @Phone NVARCHAR(30)
AS
BEGIN
    SET NOCOUNT ON;

    IF LEN(@Password) < 6
        THROW 51002, N'Пароль должен содержать минимум 6 символов.', 1;

    DECLARE @CreatedUser TABLE
    (
        UserId INT,
        Message NVARCHAR(250)
    );

    INSERT INTO @CreatedUser (UserId, Message)
    EXEC dbo.sp_RegisterUser
        @Login = @Login,
        @Password = @Password,
        @RoleCode = 'CLIENT',
        @LastName = @LastName,
        @FirstName = @FirstName,
        @MiddleName = NULL,
        @Phone = @Phone,
        @Email = NULL;

    DECLARE @UserId INT = (SELECT TOP (1) UserId FROM @CreatedUser);

    INSERT INTO dbo.Client (UserId, FullName, Phone)
    VALUES (@UserId, CONCAT(@LastName, N' ', @FirstName), @Phone);

    SELECT @UserId AS UserId, N'Клиент успешно зарегистрирован.' AS Message;
END;
GO

/* Доступное меню клиента и официанта. */
CREATE OR ALTER PROCEDURE dbo.sp_GetAvailableMenu
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
END;
GO

/* Полный список блюд для рабочего места кухни. */
CREATE OR ALTER PROCEDURE dbo.sp_GetKitchenDishes
AS
BEGIN
    SET NOCOUNT ON;

    SELECT
        d.DishId,
        d.DishName AS [Блюдо],
        c.CategoryName AS [Категория],
        d.BasePrice AS [Цена, руб.],
        s.AvailablePortions AS [Остаток, порций],
        CASE WHEN ISNULL(sl.IsStopListed, 0) = 1 THEN N'Да' ELSE N'Нет' END AS [Стоп-лист],
        sl.Reason AS [Причина]
    FROM dbo.Dish d
    JOIN dbo.DishCategory c ON c.CategoryId = d.CategoryId
    JOIN dbo.DishStock s ON s.DishId = d.DishId
    LEFT JOIN dbo.DishStopList sl ON sl.DishId = d.DishId
    ORDER BY c.CategoryName, d.DishName;
END;
GO

/* Позиции текущего заказа или корзины. */
CREATE OR ALTER PROCEDURE dbo.sp_GetOrderItems
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
END;
GO

/* Управление стоп-листом из рабочего места кухни. */
CREATE OR ALTER PROCEDURE dbo.sp_SetDishStopListStatus
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
          AND r.RoleCode IN ('KITCHEN', 'ADMIN')
    )
        THROW 51010, N'Изменять стоп-лист могут только кухня и администратор.', 1;

    IF NOT EXISTS (SELECT 1 FROM dbo.Dish WHERE DishId = @DishId)
        THROW 51011, N'Блюдо не найдено.', 1;

    IF @IsStopListed = 1 AND NULLIF(LTRIM(RTRIM(@Reason)), N'') IS NULL
        THROW 51012, N'Укажите причину добавления блюда в стоп-лист.', 1;

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
             THEN N'Блюдо добавлено в стоп-лист.'
             ELSE N'Блюдо убрано из стоп-листа.'
        END AS Message;
END;
GO

/* Финальная проверка: выводит тестовые учётные записи и ключевые процедуры. */
SELECT
    u.Login,
    r.RoleCode,
    CONCAT(u.LastName, N' ', u.FirstName) AS FullName,
    u.IsActive
FROM dbo.AppUser u
JOIN dbo.AppRole r ON r.RoleId = u.RoleId
ORDER BY u.UserId;
GO

PRINT N'Базовая часть единого скрипта White Rabbit v2.8 успешно выполнена.';
GO
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


/* ================== SQL_Update_v3_0_Reservation_Privacy_And_Waiter_Bookings.sql ================== */
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

PRINT N'Единый скрипт White Rabbit v3.0 успешно выполнен.';
GO
