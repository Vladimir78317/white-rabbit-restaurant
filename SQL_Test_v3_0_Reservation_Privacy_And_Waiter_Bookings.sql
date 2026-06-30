/*
 Быстрая проверка установки White Rabbit v3.0.
 Выполняйте после SQL_Update_v3_0_Reservation_Privacy_And_Waiter_Bookings.sql.
*/
USE WhiteRabbitRestaurant;
GO

SELECT name AS [Процедура],
       CASE WHEN OBJECT_ID(N'dbo.' + name, N'P') IS NOT NULL THEN N'Найдена' ELSE N'Не найдена' END AS [Результат]
FROM (VALUES
    (N'sp_GetClientReservations'),
    (N'sp_CancelReservation'),
    (N'sp_GetWaiterReservationDayTableMap'),
    (N'sp_GetWaiterReservationsByTableAndDate'),
    (N'sp_GetAdminWaiterShiftsFiltered')
) procedures(name);
GO

/*
 Проверка личного списка бронирований для тестового клиента client1.
 При отсутствии тестовой учетной записи вернется понятная ошибка.
*/
DECLARE @ClientUserId INT =
(
    SELECT TOP (1) UserId
    FROM dbo.AppUser
    WHERE Login = N'client1'
);

IF @ClientUserId IS NOT NULL
    EXEC dbo.sp_GetClientReservations @UserId = @ClientUserId;
ELSE
    PRINT N'Тестовая учетная запись client1 не найдена: проверка личных броней пропущена.';
GO
