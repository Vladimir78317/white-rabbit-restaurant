WHITE RABBIT v2.8 — FIX FOR WAITER TABLES

Problem fixed
-------------
The waiter shift could open successfully, but the Table combo box remained empty.
The database procedure returned a technical result set from automatic distribution
before it returned the waiter table list. The WinForms application read the first
result set, which did not contain TableId/TableNumber.

What changed
------------
1. sp_RebalanceOpenWaiterTables no longer returns a technical result set by default.
2. sp_GetWaiterAssignedTables returns only TableId, TableNumber, SeatsCount and HallZone.
3. Open shifts with unfinished orders keep their assigned tables even if planned end time passed.
4. Waiter screen selects the first assigned table automatically.
5. The waiter screen has an "Обновить столики" button.
6. If the v2.8 SQL update was not applied, the application shows a clear message instead of a silent empty list.

How to install
--------------
1. Extract the archive.
2. In SSMS, run:
   WhiteRabbitRestaurant\SQL_Update_v2_8_Waiter_Table_Assignment_Fix.sql
3. In Visual Studio:
   Restore NuGet Packages -> Clean Solution -> Rebuild Solution -> F5
4. Open or refresh the waiter shift and click "Обновить столики".
