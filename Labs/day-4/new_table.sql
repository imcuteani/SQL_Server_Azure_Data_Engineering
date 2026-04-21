-- create these new SQL tables -- 

use publisher;
GO 

-- create schema -- 

--CREATE SCHEMA HumanResources AUTHORIZATION dbo 
--GO 

-- create Employee table -- 
/*
CREATE TABLE HumanResources.Employee
(EmployeeID INT IDENTITY(1,1),
FirstName VARCHAR(50) NOT NULL,
LastName VARCHAR(50) NOT NULL,
JobTitle VARCHAR(50) NOT NULL,
BirthDate DATE NOT NULL,
HireDate DATE NOT NULL)
GO 

-- create EmployeeAddress table -- 

CREATE TABLE HumanResources.EmployeeAddress
(AddressID INT IDENTITY(1,1),
AddressType VARCHAR(20) NOT NULL,
AddressLine1 VARCHAR(50) NOT NULL,
AddressLine2 VARCHAR(50) NULL,
AddressLine3 VARCHAR(50) NULL,
City VARCHAR(50) NOT NULL,
StateProvince VARCHAR(50) NULL,
Country VARCHAR(50) NULL)
GO
*/

-- insert into tables -- 

--SET IDENTITY_INSERT [HumanResources].[Employee] ON

INSERT INTO [HumanResources].[Employee] (EmployeeID, FirstName, LastName, JobTitle, BirthDate, HireDate) VALUES (1, 'Jim','Webb', 'Engineer', '2000-01-15', '2022-03-02');
INSERT INTO [HumanResources].[Employee] (EmployeeID, FirstName, LastName, JobTitle, BirthDate, HireDate) VALUES (2, 'Ben','Mario', 'Architect', '1988-03-02', '2024-02-02');
GO

-- Set IDENTITY_INSERT OFF 
--SET IDENTITY_INSERT [HumanResources].[Employee] OFF


--SET IDENTITY_INSERT [HumanResources].[EmployeeAddress] ON
INSERT INTO [HumanResources].[EmployeeAddress] (AddressID, AddressType, AddressLine1, AddressLine2, AddressLine3, City, StateProvince, Country ) VALUES (1, 'Official','1, Seattle Washington', 'old parkway', 'New office', 'Seattle', 'WA', 'US');
INSERT INTO [HumanResources].[EmployeeAddress] (AddressID, AddressType, AddressLine1, AddressLine2, AddressLine3, City, StateProvince, Country ) VALUES (2, 'Cargo','5201, Detroit Way', 'old freeway', 'New Orleans', 'Chicago', 'IL', 'US');
-- Set IDENTITY_INSERT OFF 
--SET IDENTITY_INSERT [HumanResources].[Employee] OFF
