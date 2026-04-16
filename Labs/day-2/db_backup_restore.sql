USE master;  
--Make sure the database is using the simple recovery model.  
ALTER DATABASE AdventureWorks2022 SET RECOVERY SIMPLE;  
GO  
-- Back up the full AdventureWorks2022 database.  
BACKUP DATABASE AdventureWorks2022   
TO DISK = 'F:\SQLServerBackups\AdventureWorks2022.bak'   
  WITH FORMAT;  
GO  
--Create a differential database backup.  
BACKUP DATABASE AdventureWorks2022   
TO DISK = 'F:\SQLServerBackups\AdventureWorks2022.bak'  
   WITH DIFFERENTIAL;  
GO  
--Restore the full database backup (from backup set 1).  
RESTORE DATABASE AdventureWorks2022   
FROM DISK = 'F:\SQLServerBackups\AdventureWorks2022.bak'   
   WITH FILE=1, NORECOVERY;  
--Restore the differential backup (from backup set 2).  
RESTORE DATABASE AdventureWorks2022   
FROM DISK = 'F:\SQLServerBackups\AdventureWorks2022.bak'   
   WITH FILE=2, RECOVERY;  
GO