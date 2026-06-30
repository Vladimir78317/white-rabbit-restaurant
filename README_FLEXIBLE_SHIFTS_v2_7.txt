WHITE RABBIT v2.7 — FLEXIBLE SHIFTS AND AUTO TABLE DISTRIBUTION

1. In SSMS execute:
   SQL_Update_v2_7_Flexible_Shifts_And_Auto_Table_Distribution.sql

2. In Visual Studio:
   Restore NuGet Packages -> Clean Solution -> Rebuild Solution -> F5

NEW RULES
- An administrator can create a scheduled shift as before.
- A waiter may click "Open shift / arrive for shift" without a schedule.
  The self-opened shift lasts until 23:00 on the same day.
- A waiter cannot open a self-service shift before 09:00, after 23:00, or when a future scheduled shift exists for that day.
- Every opened shift is shown on the administrator's "Shifts and tables" page.
- All active restaurant tables are allocated round-robin across all open waiter shifts.
- Opening or closing a shift automatically recalculates assignments.
- The administrator may force an immediate recalculation using "Distribute tables".

IMPORTANT
The database update must be executed before starting the updated application.
