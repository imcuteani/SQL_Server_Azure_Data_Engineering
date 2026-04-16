use master
ALTER ROLE db_datareader ADD MEMBER Ben;
GO

-- List of all database level principals which are members of database level role. 

SELECT roles.principal_id AS RolePrincipalID,
    roles.name AS RolePrincipalName,
    database_role_members.member_principal_id AS MemberPrincipalID,
    members.name AS MemberPrincipalName
FROM sys.database_role_members AS database_role_members
INNER JOIN sys.database_principals AS roles
    ON database_role_members.role_principal_id = roles.principal_id
INNER JOIN sys.database_principals AS members
    ON database_role_members.member_principal_id = members.principal_id;
GO