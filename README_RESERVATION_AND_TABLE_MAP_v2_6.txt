WHITE RABBIT v2.6 — RESERVATION FIX AND CLIENT TABLE MAP

WHAT WAS FIXED
1. Reservation no longer calls the old sp_CreateReservationByClientName procedure.
   The application now calls the new sp_CreateReservationSafe procedure with exactly 8 parameters.
   This fixes the SQL Server message: "too many arguments were specified".
2. The SQL script independently removes the old unique constraint that prevented multiple guest clients with UserId = NULL.
3. The Client > Booking screen now has a visual table map:
   - green tile = free table;
   - grey tile = unavailable at the selected time / too few seats;
   - clicking a green table fills the Table field automatically.

REQUIRED INSTALLATION STEP
Before starting the updated application, run this script in SQL Server Management Studio:
WhiteRabbitRestaurant\SQL_Update_v2_6_Reservation_Procedure_And_Table_Map.sql

Then in Visual Studio:
Restore NuGet Packages -> Clean Solution -> Rebuild Solution -> F5

IMPORTANT
Run the v2.6 SQL script even if you previously ran the v2.5 script.
