WHITE RABBIT v2.6 — RESERVATION PROCEDURE FIX AND CLIENT TABLE MAP

INSTALLATION
1. In SQL Server Management Studio, open and run:
   WhiteRabbitRestaurant\SQL_Update_v2_6_Reservation_Procedure_And_Table_Map.sql

2. In Visual Studio:
   Restore NuGet Packages -> Clean Solution -> Rebuild Solution -> F5

WHAT CHANGED
- Reservation now uses dbo.sp_CreateReservationSafe instead of the old stored procedure.
- This resolves the error: "too many arguments were specified for sp_CreateReservationByClientName".
- The v2.6 SQL script also corrects the old unique Client.UserId rule.
- Client > Booking now includes a visual table map.
- Select the start time, end time and guest count; then click a green table tile.
- Green = available, grey = booked or insufficient seats.

TEST
Run SQL_Test_Reservation_Procedure_And_Table_Map_v2_6.sql after the update if you want to verify the procedures.


--- v2.7 ---
Execute SQL_Update_v2_7_Flexible_Shifts_And_Auto_Table_Distribution.sql after v2.6.
Flexible waiter shifts and automatic table distribution are available.
