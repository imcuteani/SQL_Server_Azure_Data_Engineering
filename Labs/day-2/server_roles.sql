SELECT *
FROM sys.fn_builtin_permissions('SERVER')
ORDER BY permission_name;