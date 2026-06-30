/* Проверка состояния после работы официанта. */
USE WhiteRabbitRestaurant;
GO

/* Активные заказы: ISSUED означает выдан, но счёт ещё не закрыт. */
SELECT
    o.OrderId,
    t.TableNumber,
    s.StatusCode,
    s.StatusName,
    b.Amount,
    b.IssuedAt,
    b.IsPaid,
    b.PaidAt,
    b.PaymentMethod,
    b.ReceiptNumber
FROM dbo.CustomerOrder o
JOIN dbo.RestaurantTable t ON t.TableId = o.TableId
JOIN dbo.OrderStatus s ON s.OrderStatusId = o.OrderStatusId
LEFT JOIN dbo.Bill b ON b.OrderId = o.OrderId
ORDER BY o.OrderId DESC;
GO

/* После закрытия счёта у заказа статус COMPLETED, а столик в схеме — «Свободен». */
SELECT * FROM dbo.vw_TableScheme ORDER BY [№ столика];
GO
