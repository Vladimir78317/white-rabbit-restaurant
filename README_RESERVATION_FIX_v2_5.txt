WHITE RABBIT v2.5 — RESERVATION FIX

Problem fixed
-------------
When creating the second reservation for a guest without an account, SQL Server returned:
"Violation of UNIQUE KEY constraint ... dbo.Client. Duplicate key value: (NULL)".

Cause
-----
The old UNIQUE constraint on Client.UserId allowed only one NULL value.
Guest reservations create Client records with UserId = NULL, so the second guest caused an error.

What changed
------------
1. SQL_Update_v2_5_Reservation_Guest_Client_Fix.sql removes the old UNIQUE constraint.
2. It creates UX_Client_UserId_NotNull: UserId is unique only when it is filled.
3. The reservation procedure was updated:
   - a registered client reservation uses the existing Client profile by UserId;
   - a guest reservation reuses a guest record by full name and phone;
   - a new guest record can be added with UserId = NULL without conflicts.
4. MainForm.cs passes UserId only when a client is logged in.

Installation
------------
1. Close the White Rabbit application.
2. Open SQL Server Management Studio.
3. Select the WhiteRabbitRestaurant database.
4. Run SQL_Update_v2_5_Reservation_Guest_Client_Fix.sql ONE TIME.
5. Open WhiteRabbitRestaurant.sln in Visual Studio.
6. Run Restore NuGet Packages, then Clean Solution, Rebuild Solution, and F5.

Verification
------------
Run SQL_Test_Reservation_Guest_Client_Fix_v2_5.sql in SSMS.
