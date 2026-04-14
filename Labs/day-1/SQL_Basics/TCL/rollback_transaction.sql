-- Rollback statement restores the database to last committed state. 

-- It's also used with savepoint command to jump to a savepoint. 

use amdocssqltraining
GO 

BEGIN TRANSACTION;
DELETE FROM Customers.Customer WHERE FirstName = 'Matt'
ROLLBACK TRANSACTION;

select * from Customers.Customer

